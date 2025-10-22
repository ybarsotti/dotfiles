# AI-Assisted TDD Workflow Visualization

A comprehensive visual guide to the Test-Driven Development workflow powered by Claude Code commands.

## Overview

This workflow represents a complete software development cycle from problem discovery through design, implementation, review, and shipping. Each phase is supported by dedicated Claude Code commands that ensure quality, performance, and best practices at every step.

**Key Principles**:
- **Design First**: Understand the problem before coding
- **TDD Always**: Red-Green-Refactor cycle for all implementations
- **Review Early**: Catch issues before they become problems
- **Ship Confidently**: Comprehensive checks before deployment

---

## Complete Workflow

The following D2 diagram shows the entire workflow from Discovery to Ship.

**Diagram Source**: The diagram is stored in `ai-workflow.d2` in the same directory.

### Visual Workflow Diagram

The workflow consists of 4 main phases:

1. **Design Phase** (Blue) - Problem analysis and solution design
   - User describes problem
   - `/design-solution` creates comprehensive design
   - `/review-solution-design` validates the design

2. **Develop Phase** (Purple) - TDD implementation
   - `/develop-solution` guides through Red-Green-Refactor cycle
   - Tests written first, then implementation, then refactoring

3. **Review Phase** (Light Blue) - Multi-layered code review
   - Automated review with `/review-solution-code`
   - Manual self-review
   - Split strategy for complex changes
   - Peer review with `/review-pr`

4. **Ship Phase** (Green) - Final validation and deployment
   - `/ship-it` runs all checks and creates PR

**To view the diagram visually**, use one of these methods:

```bash
# Render to SVG
d2 ~/.claude/commands/ai-workflow.d2 workflow.svg

# Render to PNG
d2 ~/.claude/commands/ai-workflow.d2 workflow.png

# Watch mode (auto-refresh on changes)
d2 --watch ~/.claude/commands/ai-workflow.d2 workflow.svg
```

Or view the D2 source directly: `~/.claude/commands/ai-workflow.d2`

---

## Command Reference

Map workflow phases to Claude Code commands:

| Phase | Step | Command | Input | Output | Purpose |
|-------|------|---------|-------|--------|---------|
| **Design** | Solution Design | `/design-solution` | Problem description | `tmp/DESIGN.md` | Analyze problem, design solution with performance considerations |
| **Design** | Design Review | `/review-solution-design` | `tmp/DESIGN.md` | Updated `tmp/DESIGN.md` | Review design for edge cases, security, N+1 queries |
| **Develop** | TDD Implementation | `/develop-solution` | `tmp/DESIGN.md` | Code + Tests + `tmp/IMPLEMENTATION.md` | Implement using TDD with performance tests |
| **Review** | Code Review | `/review-solution-code` | Implemented code | `tmp/REVIEW.md` | Review for security, performance, best practices |
| **Review** | PR Review | `/review-pr [number]` | PR or branch | `tmp/PR_REVIEW.md` | Comprehensive PR review with performance checks |
| **Ship** | Quality Checks + PR | `/ship-it` | All artifacts | Pull Request | Run all checks and create meaningful PR |

---

## Phase Details

### 1. Design Phase 📋

**Objective**: Understand the problem and create a robust design

**Process**:
1. User describes the problem
2. `/design-solution` explores codebase and designs solution
   - Identifies existing code to leverage
   - Plans for N+1 query prevention
   - Defines caching strategy
   - Considers bulk operations
3. Creates `tmp/DESIGN.md` with comprehensive design
4. `/review-solution-design` reviews the design
   - Checks for edge cases
   - Validates performance strategy
   - Ensures security considerations

**Key Outputs**:
- `tmp/DESIGN.md` - Complete solution design
- Design review section with checklist

---

### 2. Develop Phase 💻

**Objective**: Implement the solution using Test-Driven Development

**TDD Cycle**:
1. **🔴 RED**: Write failing tests first
   - Unit tests for all scenarios
   - Performance tests (query counts, response times)
   - Edge case tests
   - Security tests

2. **🟢 GREEN**: Write minimum code to pass tests
   - Implement according to design
   - Use existing code identified in design
   - Follow performance best practices

3. **🔵 REFACTOR**: Clean up and optimize
   - Remove duplication
   - Improve readability
   - Optimize performance (if needed)
   - Ensure all tests still pass

**Key Outputs**:
- Production code
- Comprehensive test suite
- `tmp/IMPLEMENTATION.md` - Implementation notes

---

### 3. Review Phase 🔍

**Objective**: Ensure code quality, security, and performance

**Review Types**:

