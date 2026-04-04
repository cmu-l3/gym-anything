# VSCode JSON Validation Task (`validate_json_config@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Problem diagnosis, JSON validation, documentation, VSCode Problems panel  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Identify and document validation errors in corrupted JSON configuration files using VSCode's built-in JSON validation features. Create a clear markdown report of all issues found.

## Scenario

You've received configuration files from a third-party integration. When loading the application, it crashes with cryptic errors. You need to quickly identify what's wrong with the JSON files before the demo call in 30 minutes.

## Expected Workflow

1. Observe that VSCode shows JSON errors (red squiggly lines, status bar error count)
2. Open Problems panel (Ctrl+Shift+M or View → Problems)
3. Examine each error by clicking on it in the Problems panel
4. Review the JSON files: config.json, database.json, api_settings.json
5. Create a file named `validation_report.md` in the workspace root
6. Document each error with:
   - File name and line number
   - Clear description of the issue
   - Severity (Critical/Warning)
   - Suggested fix (optional)
7. Save the report (Ctrl+S)

## Expected Report Structure
