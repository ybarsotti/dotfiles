# Refactor Command

Analyze code and suggest or apply refactoring improvements.

## Instructions

1. Analyze the specified code or entire codebase for refactoring opportunities:
   - Identify code smells and anti-patterns
   - Find duplicated code
   - Detect overly complex functions (high cyclomatic complexity)
   - Look for long parameter lists
   - Find large classes/functions that should be split
   - Identify tight coupling and suggest decoupling strategies
   - Find magic numbers and strings that should be constants

2. Common refactoring patterns to consider:

   **Extract Method/Function:**
   - Break down large functions into smaller, focused ones
   - Extract repeated code into reusable functions

   **Rename:**
   - Improve variable, function, and class names for clarity
   - Ensure naming follows project conventions

   **Extract Class/Module:**
   - Split large classes with multiple responsibilities
   - Create new modules for related functionality

   **Simplify Conditional Logic:**
   - Replace complex conditionals with guard clauses
   - Use early returns to reduce nesting
   - Extract complex conditions into named functions

   **Remove Duplication:**
   - Consolidate similar code paths
   - Create shared utilities for common operations

   **Improve Data Structures:**
   - Replace primitive obsession with proper types
   - Use appropriate collections and data structures

   **Dependency Injection:**
   - Reduce tight coupling by injecting dependencies
   - Make code more testable

3. For each refactoring suggestion:
   - Explain why the refactoring is beneficial
   - Show before and after code
   - Highlight improvements in readability, maintainability, or performance
   - Note any potential risks or side effects
   - Suggest tests to verify the refactoring doesn't break functionality

4. Prioritize refactorings:
   - **High Priority:** Critical issues affecting maintainability or correctness
   - **Medium Priority:** Code smells that should be addressed soon
   - **Low Priority:** Nice-to-have improvements

5. Apply refactorings safely:
   - Ensure tests pass before and after
   - Make small, incremental changes
   - Commit refactorings separately from feature changes
   - Use IDE refactoring tools when available

6. Code quality metrics to check:
   - Cyclomatic complexity
   - Code duplication percentage
   - Function/method length
   - Class size
   - Dependency depth

## Output Format

```
🔧 Refactoring Analysis

High Priority Issues:
1. [Issue description] - [File:Line]
   Suggestion: [Refactoring approach]
   Impact: [Expected improvement]

Medium Priority Issues:
[Similar format]

Low Priority Issues:
[Similar format]

Metrics:
- Functions over 50 lines: X
- Duplicated code blocks: Y
- Average cyclomatic complexity: Z

Would you like me to apply any of these refactorings?
```
