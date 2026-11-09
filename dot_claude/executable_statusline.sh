#!/usr/bin/env bash
# Claude Code status line, two rows:
#   🤖 model | Effort level | 📂 dir | 🌳 branch ✓/✗ | ⌛ duration
#   🚀 Context used/size (pct) | 🌙 Weekly bar ~ pct T-reset
# Claude Code pipes the session JSON on stdin. One jq call reads every field.
set -u

IFS=$'\x1f' read -r MODEL EFFORT DIR DURATION_MS USED SIZE PCT WEEK_PCT WEEK_RESET < <(
  jq -r '[
    .model.display_name // "",
    .effort.level // "",
    .workspace.current_dir // .cwd // "",
    (.cost.total_duration_ms // 0 | floor),
    (.context_window.total_input_tokens // 0 | floor),
    (.context_window.context_window_size // 0 | floor),
    (.context_window.used_percentage // 0 | floor),
    (.rate_limits.seven_day.used_percentage // "" | if . == "" then "" else floor end),
    (.rate_limits.seven_day.resets_at // "" | if . == "" then "" else floor end)
  ] | map(tostring) | join("\u001f")'
)

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
SEP=' | '

compact() { # 94400 -> 94.4k, 1200000 -> 1.2M
  awk -v n="$1" 'BEGIN {
    if (n < 1000) printf "%d", n
    else if (n < 1000000) printf "%.1fk", n / 1000
    else printf "%.1fM", n / 1000000
  }' | sed 's/\.0\([kM]\)/\1/'
}

human_duration() { # ms -> 42s, 8m 47s, 1h 5m
  local t=$(($1 / 1000)) m h
  if ((t < 60)); then printf '%ds' "$t"; return; fi
  m=$((t / 60))
  if ((m < 60)); then printf '%dm %ds' "$m" $((t % 60)); return; fi
  h=$((m / 60))
  printf '%dh %dm' "$h" $((m % 60))
}

bar() { # pct -> ▰▰▱▱▱▱▱▱▱▱
  local filled=$((($1 * 10 + 50) / 100)) i out=''
  ((filled > 10)) && filled=10
  for ((i = 0; i < 10; i++)); do
    if ((i < filled)); then out+='▰'; else out+='▱'; fi
  done
  printf '%s' "$out"
}

until_reset() { # epoch -> T-3d04h, T-5h12m, T-9m
  local d=$(($1 - $(date +%s)))
  ((d <= 0)) && return
  if ((d >= 86400)); then printf 'T-%dd%02dh' $((d / 86400)) $((d % 86400 / 3600))
  elif ((d >= 3600)); then printf 'T-%dh%02dm' $((d / 3600)) $((d % 3600 / 60))
  else printf 'T-%dm' $((d / 60)); fi
}

# Row 1
c '1;38;2;30;213;107' "🤖 ${MODEL}"
printf '%s' "$SEP"
c '1;38;2;205;214;244' "Effort ${EFFORT:-–}"
printf '%s' "$SEP"
c '1;38;2;137;180;250' "📂~${DIR##*/}"
if BRANCH=$(git -C "${DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null); then
  printf '%s' "$SEP"
  c '3;38;2;166;227;161' "🌳${BRANCH} "
  if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null | head -1)" ]; then
    printf '✗'
  else
    c '38;2;94;255;0' '✓'
  fi
fi
printf '%s' "$SEP"
c '38;2;220;91;91' "⌛ $(human_duration "$DURATION_MS")"
printf '\n'

# Row 2: the context colour moves from green to red as the window fills.
if ((USED > 150000)); then CTX=167; elif ((USED > 80000)); then CTX=214
elif ((USED > 50000)); then CTX=226; else CTX=114; fi
c '1;38;2;205;214;244' '🚀 Context '
c "1;38;5;${CTX}" "$(compact "$USED")/$(compact "$SIZE") (${PCT}%)"
if [ -n "$WEEK_PCT" ]; then
  printf '%s' "$SEP"
  c '38;2;47;223;66' '🌙 Weekly '
  c '96' "$(bar "$WEEK_PCT") ~ ${WEEK_PCT}%"
  [ -n "$WEEK_RESET" ] && c '96' " $(until_reset "$WEEK_RESET")"
fi
exit 0
