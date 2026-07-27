#!/usr/bin/env bash
# Testes do script `journal`. Roda contra um vault temporário — nunca toca o
# vault real. Uso: ./test-journal.sh [caminho-do-script-journal]
set -uo pipefail

# shellcheck source=/dev/null
. "${HOME}/.claude/skills/_shared/assert.sh"

J="${1:-${HOME}/.local/bin/journal}"
[ -x "$J" ] || { echo "journal não encontrado ou não executável: $J" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# assert_exit usa "$*" como label, então não aceita rótulo próprio.
# Estes wrappers dão um rótulo legível sem virar argumento do comando.
assert_file() {
  if [ -f "$1" ]; then
    ASSERT_PASS=$((ASSERT_PASS + 1)); echo "ok: $2"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1)); echo "FAIL: $2 (arquivo ausente: $1)"
  fi
}

# assert_fails LABEL CMD... — espera saída diferente de zero.
assert_fails() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    ASSERT_FAIL=$((ASSERT_FAIL + 1)); echo "FAIL: ${label} (comando teve sucesso)"
  else
    ASSERT_PASS=$((ASSERT_PASS + 1)); echo "ok: ${label}"
  fi
}

# assert_absent HAYSTACK NEEDLE LABEL
assert_absent() {
  case "$1" in
    *"$2"*) ASSERT_FAIL=$((ASSERT_FAIL + 1)); echo "FAIL: $3 (encontrou '$2')" ;;
    *)      ASSERT_PASS=$((ASSERT_PASS + 1)); echo "ok: $3" ;;
  esac
}
mkdir -p "$TMP/vault" "$TMP/state" "$TMP/work/repo" "$TMP/learn/curso" "$TMP/outro"

cat > "$TMP/config.sh" <<EOF
JOURNAL_VAULT="$TMP/vault"
JOURNAL_DIR="Journal"
JOURNAL_NUDGE_MINUTES="90"
JOURNAL_STREAMS="
$TMP/work:work
$TMP/learn:study"
JOURNAL_ALIASES="
meurepo:Apelido"
EOF

export JOURNAL_CONFIG="$TMP/config.sh" JOURNAL_STATE_DIR="$TMP/state"
D="$TMP/vault/Journal/2026/07"

# ---------------------------------------------------------------- criação

JOURNAL_DATE=2026-07-27 "$J" today >/dev/null
assert_file "$D/2026-07-27.md" "cria a nota do dia"

body=$(cat "$D/2026-07-27.md")
assert_contains "$body" "weekday: seg" "frontmatter traz o dia da semana"
assert_contains "$body" "[[2026-W31]]" "linka a semana ISO"
assert_contains "$body" "[[2026-07-28]]" "linka o próximo dia útil"
for s in Plano Decisões Threads Tickets Estudos Notas; do
  assert_contains "$body" "## $s" "seção $s presente"
done

# Sexta liga para segunda, não para sábado.
JOURNAL_DATE=2026-07-31 "$J" today >/dev/null
assert_contains "$(cat "$D/2026-07-31.md")" "[[2026-08-03]]" "sexta aponta para segunda"

# ---------------------------------------------------------------- append

JOURNAL_DATE=2026-07-27 "$J" append --project alfa --section Plano --text "- [ ] aberto" >/dev/null
JOURNAL_DATE=2026-07-27 "$J" append --project alfa --section Plano --text "- [x] fechado" >/dev/null
JOURNAL_DATE=2026-07-27 "$J" append --project alfa --section Decisões --text "- decisão X" >/dev/null

plano=$(awk '/^## Plano$/{f=1;next} f&&/^## /{exit} f' "$D/2026-07-27.md")
assert_contains "$plano" "- [ ] aberto" "append vai para a seção pedida"
assert_contains "$plano" "- [x] fechado" "append preserva ordem na seção"

dec=$(awk '/^## Decisões$/{f=1;next} f&&/^## /{exit} f' "$D/2026-07-27.md")
assert_contains "$dec" "- decisão X" "append respeita seção com acento"
assert_absent "$dec" "aberto" "append não vaza entre seções"

# Uma entrada real tem resumo, motivo e links em linhas separadas.
JOURNAL_DATE=2026-07-27 "$J" append --project alfa --section Decisões --text "- **Escolha X** — resumo
  **Por quê:** o motivo.
  [[Entidade]] · [link](https://exemplo)" >/dev/null
multi=$(awk '/^## Decisões$/{f=1;next} f&&/^## /{exit} f' "$D/2026-07-27.md")
assert_contains "$multi" "- **Escolha X** — resumo" "append multilinha: primeira linha"
assert_contains "$multi" "  **Por quê:** o motivo." "append multilinha: preserva indentação"
assert_contains "$multi" "[[Entidade]] · [link](https://exemplo)" "append multilinha: última linha"

# Projetos distintos coexistem na mesma seção, cada um sob o seu `### `.
JOURNAL_DATE=2026-07-27 "$J" append --project beta --section Decisões --text "- decisão beta" >/dev/null
JOURNAL_DATE=2026-07-27 "$J" append --project alfa --section Decisões --text "- segunda de alfa" >/dev/null
dec2=$(awk '/^## Decisões$/{f=1;next} f&&/^## /{exit} f' "$D/2026-07-27.md")
assert_contains "$dec2" "### alfa" "cria subseção do projeto"
assert_contains "$dec2" "### beta" "segundo projeto ganha subseção própria"
nsub=$(printf '%s\n' "$dec2" | grep -c '^### alfa$')
assert_eq "$nsub" "1" "não duplica a subseção do projeto"

# A entrada nova entra sob alfa, não no fim da seção.
alfa=$(printf '%s\n' "$dec2" | awk '/^### alfa$/{f=1;next} f&&/^### /{exit} f')
assert_contains "$alfa" "- segunda de alfa" "append vai para a subseção do projeto"
assert_absent "$alfa" "decisão beta" "projeto não vaza para outro"

assert_fails "seção inválida falha" \
  env JOURNAL_DATE=2026-07-27 "$J" append --section Inexistente --text x
assert_fails "--section ausente falha" \
  env JOURNAL_DATE=2026-07-27 "$J" append --text "sem seção"

# ---------------------------------------------------------------- rollover

JOURNAL_DATE=2026-07-28 "$J" today >/dev/null
p28=$(awk '/^## Plano$/{f=1;next} f&&/^## /{exit} f' "$D/2026-07-28.md")
assert_contains "$p28" "↳ aberto desde [[2026-07-27]]" "rollover marca a origem"
assert_contains "$p28" "### alfa" "rollover devolve o item ao seu projeto"
assert_absent "$p28" "fechado" "rollover ignora item ticado"

# A idade não pode reiniciar a cada salto.
JOURNAL_DATE=2026-07-29 "$J" today >/dev/null
JOURNAL_DATE=2026-07-30 "$J" today >/dev/null
p30=$(awk '/^## Plano$/{f=1;next} f&&/^## /{exit} f' "$D/2026-07-30.md")
assert_contains "$p30" "↳ aberto desde [[2026-07-27]]" "idade sobrevive a 3 saltos"
n=$(printf '%s\n' "$p30" | grep -c "aberto desde")
assert_eq "$n" "1" "não duplica o marcador"

# Dia anterior permanece intacto — é o registro daquele dia.
assert_contains "$(cat "$D/2026-07-27.md")" "- [x] fechado" "dia anterior não é mutado"

# ---------------------------------------------------------------- idempotência

before=$(md5 -q "$D/2026-07-28.md" 2>/dev/null || md5sum "$D/2026-07-28.md" | cut -d' ' -f1)
JOURNAL_DATE=2026-07-28 "$J" today >/dev/null
after=$(md5 -q "$D/2026-07-28.md" 2>/dev/null || md5sum "$D/2026-07-28.md" | cut -d' ' -f1)
assert_eq "$after" "$before" "today é idempotente"

# ---------------------------------------------------------------- semana

"$J" ensure-week 2026-07-27 >/dev/null
W="$TMP/vault/Journal/weeks/2026-W31.md"
assert_file "$W" "cria a nota da semana"
wk=$(cat "$W")
assert_contains "$wk" "range: 2026-07-27 → 2026-08-02" "intervalo ISO correto"
assert_contains "$wk" "## Compromissos" "semana tem Compromissos"
assert_contains "$wk" "## Radar" "semana tem Radar"
assert_contains "$wk" "dataview" "semana tem a query"

assert_contains "$wk" 'AND !"Journal/weeks"' "query exclui as próprias notas semanais"

# Compromisso é referência, não checkbox: tudo desce para o Radar da próxima
# semana e a poda é manual, na segunda.
awk '{print}
     /^## Compromissos$/{print "### alfa"; print "- [[PROJ-1]] alguma promessa — ETA ter"}
     /^## Radar$/{print "### alfa"; print "- item de radar antigo"}
    ' "$W" > "$W.tmp" && mv "$W.tmp" "$W"
"$J" ensure-week 2026-08-03 >/dev/null
W2="$TMP/vault/Journal/weeks/2026-W32.md"
radar=$(awk '/^## Radar$/{f=1;next} f&&/^## /{exit} f' "$W2")
compr=$(awk '/^## Compromissos$/{f=1;next} f&&/^## /{exit} f' "$W2")
assert_contains "$radar" "PROJ-1" "compromisso aberto desce para Radar"
assert_contains "$radar" "### alfa" "Radar preserva o projeto do compromisso"
assert_contains "$radar" "item de radar antigo" "radar também desce para a semana seguinte"
assert_absent "$compr" "PROJ-1" "reassumir compromisso é deliberado"

# Um item que espera há semanas deve mostrar a semana de origem, não a última.
"$J" ensure-week 2026-08-10 >/dev/null
W3="$TMP/vault/Journal/weeks/2026-W33.md"
radar3=$(awk '/^## Radar$/{f=1;next} f&&/^## /{exit} f' "$W3")
assert_contains "$radar3" "↳ de [[2026-W31]]" "marcador guarda a semana de origem"
n=$(printf '%s\n' "$radar3" | grep -c "PROJ-1")
assert_eq "$n" "1" "item não se duplica a cada semana"

# ------------------------------------------------------- append na semana

"$J" append --week --date 2026-07-27 --project gama --section Compromissos \
  --text "- [[PROJ-2]] alguma coisa — ETA qua" >/dev/null
wcomp=$(awk '/^## Compromissos$/{f=1;next} f&&/^## /{exit} f' "$W")
assert_contains "$wcomp" "### gama" "append --week cria subseção na semana"
assert_contains "$wcomp" "- [[PROJ-2]] alguma coisa — ETA qua" "append --week escreve o item"
assert_absent "$(cat "$D/2026-07-27.md")" "PROJ-2" "append --week não toca a nota do dia"

assert_fails "seção do dia é inválida com --week" \
  "$J" append --week --date 2026-07-27 --section Plano --text x
assert_fails "seção da semana é inválida sem --week" \
  env JOURNAL_DATE=2026-07-27 "$J" append --section Compromissos --text x

# ---------------------------------------------------------------- entidades

f=$("$J" entity --type ticket --name PROJ-201)
assert_file "$f" "cria nota de ticket"
assert_contains "$f" "/entities/" "ticket vai para entities/"
assert_contains "$("$J" entity --type decision --name "Price Sync")" "/decisions/" "decisão vai para decisions/"
assert_contains "$("$J" entity --type study --name "Tool Use")" "/study/" "estudo vai para study/"
assert_contains "$("$J" entity --type project --name dotfiles)" "/projects/" "projeto vai para projects/"
assert_fails "tipo inválido falha" "$J" entity --type invalido --name x

printf 'conteúdo manual\n' >> "$f"
f2=$("$J" entity --type ticket --name PROJ-201)
assert_contains "$(cat "$f2")" "conteúdo manual" "entity não sobrescreve nota existente"

# ---------------------------------------------------------------- inbox

"$J" note "primeira anotação livre" >/dev/null
"$J" note "segunda, com acento e — travessão" >/dev/null
INBOX="$TMP/vault/Journal/inbox.md"
assert_file "$INBOX" "note cria o inbox"
inb=$(cat "$INBOX")
assert_contains "$inb" "primeira anotação livre" "note grava a primeira"
assert_contains "$inb" "segunda, com acento e — travessão" "note preserva acento e travessão"
n=$(grep -c '^# Inbox$' "$INBOX")
assert_eq "$n" "1" "cabeçalho do inbox não se repete"
assert_contains "$("$J" inbox)" "primeira anotação livre" "inbox mostra o conteúdo"
assert_fails "note sem texto falha" "$J" note

# O inbox não pertence a nenhum dia nem projeto.
assert_absent "$(cat "$D/2026-07-27.md")" "primeira anotação livre" "note não toca a nota do dia"

# ---------------------------------------------------------------- streams

assert_eq "$("$J" stream "$TMP/work/repo")" "work" "detecta stream work"
assert_eq "$("$J" stream "$TMP/learn/curso")" "study" "detecta stream study"
assert_eq "$("$J" stream "$TMP/outro")" "" "path fora dos roots não tem stream"

# ---------------------------------------------------------------- projeto

assert_eq "$("$J" project "$TMP/outro")" "outro" "projeto cai no nome do diretório"
mkdir -p "$TMP/work/meurepo" && (cd "$TMP/work/meurepo" && git init -q .)
assert_eq "$("$J" project "$TMP/work/meurepo")" "Apelido" "alias substitui o nome do repo"
mkdir -p "$TMP/work/meurepo/src/deep"
assert_eq "$("$J" project "$TMP/work/meurepo/src/deep")" "Apelido" "subdiretório resolve para a raiz"
(cd "$TMP/work/meurepo/src" && JOURNAL_DATE=2026-07-29 "$J" append --section Notas --text "- auto" >/dev/null)
assert_contains "$(cat "$D/2026-07-29.md")" "### Apelido" "append sem --project detecta sozinho"

# ---------------------------------------------------------------- status

rm -f "$TMP/state"/last-append-*
assert_eq "$(cd "$TMP/work/repo" && "$J" status | cut -d' ' -f1)" "999999" "sem registro devolve valor alto"
(cd "$TMP/work/repo" && JOURNAL_DATE=2026-07-27 "$J" append --section Notas --text "- oi" >/dev/null)
assert_eq "$(cd "$TMP/work/repo" && "$J" status | cut -d' ' -f1)" "0" "append zera o contador"
assert_eq "$(cd "$TMP/learn/curso" && "$J" status | cut -d' ' -f1)" "999999" "contador é por stream"

# ---------------------------------------------------------------- erros

assert_fails "comando desconhecido falha" "$J" comando-inexistente
assert_fails "vault ausente falha" \
  env JOURNAL_CONFIG=/dev/null JOURNAL_VAULT=/nao/existe "$J" today

assert_summary
