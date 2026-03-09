# VSCode Code Coverage Visualization Task (`visualize_coverage_gaps@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Extension installation, test coverage, configuration management  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Set up code coverage visualization in VSCode to identify untested code before a release. Install a coverage extension, generate a coverage report from existing tests, configure the extension to display coverage indicators, and verify that coverage gaps are visible in the editor.

## Scenario

You're preparing for a release when your team lead asks "What's our test coverage?" You realize you have tests but no visibility into what code is actually covered. You need to quickly set up coverage visualization to identify gaps before the release deadline.

## Expected Workflow

1. Open Command Palette (`Ctrl+Shift+P`)
2. Install a coverage visualization extension (e.g., "Coverage Gutters")
3. Open integrated terminal (`Ctrl+` ` `)
4. Generate coverage report: `pytest --cov=. --cov-report=xml`
5. Configure extension to use the coverage file
6. Activate coverage display via Command Palette or extension controls
7. Observe coverage indicators (green/red) in editor gutter

## Project Structure

The workspace contains a Python project with intentional coverage gaps:
