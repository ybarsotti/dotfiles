---
globs: ["**/*.sh", "**/*.bash", "**/Makefile"]
---

# Shell Scripts

## Shellcheck Compliance

### Enable Strict Mode
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

| Flag | Effect |
|------|--------|
| `-e` | Exit on error |
| `-u` | Error on undefined vars |
| `-o pipefail` | Pipe fails if any cmd fails |

### Common Shellcheck Fixes

```bash
# SC2086: Quote to prevent globbing
# BAD
rm $file
# GOOD
rm "$file"

# SC2046: Quote command substitution
# BAD
files=$(ls *.txt)
# GOOD
files="$(ls ./*.txt)"

# SC2155: Declare and assign separately
# BAD
local foo=$(command)
# GOOD
local foo
foo=$(command)

# SC2164: Use || exit after cd
cd /some/path || exit 1
```

## POSIX Portability

### Avoid Bashisms
```bash
# Use $() not backticks
result=$(command)

# Use = not == in [ ]
if [ "$var" = "value" ]; then

# Use -a/-o not &&/|| in [ ]
if [ -f "$file" ] && [ -r "$file" ]; then

# Portable alternatives
command -v git    # not 'which'
printf '%s\n'     # not 'echo -e'
```

### Arrays (Bash-only)
```bash
# If you need arrays, require bash explicitly
#!/usr/bin/env bash

declare -a files=("one.txt" "two.txt")
for file in "${files[@]}"; do
    echo "$file"
done
```

## Best Practices

### Error Handling
```bash
cleanup() {
    rm -f "$tmpfile"
}
trap cleanup EXIT

die() {
    echo "ERROR: $1" >&2
    exit 1
}

command || die "command failed"
```

### Argument Parsing
```bash
usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <arg>
Options:
    -h, --help     Show help
    -v, --verbose  Verbose output
EOF
}

verbose=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        -v|--verbose) verbose=true; shift ;;
        --) shift; break ;;
        -*) die "Unknown option: $1" ;;
        *) break ;;
    esac
done
```

### Safe Temporary Files
```bash
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
```

### Checking Commands
```bash
# Check if command exists
if ! command -v git &>/dev/null; then
    die "git is required"
fi

# Check if file exists
[[ -f "$config" ]] || die "Config not found: $config"
```

## Formatting (shfmt)

```bash
# Format with 4-space indent
shfmt -i 4 -w script.sh

# Common options
shfmt -i 2 -ci -bn script.sh
#      │   │   └─ binary ops start of line
#      │   └───── case indent
#      └───────── 2 space indent
```

## Testing Scripts

```bash
# Use bats for testing
@test "script runs successfully" {
    run ./script.sh
    [ "$status" -eq 0 ]
}

@test "validates input" {
    run ./script.sh ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "required" ]]
}
```
