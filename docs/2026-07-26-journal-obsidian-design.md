# Journal — diário de trabalho e estudo no Obsidian

**Data:** 2026-07-26
**Status:** aprovado, pronto para plano de implementação

## Problema

As notas em `Documents/Dump/Tasks/MM Mês/Semana NN.md` acumulam quatro coisas
distintas no mesmo arquivo: backlog solto, plano semanal com ETA, checklists
diários e dump livre (threads do Slack, tickets do Jira, specs de produto,
tabelas de dados, credenciais).

Três consequências observadas nos arquivos reais:

1. **Duplicação de estado.** Uma nota semanal repete o mesmo ticket três vezes —
   uma em `# Plano`, uma em `# Segunda`, uma em `# Terça` — cada ocorrência com
   seu próprio checkbox. Não existe fonte da verdade.
2. **Assunto que atravessa semanas é copiado.** A mesma tabela de dados aparece
   idêntica em duas semanas seguidas.
3. **Nada é linkável.** Decisões e threads morrem dentro do arquivo da semana.
   Não viram nó do grafo, não têm backlink, não são recuperáveis por assunto.

Falta um lugar para o que **não é tarefa**: decisões tomadas e o porquê, threads
importantes, links, tickets, material de estudo.

## Objetivo

Um diário no vault do Obsidian que:

- Registra decisões, threads, tickets, links e estudo — não só TODOs.
- É escrito pela IA em qualquer sessão (Claude Code ou Codex), sem divergência.
- Conecta o grafo do Obsidian via wikilinks e notas atômicas.
- Cria a nota do dia sozinho em dias úteis e carrega o que ficou aberto.
- Não altera o hábito de planejar a semana.

## Restrições

- **Sem path hardcoded.** Caminho do vault vem de config gerada pelo chezmoi.
- **Portável entre agentes.** Claude Code e Codex compartilham o mesmo schema de
  hooks (`PreToolUse`, `PostToolUse`, `SessionStart`, `UserPromptSubmit`, `Stop`,
  `PreCompact`) e o mesmo mecanismo `hookSpecificOutput.additionalContext`. Codex
  não tem `SessionEnd`.
- **Tudo versionado no chezmoi.**
- **Vault hoje é vanilla** — zero plugins da comunidade instalados.
- **Não pode atrapalhar o fluxo.** Nada escreve no diário sem passar pelo modelo,
  e o lembrete é raro.

## Decisões de design

### Script é o dono, não os plugins

Plugin de Obsidian só executa com o app aberto. O requisito é que a nota do dia
exista em dias úteis independente disso, então um job `launchd` cria o arquivo.
Como consequência, **não** se instala o plugin Rollover — se ele e o script
tentassem criar/rolar a mesma nota, haveria dupla escrita por caminhos
diferentes, que falha em silêncio.

Plugins de leitura pura (Dataview, Calendar) não conflitam e entram.

Alternativas descartadas:

- **Obsidian dono** (Periodic Notes + Templater + Rollover): zero código de
  rollover para manter, mas sem nota quando o app fica fechado, e a config vive
  em `.obsidian/`, fora do chezmoi.
- **Híbrido** (script cria, Templater define template): o script teria que
  interpretar sintaxe de Templater. Peças móveis demais para o ganho.

### Hook nudge em vez de escrita automática

Hook é comando shell, não chamada de LLM — só consegue despejar dado bruto. Uma
entrada de diário útil exige julgamento sobre o que merece registro.

Então o hook **pergunta ao modelo** que já está na sessão, via
`additionalContext` no `UserPromptSubmit`, em vez de tentar escrever. Custo: uma
linha injetada, e só quando o throttle abre. Sem chamada headless, sem token
gasto à toa.

`Stop` foi descartado: para instruir o modelo ali é preciso bloquear, o que
interrompe o fluxo e arrisca loop. `SessionEnd` foi descartado: dispara em
`clear`, `resume`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled` e
`other` — fechar a janela do terminal mata o processo sem rodar o hook, e é
exatamente o padrão de uso do usuário. Além disso Codex não tem esse evento.

### Rollover copia, não move

O arquivo do dia anterior é o registro daquele dia e não é mutado. Item
não-ticado é **copiado** para a nota nova com marcador de origem:

```markdown
- [ ] PROJ-102 alguma tarefa  ↳ aberto desde [[2026-07-24]]
```

Item que arrasta cinco dias fica visível como tal, em vez de sumir na
renumeração. "Dia anterior" é o último arquivo que existe varrendo para trás —
isso pula fim de semana, feriado e dia não trabalhado sem lógica de calendário.

### ai-memory não é a fonte

O ai-memory já captura via hooks, mas é escopado por `repo-root`. Uma semana
atravessa vários repositórios e muita coisa fora de repositório (threads,
reuniões, Jira). Reconstruir exigiria varrer N projetos e reconciliar. O `/log`
no momento da conversa já tem o contexto de graça.

Os dois coexistem: ai-memory é memória de projeto para o agente; o Journal é
registro cronológico de trabalho para a pessoa.

## Arquitetura

Três camadas. A de baixo é o contrato — as de cima só a consomem.

```
launchd (seg-sex 07:00) ─┐
                         ├─→ journal (script bash) ──→ Obsidian vault
