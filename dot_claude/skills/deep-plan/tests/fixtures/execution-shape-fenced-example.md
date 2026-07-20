# Fenced Execution Shape Example Fixture

This plan has no real `## Execution shape` section — only an illustrative
fenced example showing another plan author what the heading looks like. It
must not be mistaken for a real declaration (mode must stay null, not
"parallel"), and it must not trip the near-miss-heading guard either (the
heading inside the fence is an exact match, but it's inside a fence).

```
## Execution shape
- Mode: `parallel`
```

## Affected files

- `justfile` — test
