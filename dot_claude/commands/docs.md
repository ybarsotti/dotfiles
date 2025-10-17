# Documentation Command

Generate or update project documentation.

## Instructions

1. Analyze the project structure to determine documentation needs:
   - Identify the project type and primary language
   - Check for existing documentation (README.md, docs/, wiki/)
   - Review code comments and docstrings
   - Identify public APIs, modules, and functions

2. Generate documentation based on project type:

   **For README.md:**
   - Project title and description
   - Installation instructions
   - Usage examples
   - Configuration options
   - Contributing guidelines
   - License information

   **For API Documentation:**
   - Python: Use docstrings, generate with Sphinx or MkDocs
   - JavaScript/TypeScript: JSDoc comments, generate with TypeDoc or JSDoc
   - Go: godoc comments
   - Rust: rustdoc comments
   - Java: Javadoc comments

   **For User Guides:**
   - Getting started tutorial
   - Common use cases with examples
   - Troubleshooting section
   - FAQ

3. Ensure documentation includes:
   - Code examples that are tested and working
   - Clear explanations of complex concepts
   - Links to relevant resources
   - Version information
   - Changelog or release notes

4. Update existing documentation:
   - Fix outdated information
   - Add missing sections
   - Improve clarity and readability
   - Add or update code examples
   - Update API references for changed interfaces

5. Generate documentation artifacts:
   - Run documentation generators (Sphinx, TypeDoc, godoc, rustdoc, etc.)
   - Verify generated docs render correctly
   - Check for broken links
   - Validate code examples

6. Documentation best practices:
   - Write in clear, concise language
   - Use consistent formatting
   - Include visual aids (diagrams, screenshots) where helpful
   - Keep documentation close to the code it describes
   - Version documentation alongside code

## Output

Summarize what documentation was created or updated:

```
📚 Documentation Updated

Created:
- [List of new documentation files]

Updated:
- [List of modified documentation files]

Generated:
- [Documentation artifacts generated]

Next Steps:
- [Suggestions for additional documentation needs]
```
