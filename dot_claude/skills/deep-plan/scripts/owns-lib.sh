#!/usr/bin/env bash
# owns-lib.sh — shared ownership-matching primitives for validate-plan.sh and
# subplan-fanout.sh. Source only; never invoke directly (no `executable_`
# prefix, so chezmoi deploys it under the same name in both the source tree
# and the applied tree — no deployed/source fallback needed to find it).
#
# This used to be two textually-identical copies, one per script. A reviewer
# reverted the quoting fix in both copies and the test suite stayed green in
# both cases (100 passed, 0 failed) — nothing pinned the behavior. Rather than
# keep two copies that can silently drift apart again, this is now the single
# copy both scripts source.

# owns_match PATH PATTERN — exact-path or `/**`-prefix ownership match.
# The `**` in both case arms is quoted so it matches the literal two
# characters, not a glob wildcard — unquoted, `*/**` matches ANY string
# containing a `/` (since `**` degrades to `*` under glob rules), which
# silently misclassifies every ordinary exact path with a directory
# separator (i.e. almost all real repo paths) as a `/**`-prefix pattern.
owns_match() {
  local path="$1" pattern="$2" prefix
  case "$pattern" in
    */'**')
      prefix=${pattern%/'**'}
      case "$path" in "$prefix" | "$prefix"/*) return 0 ;; esac
      ;;
    *) [ "$path" = "$pattern" ] && return 0 ;;
  esac
  return 1
}

# valid_owns_pattern PATTERN — repo-relative exact path, or a directory
# prefix ending in the literal `/**`; no other wildcard, no absolute path,
# no `..` traversal.
valid_owns_pattern() {
  local p="$1"
  case "$p" in
    /*) return 1 ;;
    *..*) return 1 ;;
    *'*'*)
      case "$p" in
        */'**') return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 0 ;;
  esac
}

# owns_overlap A B — true when two ownership patterns are equal, or one is
# a `/**`-prefix covering the other (nested prefix, and an exact path under
# the other's prefix, both count as overlap).
owns_overlap() {
  local a="$1" b="$2" pa pb
  [ "$a" = "$b" ] && return 0
  case "$a" in */'**') pa=${a%/'**'} ;; *) pa="$a" ;; esac
  case "$b" in */'**') pb=${b%/'**'} ;; *) pb="$b" ;; esac
  owns_match "$pa" "$b" && return 0
  owns_match "$pb" "$a" && return 0
  return 1
}
