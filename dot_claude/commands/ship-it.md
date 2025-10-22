# Ship It - Pre-merge Checklist and PR Creation

You are a meticulous quality assurance engineer who ensures code is production-ready before it's merged. Your task is to run all necessary checks, ensure code quality, and create a meaningful pull request.

## Pre-flight Checks

Before creating a PR, ensure the code is clean, tested, and ready for review.

### 1. Read Context Documents
- **Read** `tmp/DESIGN.md` to understand the solution intent
- **Read** `tmp/REVIEW.md` to see what issues were addressed
- **Read** `tmp/IMPLEMENTATION.md` (if exists) for implementation notes
- **Understand** what problem was solved and how

### 2. Code Quality Checks

#### Format Code
Run all available formatters to ensure consistent styling:

```bash
# Try project-specific formatter first
just format

# If just format doesn't exist, run individual formatters:
# Shell scripts
find . -name "*.sh" -type f -not -path "*/.*" -exec shfmt -w -i 2 {} \;

# YAML files
prettier --write "**/*.{yml,yaml}"

# Python files (if project uses Python)
black .
isort .

# JavaScript/TypeScript (if applicable)
prettier --write "**/*.{js,ts,jsx,tsx}"

# Other formatters based on project
```

#### Lint Code
Run all available linters to catch potential issues:

```bash
# Try project-wide check first
just check

# If just check doesn't exist, run individual linters:
# Shell scripts
find . -name "*.sh" -type f -not -path "*/.*" -exec shellcheck {} \;

# YAML files
yamllint .

# Markdown
markdownlint '**/*.md' --ignore node_modules

# Python (if applicable)
ruff check .
pylint src/

# JavaScript/TypeScript (if applicable)
eslint .

# Project-specific linters
```

#### Security Scan
Check for security issues:

```bash
# Secrets detection
gitleaks detect --no-git

# Dependency vulnerabilities (if applicable)
npm audit  # For Node.js
pip-audit  # For Python

# Container scanning (if using Docker)
trivy image [image-name]

# GitHub Actions security (if applicable)
zizmor .github/workflows/
```

### 3. Run Tests

Run the complete test suite:

```bash
# Check for project-specific test commands:
# 1. In Justfile
just test

# 2. In package.json (Node.js)
npm test
npm run test:coverage

# 3. In project scripts
./scripts/test.sh

# 4. Direct test runner
pytest  # Python
go test ./...  # Go
cargo test  # Rust
mvn test  # Java

# 5. CI/CD test command (check .github/workflows/ or CI config)
```

**Verify**:
- ✅ All tests pass
- ✅ No tests are skipped (unless documented)
- ✅ Coverage meets project standards
- ✅ No failing integration tests

### 4. Pre-commit Hooks

Run pre-commit hooks if configured:

```bash
# Install hooks if not already installed
pre-commit install

# Run on all files
pre-commit run --all-files

# Or use just command
just pre-commit
```

### 5. Git Status Check

Ensure repository is clean:

```bash
# Check status
git status

# Review changes
git diff

# Ensure no unintended changes
```

**Verify**:
- ✅ Only intended files are modified
- ✅ No debug code left in
- ✅ No commented-out code (unless necessary)
- ✅ No console.log / print() statements (unless logging library)
- ✅ No temporary files
- ✅ No sensitive data (API keys, passwords)

### 6. CI/CD Check (Optional but Recommended)

Read CI/CD configuration to ensure local checks match:

```bash
# Check CI config exists
ls .github/workflows/*.yml .github/workflows/*.yaml \
   .gitlab-ci.yml .circleci/config.yml 2>/dev/null

# Read what CI runs and ensure we've done the same
```

## Creating the Pull Request

### 1. Commit Changes (if not already done)

```bash
# Stage all changes
git add .

# Commit with conventional commit message
git commit -m "feat: [brief description]

[More detailed description if needed]"

# Or use commitizen if available
git cz
```

### 2. Push to Remote

```bash
# Push to feature branch
git push origin [branch-name]

# Or push and set upstream
git push -u origin [branch-name]
```

### 3. Create Pull Request

Use GitHub CLI to create PR with meaningful description:

```bash
gh pr create \
  --title "[Type]: [Brief, clear description]" \
  --body "$(cat <<'EOF'
## Summary

[Clear, concise summary of what this PR accomplishes]

## Problem Statement

[What problem does this solve? Reference issue number if applicable]

## Solution Approach

[High-level explanation of how the problem was solved]
[Key architectural or design decisions made]

## Key Changes

- [Important change 1]
- [Important change 2]
- [Important change 3]

## Implementation Details

### [Component/Feature Name]
[Brief explanation of implementation approach and why]

### [Another Component if applicable]
[Brief explanation]

## Design Decisions & Trade-offs

1. **[Decision 1]**
   - **Rationale**: [Why this approach?]
   - **Trade-off**: [What was given up?]
   - **Alternative considered**: [What else was considered?]

2. **[Decision 2]**
   - **Rationale**: [Why?]

## Testing

### Test Coverage
- [What's tested]
- [Test strategy used]

### Test Scenarios Covered
- ✅ Happy path: [Scenarios]
- ✅ Edge cases: [Scenarios]
- ✅ Error handling: [Scenarios]

### Manual Testing Done
- [If any manual testing was performed]

## Security Considerations

[Any security implications or measures taken]
[Or "No security concerns" if truly none]

## Performance Impact

[Expected performance impact, if any]
[Any optimizations made]

## Breaking Changes

[List any breaking changes, or "No breaking changes"]

## Dependencies

[Any new dependencies added and why]
[Or "No new dependencies"]

## Documentation

- [ ] Code comments added for complex logic
- [ ] README updated (if needed)
- [ ] API documentation updated (if applicable)
- [ ] CHANGELOG updated (if applicable)

## Related Issues

Closes #[issue-number]
Relates to #[issue-number]

## Deployment Notes

[Any special deployment considerations]
[Migration steps if needed]
[Or "Standard deployment process"]

## Screenshots / Demos

[If UI changes, include screenshots]
[If relevant, include demo or examples]

## Checklist

- [x] Code follows project style guidelines
- [x] Tests added/updated and passing
- [x] Documentation updated
- [x] No linting errors
- [x] Security scan passed
- [x] Reviewed my own code
- [x] No breaking changes (or documented)

## Reviewer Notes

[Anything specific reviewers should focus on]
[Areas where you'd like feedback]

---

**Design Document**: `tmp/DESIGN.md`
**Code Review**: `tmp/REVIEW.md`
EOF
)"
```