#### Automated Review (`/review-solution-code`)
- Security vulnerability scan
- N+1 query detection
- Performance analysis
- Best practices validation
- Library usage optimization
- Code complexity analysis

#### Manual Self Review
- Read through your own code
- Check against design document
- Verify edge cases are handled
- Ensure tests are comprehensive

#### Split Strategy (for complex changes)
- Break large changes into smaller branches
- Each branch is independently reviewable
- Reduces review burden
- Easier to merge and rollback

#### Peer Review (`/review-pr`)
- Colleague reviews your PR
- Provides feedback and suggestions
- Catches issues you might have missed
- Knowledge sharing

**Key Outputs**:
- `tmp/REVIEW.md` - Comprehensive code review
- `tmp/PR_REVIEW.md` - PR review findings
- Fixed issues
- Improved code quality

---

### 4. Ship Phase 🚀

**Objective**: Confidently deploy to production

**Pre-Flight Checklist**:
- ✅ **Format**: Code formatted consistently
- ✅ **Lint**: No linting errors
- ✅ **Test**: All tests passing
- ✅ **Security**: No secrets, vulnerabilities scanned
- ✅ **Performance**: Query counts verified, benchmarks met

**Pull Request**:
- Meaningful description (not just file counts!)
- Problem statement and solution approach
- Key decisions and trade-offs
- Testing coverage
- Performance impact
- Security considerations

**🎉 This is a BIG DEAL!** Your code has been thoroughly designed, tested, and reviewed. It's ready for production!

---

## Usage Instructions

### Viewing the D2 Diagram

The D2 diagram source is in a separate file: `~/.claude/commands/ai-workflow.d2`

**Option 1: Using D2 CLI**

```bash
# Install D2 (if not already installed)
brew install d2  # macOS
# or
curl -fsSL https://d2lang.com/install.sh | sh -s --

# Render to SVG
d2 --theme=200 ~/.claude/commands/ai-workflow.d2 workflow.svg

# Render to PNG
d2 --theme=200 ~/.claude/commands/ai-workflow.d2 workflow.png

# View in browser with auto-refresh
d2 --watch ~/.claude/commands/ai-workflow.d2 workflow.svg
```

**Option 2: VS Code Extension**

- Install "D2 Language Support" extension
- Open `~/.claude/commands/ai-workflow.d2` in VS Code
- D2 syntax will be highlighted
- Use extension commands to preview

**Option 3: Online**

- Open `~/.claude/commands/ai-workflow.d2`
- Copy the D2 code to <https://play.d2lang.com/>
- Customize and export

### Running the Workflow

**Complete workflow example**:
```bash
# 1. Design
/design-solution
# Review the design
/review-solution-design

# 2. Develop (TDD)
/develop-solution
# This will guide you through Red-Green-Refactor cycles

# 3. Review
/review-solution-code
# Fix any issues found
/review-pr  # (after creating PR or pushing branch)

# 4. Ship
/ship-it
# Creates PR with comprehensive description
```

**Iterative workflow** (for complex features):
```bash
# Design
/design-solution

# Review identifies this should be split into 3 parts
/review-solution-design

# Develop Part 1
/develop-solution  # Implement first sub-problem only
/review-solution-code
/ship-it  # PR for part 1

# Develop Part 2 (after Part 1 merged)
/develop-solution  # Implement second sub-problem
/review-solution-code
/ship-it  # PR for part 2

# Develop Part 3
/develop-solution  # Implement third sub-problem
/review-solution-code
/ship-it  # PR for part 3
```

---

## Workflow Tips & Best Practices

### Design Phase Tips
- **Be thorough**: Don't rush the design phase
- **Search first**: Always look for existing code to leverage
- **Think performance**: Plan for N+1 prevention and caching upfront
- **Consider scale**: How will this work with 1M records?
- **Plan for failure**: What could go wrong?

### Development Phase Tips
- **Tests first, always**: Never write production code without a failing test
- **One test at a time**: Don't try to test everything at once
- **Keep tests simple**: Each test should verify one behavior
- **Test performance**: Include query count and response time tests
- **Commit often**: Small, focused commits in TDD cycle

### Review Phase Tips
- **Review your own code first**: Catch obvious issues before others see them
- **Use automated reviews**: `/review-solution-code` catches many issues
- **Break down large changes**: Use Split strategy for complex features
- **Respond promptly**: Address peer review feedback quickly
- **Learn from feedback**: Each review is a learning opportunity

### Ship Phase Tips
- **Run all checks**: Don't skip formatters, linters, or tests
- **Write meaningful PRs**: Help reviewers understand your changes
- **Include context**: Link to design docs and review findings
- **Test locally first**: Don't rely on CI to catch obvious issues
- **Celebrate**: Shipping is a big deal! 🎉

