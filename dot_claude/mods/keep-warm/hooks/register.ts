import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

// The cache lives 1 hour on a Claude subscription and every read resets it (prompt caching docs).
// A ping 55 minutes after the last request costs a cache read (~0.1x the prefix); letting it lapse
// costs a rewrite (2x) the next time he types. Break-even is ~19 idle hours, so the default cap is 8.
const PING_AFTER_MS = 55 * 60_000
const CHECK_EVERY_MS = 60_000
const DEFAULT_HOURS = 8
// Every session starts with this plan, so parallel sessions that wait on CI or a review keep
// their cache without a /keepwarm each. A prompt restarts the window. "/keepwarm off" stops it.
const AUTO_HOURS = 3
const MAX_HOURS = 24
const MIN_TOKENS = 30_000 // below this a rewrite is cheap; not worth a ping
const WARM_SHARE = 0.5 // a ping that read less than half the context found the cache cold
const PING_PROMPT = 'Keep-alive ping to hold the prompt cache. Reply with only: ok'

const plan = atom({ plugin: 'keep-warm', key: 'plan' } as const, null)

// "/keepwarm", "/keepwarm 4h", "/keepwarm 90m", "/keepwarm off", "/keepwarm ping".
export function parseArgs(args: string): { kind: 'on'; hours: number } | { kind: 'off' } | { kind: 'ping' } | { kind: 'bad' } {
  const a = args.trim().toLowerCase()
  if (a === '' || a === 'on') return { kind: 'on', hours: DEFAULT_HOURS }
  if (a === 'off' || a === 'stop') return { kind: 'off' }
  if (a === 'ping' || a === 'now') return { kind: 'ping' }
  const m = a.match(/^(\d+(?:\.\d+)?)\s*(h|m)?$/)
  if (!m) return { kind: 'bad' }
  const hours = Number(m[1]) / (m[2] === 'm' ? 60 : 1)
  return hours > 0 && hours <= MAX_HOURS ? { kind: 'on', hours } : { kind: 'bad' }
}

// Should a ping go out now? Null means yes; otherwise the reason it waits or stops.
export function pingDecision(s: {
  now: number
  lastRequestAt: number
  isBusy: boolean
  until: number
  contextTokens: number | undefined
  onCredits: boolean
}): null | 'busy' | 'not-due' | 'expired-plan' | 'small' | 'credits' {
  if (s.now >= s.until) return 'expired-plan'
  if (s.isBusy) return 'busy'
  if (s.now - s.lastRequestAt < PING_AFTER_MS) return 'not-due'
  if (s.onCredits) return 'credits'
  if ((s.contextTokens ?? 0) < MIN_TOKENS) return 'small'
  return null
}

export const wasWarm = (read: number, contextTokens: number | undefined) => read >= (contextTokens ?? 0) * WARM_SHARE

const inMinutes = (ms: number) => `in ${Math.max(0, Math.round((ms - Date.now()) / 60_000))} min`
const kTokens = (n: number) => `${Math.round(n / 1000)}k`

// Module state: a reload starts these over, and a (re)load lands right after a turn, so the cache was just used.
let lastRequestAt = Date.now()
let isBusy = false
let pings = 0
let lastRead = 0
let isPinging = false

async function status($: EngineInterface, note?: string) {
  const p = await read($, plan)
  if (!p) return $.ui.status(note)
  const next = inMinutes(lastRequestAt + PING_AFTER_MS)
  $.ui.status(note ?? `cache kept warm · next ${next} · ${pings} ping${pings === 1 ? '' : 's'}${lastRead ? ` · read ${kTokens(lastRead)}` : ''}`)
}

async function ping($: EngineInterface, contextTokens: number | undefined): Promise<string> {
  isPinging = true
  const startedAt = Date.now()
  try {
    const r = await $.model.fork({ prompt: PING_PROMPT })
    if (!r.isAnswered && r.reason === 'nothing-to-fork') return 'nothing to keep warm yet (no reply in this session)'
    lastRequestAt = startedAt
    lastRead = r.usage.cache_read_input_tokens
    pings += 1
    const warm = wasWarm(lastRead, contextTokens)
    return `${warm ? 'warm' : 'COLD'}: read ${kTokens(lastRead)} from cache, wrote ${kTokens(r.usage.cache_creation_input_tokens)}`
  } finally {
    isPinging = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'keepwarm', description: 'Keep this session’s prompt cache warm while idle: /keepwarm [4h|off|ping]' })
    if (!(await read($, plan))) await update($, plan, () => ({ hours: AUTO_HOURS, until: Date.now() + AUTO_HOURS * 3_600_000 }))
    $.clock.every(CHECK_EVERY_MS, () => {
      void (async () => {
        const p = await read($, plan)
        if (!p || isPinging) return
        const usage = await $.session.usage()
        const why = pingDecision({
          now: Date.now(),
          lastRequestAt,
          isBusy,
          until: p.until,
          contextTokens: usage.context.tokens,
          onCredits: usage.rateLimits.some(r => r.percentUsed >= 100),
        })
        if (why === 'expired-plan') {
          await update($, plan, () => null)
          return $.ui.status(`keep-warm ended after ${p.hours}h idle`)
        }
        if (why === 'credits') return status($, 'keep-warm paused: on usage credits, the cache is 5 minutes there')
        if (why === 'small') return status($, 'keep-warm idle: context under 30k tokens, a rewrite is cheap')
        if (why !== null) return status($)
        const result = await ping($, usage.context.tokens)
        if (result.startsWith('COLD')) {
          await update($, plan, () => null)
          $.ui.toast(`keep-warm stopped: the cache was already cold (${result}). It may be a 5-minute cache here.`)
          return $.ui.status(undefined)
        }
        return status($)
      })().catch(() => undefined)
    })
    return next(e)
  })

  on('command.run', { command: 'keepwarm' }, async ($, e) => {
    const arg = parseArgs(e.args)
    if (arg.kind === 'bad') return { text: 'Use /keepwarm, /keepwarm 4h (up to 24h), /keepwarm off or /keepwarm ping.' }
    if (arg.kind === 'off') {
      await update($, plan, () => null)
      $.ui.status(undefined)
      return { text: 'keep-warm is off for this session.' }
    }
    if (arg.kind === 'ping') {
      const usage = await $.session.usage()
      const result = await ping($, usage.context.tokens)
      await status($)
      return { text: `keep-warm ping: ${result}.` }
    }
    await update($, plan, () => ({ hours: arg.hours, until: Date.now() + arg.hours * 3_600_000 }))
    await status($)
    return { text: `keep-warm is on: the cache stays warm for up to ${arg.hours}h of idle. A tiny ping goes out 55 minutes after the last request.` }
  })

  // Each main-loop request resets the cache's hour; subagents have their own prefixes.
  on('turn.step', async function* ($, e, next) {
    if (!e.agentId) lastRequestAt = Date.now()
    return yield* next(e)
  })

  // A typed prompt restarts the idle window; the turn keeps the cache warm by itself.
  on('prompt.submit', async ($, e, next) => {
    isBusy = true
    const p = await read($, plan)
    if (p && e.origin.kind !== 'plugin') await update($, plan, () => ({ hours: p.hours, until: Date.now() + p.hours * 3_600_000 }))
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const ran = await next(e)
    if (e.agentId === undefined) {
      isBusy = false
      await status($)
    }
    return ran
  })
}