/log (Claude | Codex)  ──┤         ↑
                         │         │ config sem hardcode
hook nudge ──────────────┘   ~/.config/journal/config.sh
```

### Camada 1 — script `journal`

Bash puro, sem IA. Único componente que conhece o layout do vault.

| Comando | Efeito |
|---|---|
| `journal ensure-today` | Cria a nota do dia e faz rollover. Idempotente. Chamado pelo launchd. |
| `journal ensure-week` | Cria a semanal ISO e move compromisso não fechado da anterior para `## Radar`. Segunda. |
| `journal today` | Imprime o path da nota do dia, criando se faltar. |
| `journal append --section <S> --text <T>` | Append na seção. Seções: `Plano`, `Decisões`, `Threads`, `Tickets`, `Estudos`, `Notas`. |
| `journal entity --type <decision\|ticket\|study> --name <N>` | Cria (ou retorna) a nota atômica e imprime o path. |
| `journal status` | Minutos desde o último append no stream do cwd. Usado pelo hook. |

Sai com código diferente de zero e mensagem em stderr quando a seção não existe
ou o vault não é encontrado — o agente precisa perceber a falha, não engolir.

### Camada 2 — comando `/log`

A skill chama-se `log`, então o gatilho é `/log`. O Codex lê a mesma
`SKILL.md` por symlink, de modo que as duas cópias não podem divergir.
Instrui o modelo a extrair da conversa o que merece registro, classificar por
seção, criar notas atômicas para entidades recorrentes e chamar o script.

O modelo nunca monta path. Só invoca `journal`.

### Camada 3 — hook nudge

`journal-nudge.sh` registrado em `UserPromptSubmit` nos dois agentes. Emite
`additionalContext` apenas quando ambas as condições valem:

- `cwd` está sob um root vigiado no config;
- `journal status` retorna mais de 90 minutos.

Caso contrário sai 0 em silêncio. Texto injetado:

```
journal: 90min sem registro neste projeto. Se houve decisão, thread ou ticket
que valha memória, registre com `journal append`. Se não houve, ignore.
```

Registrar não reseta só por ter sido lembrado — o timer reseta no append.

## Layout do vault

```
Documents/Dump/
  Journal/
    2026/07/2026-07-27.md              nota do dia
    weeks/2026-W31.md                  nota da semana (ISO)
    decisions/Alguma Decisão.md        nota atômica
    entities/PROJ-201.md               ticket como nó do grafo
    study/Anthropic Academy — Tool Use.md
  Tasks/                               CONGELADO — leitura, sem migração
    07 Julho/Semana NN.md
```

Semana em ISO week resolve um defeito do esquema atual: a semana 31 vai de
27/jul a 2/ago, e a convenção `MM Mês/Semana NN` não decide em que pasta ela
mora.

### Nota do dia

```markdown
---
date: 2026-07-27
weekday: seg
streams: [work]
---
# 2026-07-27 · Segunda
← [[2026-07-24]] · [[2026-W31]] · [[2026-07-28]] →

## Plano
- [ ] PROJ-102 alguma tarefa  ↳ aberto desde [[2026-07-24]]

## Decisões
## Threads
## Tickets
## Estudos
## Notas
```

### Nota da semana

````markdown
---
week: 2026-W31
range: 2026-07-27 → 2026-08-02
---
# 2026-W31

## Compromissos
- [[PROJ-102]] alguma promessa — ETA qua

## Radar
Não é desta semana.
- Algo grande que não é desta semana

## Semana
```dataview
TASK FROM "Journal/2026"
WHERE file.day >= date(2026-07-27) AND file.day <= date(2026-08-02)
GROUP BY file.link
```

## Retro
````