### General Tips
- **Iterate**: Don't try to do everything in one PR
- **Communicate**: Keep stakeholders informed of progress
- **Document decisions**: Use DESIGN.md and IMPLEMENTATION.md
- **Learn and improve**: Each cycle makes you better
- **Trust the process**: The workflow exists for good reasons

---

## Performance Optimization Focus

Throughout the entire workflow, there's a strong focus on performance:

### Design Phase
- Identify N+1 query risks
- Plan caching strategy
- Design for bulk operations
- Consider algorithmic complexity

### Development Phase
- Write performance tests (query counts, response times)
- Implement N+1 prevention
- Use bulk operations
- Add caching where appropriate

### Review Phase
- Check for N+1 queries
- Verify bulk operations are used
- Validate caching implementation
- Analyze algorithmic complexity

### Ship Phase
- Run performance benchmarks
- Verify query counts in tests
- Check response times meet targets

**Key Principle**: Performance is not an afterthought—it's built into every phase of the workflow.

---

## Troubleshooting

### Design Phase Issues
**Problem**: Design is too vague
- **Solution**: Use `/design-solution` to explore codebase more thoroughly
- Ask more specific questions about requirements

**Problem**: Design review finds major issues
- **Solution**: Iterate on design before moving to development
- Better to catch issues early than during implementation

### Development Phase Issues
**Problem**: Tests are failing
- **Solution**: That's expected in RED phase!
- Make sure tests are correct before implementing

**Problem**: Can't get tests to pass
- **Solution**: Review design document
- Simplify approach
- Ask for help if stuck

### Review Phase Issues
**Problem**: Too many issues found
- **Solution**: Fix issues iteratively
- Consider if design needs revisiting
- Learn patterns to avoid in future

**Problem**: Peer review taking too long
- **Solution**: Break PR into smaller pieces
- Provide better PR description
- Schedule dedicated review time

### Ship Phase Issues
**Problem**: CI/CD failing
- **Solution**: Run all checks locally first using `/ship-it`
- Fix issues before pushing

**Problem**: PR description unclear
- **Solution**: Use `/ship-it` which creates meaningful descriptions
- Include context from design and review docs

---

## Integration with Other Tools

### Git Workflow
```bash
# Create feature branch
git checkout -b feature/new-feature

# Design and develop
/design-solution
/develop-solution

# Commit regularly
git add .
git commit -m "feat: implement feature part 1"

# Review
/review-solution-code

# Ship
/ship-it  # Creates PR with gh CLI
```

### CI/CD Integration
The workflow complements CI/CD:
- Local checks with `/ship-it` before pushing
- CI runs same checks in cloud
- Faster feedback loop
- Catches issues before CI

### Project Management
- Link PRs to issues/tickets
- Update project board when shipping
- Document decisions in DESIGN.md
- Track technical debt in REVIEW.md

---

## Workflow Variations

### Quick Fix Workflow (for simple bugs)
```bash
# 1. Design (simplified)
# Quick analysis, maybe skip /design-solution

# 2. Develop with tests
/develop-solution  # Still use TDD!

# 3. Review
/review-solution-code

# 4. Ship
/ship-it
```

### Research/Spike Workflow (for exploration)
```bash
# 1. Explore
# Manually explore codebase and technologies

# 2. Document findings
# Create temporary docs/spike.md

# 3. Present findings
# Share with team

# 4. If approved, start full workflow
/design-solution  # Now you know more
```

### Refactoring Workflow
```bash
# 1. Design refactoring
/design-solution  # Describe what needs refactoring

# 2. Write tests for existing behavior first!
/develop-solution  # Tests should pass before refactoring

# 3. Refactor with tests passing
# Keep tests green while refactoring

# 4. Review and ship
/review-solution-code
/ship-it
```

---

## Learning Resources

- **D2 Documentation**: https://d2lang.com/
- **TDD Principles**: https://martinfowler.com/bliki/TestDrivenDevelopment.html
- **Code Review Best Practices**: https://google.github.io/eng-practices/review/
- **Performance Optimization**: See individual command documentation

---

## Conclusion

This workflow represents a **best-practice approach to software development** that:
- ✅ Ensures quality through design and review
- ✅ Prevents bugs through TDD
- ✅ Optimizes performance from the start
- ✅ Makes shipping confident and reliable
- ✅ Creates maintainable, well-documented code

**Remember**: The workflow is a guide, not a prison. Adapt it to your needs, but always maintain the core principles of design, test, review, and quality.

**Happy coding!** 🚀