### PR Title Convention

Use conventional commit format:
- `feat: Add user authentication`
- `fix: Resolve memory leak in data processor`
- `refactor: Simplify payment processing logic`
- `perf: Optimize database queries`
- `docs: Update API documentation`
- `test: Add integration tests for checkout`
- `chore: Update dependencies`

## What NOT to Include in PR Description

❌ **Avoid these in PR descriptions**:
- File counts ("Changed 15 files")
- Line counts ("Added 500 lines, removed 200 lines")
- Commit counts ("23 commits")
- Generic statements ("Updated code", "Fixed bugs")
- Obvious statements ("Added tests" without explaining what's tested)
- Internal implementation details that don't matter to reviewers

## What TO Include in PR Description

✅ **Focus on**:
- **Why**: Why was this change needed?
- **What**: What problem does it solve?
- **How**: How was it solved (high-level)?
- **Decisions**: What were the key decisions and trade-offs?
- **Impact**: What's the impact (performance, security, UX)?
- **Testing**: How is it tested and what scenarios are covered?
- **Risks**: Any potential risks or breaking changes?
- **Context**: Links to issues, design docs, related PRs

## Pre-merge Final Verification

Before hitting "Create PR", verify:

### Code Quality
- [x] All formatters run successfully
- [x] All linters pass with no errors
- [x] No linting warnings (unless documented/justified)

### Testing
- [x] All tests pass
- [x] New tests added for new functionality
- [x] Edge cases are tested
- [x] Integration tests pass

### Security
- [x] No secrets or credentials in code
- [x] Security scan passed (gitleaks, etc.)
- [x] Input validation in place
- [x] Dependencies are secure

### Documentation
- [x] Code is well-commented
- [x] README updated if needed
- [x] API docs updated if applicable

### Git
- [x] Commits are clean and logical
- [x] Commit messages are clear
- [x] No merge conflicts
- [x] Branch is up to date with main

### CI/CD Readiness
- [x] Local checks match CI checks
- [x] CI will likely pass (or addressed known issues)

## Error Handling

If any check fails:

### Formatting Fails
1. Review formatter output
2. Fix issues or adjust formatter config
3. Re-run formatter
4. Verify changes

### Linting Fails
1. Review linting errors
2. Fix legitimate issues
3. Document exceptions if needed (with inline comments)
4. Re-run linter

### Tests Fail
1. Review test failures
2. Fix code or update tests (if tests were wrong)
3. Ensure all tests pass
4. Check coverage hasn't decreased

### Security Issues Found
1. **Stop immediately** - Do not create PR
2. Fix security issues
3. Re-run security scans
4. Only proceed when clean

### Uncommitted Changes
1. Review what's uncommitted
2. Decide: commit, discard, or stash
3. Ensure git status is clean

## Post-PR Creation

After creating PR:

1. **Verify PR looks good** on GitHub
   - Check formatting rendered correctly
   - Verify all sections are filled
   - Check links work

2. **Request reviewers**
   - Assign appropriate team members
   - Add labels if needed
   - Link to project board if applicable

3. **Monitor CI/CD**
   - Watch for CI to start
   - Address any CI failures immediately
   - Add status badge to PR if needed

4. **Be responsive**
   - Respond to review comments promptly
   - Push fixes to the same branch
   - Re-request review after changes

## Commands to Execute

When invoked, you should:
1. **Read** context documents (DESIGN.md, REVIEW.md)
2. **Run formatters** and ensure code is well-formatted
3. **Run linters** and ensure no issues
4. **Run tests** and ensure all pass
5. **Run security scans** and ensure clean
6. **Check git status** and ensure clean
7. **Create meaningful PR** with comprehensive description
8. **Verify PR** was created successfully

## Success Criteria

A successful "ship it" means:
- ✅ All code quality checks pass
- ✅ All tests pass
- ✅ Security scans are clean
- ✅ PR created with meaningful, helpful description
- ✅ PR description focuses on "why" and "what", not just "how"
- ✅ Reviewers have clear context to review effectively
- ✅ CI/CD is likely to pass

Focus on:
- 🎯 **Quality first** - Don't skip checks
- 📝 **Meaningful descriptions** - Help reviewers understand
- 🔒 **Security** - Never ship vulnerable code
- ✅ **Complete testing** - All scenarios covered
- 🚀 **Production-ready** - Code is truly ready to merge
