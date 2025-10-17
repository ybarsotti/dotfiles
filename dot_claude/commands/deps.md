# Dependencies Command

Analyze and update project dependencies.

## Instructions

1. Identify the package manager and dependency files:
   - **Node.js:** `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
   - **Python:** `requirements.txt`, `pyproject.toml`, `Pipfile`, `poetry.lock`
   - **Rust:** `Cargo.toml`, `Cargo.lock`
   - **Go:** `go.mod`, `go.sum`
   - **Ruby:** `Gemfile`, `Gemfile.lock`
   - **Java:** `pom.xml`, `build.gradle`

2. Analyze current dependencies:
   - List all direct dependencies with versions
   - Identify outdated dependencies
   - Check for security vulnerabilities
   - Find unused dependencies
   - Detect dependency conflicts

3. Check for updates using appropriate tools:
   - Node.js: `npm outdated`, `yarn outdated`, `npx npm-check-updates`
   - Python: `pip list --outdated`, `poetry show --outdated`
   - Rust: `cargo outdated`
   - Go: `go list -u -m all`

4. Security scan:
   - Node.js: `npm audit`, `yarn audit`
   - Python: `pip-audit`, `safety check`
   - Rust: `cargo audit`
   - Go: `govulncheck`

5. Suggest updates with risk assessment:
   - **Low risk:** Patch versions (bug fixes)
   - **Medium risk:** Minor versions (new features, backwards compatible)
   - **High risk:** Major versions (breaking changes)

6. For each outdated dependency, provide:
   - Current version
   - Latest version
   - Changelog link
   - Breaking changes (if major update)
   - Security fixes included
   - Recommendation (update now, later, or not at all)

7. Update dependencies safely:
   - Update patch versions automatically
   - Update minor versions after reviewing changes
   - Update major versions one at a time
   - Run tests after each update
   - Update lockfiles

8. Clean up:
   - Remove unused dependencies
   - Deduplicate similar packages
   - Check bundle size impact (for frontend projects)

## Output Format

```
📦 Dependency Analysis

Security Vulnerabilities: X critical, Y high, Z moderate

Outdated Dependencies:
┌─────────────────┬──────────┬──────────┬──────────────┐
│ Package         │ Current  │ Latest   │ Risk         │
├─────────────────┼──────────┼──────────┼──────────────┤
│ package-name    │ 1.2.3    │ 2.0.0    │ High (major) │
│ another-pkg     │ 3.4.1    │ 3.4.5    │ Low (patch)  │
└─────────────────┴──────────┴──────────┴──────────────┘

Unused Dependencies:
- package-that-isnt-used
- another-unused-package

Recommendations:
1. [Critical] Update security package-name (CVE-XXXX-XXXX)
2. [High] Upgrade dependency-with-breaking-changes (review changelog first)
3. [Low] Update patch versions for X packages

Would you like me to apply recommended updates?
```