O dia é dono da execução; a semana é dona do compromisso. As seções
`# Segunda`…`# Sexta` deixam de existir — o estado vem da query, não de cópia
manual. `## Radar` torna explícito o que não foi assumido, que hoje se confunde
com o que foi. Compromisso não cumprido volta para `## Radar` da semana
seguinte, nunca para `## Compromissos` — reassumir é ato deliberado.

Dump livre (tabelas, specs, credenciais) sai da nota da semana e vira nota de
tópico em `Journal/entities/`.

## Streams

O config lista os roots vigiados com rótulo:

| Root | Stream |
|---|---|
| `~/Developer/Work/*` | work |
| `~/Developer/Learning/*` | study |

O stream determina se o nudge dispara, o frontmatter da nota do dia e onde a
nota atômica nasce (`study/` versus `decisions/`/`entities/`).

## Distribuição via chezmoi

| Peça | Source | Alvo |
|---|---|---|
| Script | `dot_local/bin/executable_journal` | `~/.local/bin/journal` |
| Config | `dot_config/journal/config.sh.tmpl` | `~/.config/journal/config.sh` |
| launchd | `dot_config/journal/com.barsotti.journal.plist.tmpl` | `~/Library/LaunchAgents/` |
| Hook | `dot_claude/hooks/executable_journal-nudge.sh` | `~/.claude/hooks/` |
| Hook (Codex) | `dot_codex/hooks/executable_journal-nudge.sh` | `~/.codex/hooks/` |
| Skill | `dot_claude/skills/log/SKILL.md` | `~/.claude/skills/log/` |
| Skill (Codex) | `dot_codex/skills/log/symlink_SKILL.md.tmpl` | symlink para a cópia do Claude |
| Registro do hook | `dot_claude/settings.json.tmpl` | já gerenciado |
| Registro do hook | `dot_codex/hooks.json` | **novo no chezmoi** |

O path do vault vem de `.chezmoidata/journal.yaml`, condicionado a
`machine.purpose` — máquina de trabalho e pessoal podem apontar para vaults
diferentes.

`launchd` usa `StartCalendarInterval` com `Weekday` de 1 a 5 às 07:00. Se a
máquina estiver dormindo no horário, o launchd executa ao acordar; `journal
ensure-today` sendo idempotente, rodar tarde ou duas vezes é inofensivo.

**Drift a corrigir:** `~/.codex/hooks.json` não é gerenciado hoje — os hooks do
Codex existem apenas nesta máquina e não se reproduzem num setup novo. Trazê-lo
para o chezmoi é pré-requisito para registrar o nudge no Codex.

## Plugins do Obsidian

Instalar **Dataview** (query das pendências na nota da semana) e **Calendar**
(navegação por data). Ambos são leitura pura.

Não instalar Rollover Daily Todos, Periodic Notes nem Templater — colidem com a
propriedade do script sobre criação e rollover.

Sem esses plugins o sistema continua funcionando: grafo, backlink e wikilink são
core do Obsidian. Só a query da seção `## Semana` deixaria de renderizar.

## Fora de escopo

- **Backfill.** `Journal/` nasce vazio. `Tasks/` fica como arquivo consultável.
- Migrar o conteúdo existente para notas atômicas.
- Sincronização do vault entre máquinas.
- Integração via MCP com o Obsidian — acesso direto a arquivo já basta.

## Riscos

| Risco | Mitigação |
|---|---|
| Nudge vira ruído e passa a ser ignorado | 90min, e só em roots vigiados. Se incomodar, aumentar o limiar antes de desligar. |
| Modelo escreve entrada de baixo valor | `SKILL.md` define critério explícito de o que registrar. |
| Script e edição manual em conflito | Script só faz append em seção existente; nunca reescreve o arquivo. |
| launchd falha silenciosamente | Script loga em `~/.local/state/journal/log`; `journal status` revela nota do dia faltando. |
| Item rolado se acumula por semanas | Marcador `↳ aberto desde` deixa a idade visível — é sinal, não defeito. |

## Pendência de segurança (não bloqueia)

Uma das notas antigas contém uma chave de API em texto puro. O vault não é
repositório git e `~/Documents` não sincroniza com iCloud, então a exposição é
local à máquina. Rotacionar a chave e mover segredos para o 1Password é higiene
recomendada, sem urgência.

Separadamente: `~/.claude/settings.json` renderizado contém
`CLAUDE_CODE_OAUTH_TOKEN` literal, com cópias em quatro arquivos `.bak-*`. O
template do chezmoi está correto (injeta via `env`), e `git log -S` confirma que
o token nunca entrou no repositório. Limpar os `.bak-*` é higiene.
