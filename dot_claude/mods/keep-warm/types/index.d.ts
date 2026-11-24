export type KeepWarmPlan = { hours: number; until: number } | null

declare module 'claude-code' {
  interface PluginState {
    'keep-warm': { plan: KeepWarmPlan }
  }
}
