# Test Command

Run the project's test suite and report results.

## Instructions

1. Identify the project type and test framework by examining:
   - `package.json` (Node.js projects): check for jest, vitest, mocha, etc.
   - `pyproject.toml`, `setup.py`, `pytest.ini` (Python projects): check for pytest, unittest
   - `Cargo.toml` (Rust projects): cargo test
   - `go.mod` (Go projects): go test
   - `pom.xml`, `build.gradle` (Java projects): maven, gradle

2. Run the appropriate test command:
   - Node.js: `npm test`, `yarn test`, `pnpm test`, or direct framework command
   - Python: `pytest`, `python -m pytest`, `python -m unittest`
   - Rust: `cargo test`
   - Go: `go test ./...`
   - Java: `mvn test`, `gradle test`

3. Analyze the test results:
   - Report number of tests passed/failed
   - Show detailed output for any failing tests
   - Identify flaky tests if multiple runs show different results
   - Check code coverage if available

4. If tests fail:
   - Show the failure details
   - Suggest potential fixes based on error messages
   - Offer to run specific failing tests in isolation

5. Additional checks:
   - Verify all test files are properly imported/discovered
   - Check for skipped or ignored tests
   - Suggest adding tests for uncovered code if coverage is low

## Output Format

Provide a summary in this format:

```
✅ Test Run Complete

Summary:
- Total: X tests
- Passed: Y tests
- Failed: Z tests
- Skipped: N tests
- Duration: XX.XXs

Coverage: XX% (if available)

[Details of any failures or warnings]
```
