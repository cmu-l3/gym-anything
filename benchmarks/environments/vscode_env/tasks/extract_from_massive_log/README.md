# Extract from Massive Log Task

**Difficulty**: 🟡 Medium  
**Skills**: Large file handling, CLI tools, VSCode configuration, terminal proficiency  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

A 450MB production log file is causing VSCode performance issues. Extract all critical payment errors with surrounding context using command-line tools, and configure VSCode for better large-file handling.

## Scenario

Production incident: Payment gateway timeouts. The SRE team dumped 8 hours of logs into a massive 450MB file. You need to extract all occurrences of `"CRITICAL: Payment gateway timeout - transaction failed"` with 2 lines of context before and after each error for analysis.

Opening the file directly in VSCode will freeze the editor, so you must use terminal tools.

## Expected Workflow

1. **Configure VSCode for large files**:
   - Open Settings (Ctrl+,) or edit `.vscode/settings.json`
   - Set `files.maxMemoryForLargeFilesMB` to at least 1024
   - Save settings

2. **Use integrated terminal** (Ctrl+`):
   - Navigate to `/home/ga/workspace/incident_logs/`
   - Use `grep` with context flags to extract errors
   - Example: `grep -B 2 -A 2 "CRITICAL: Payment gateway timeout - transaction failed" production_dump.log > payment_failures.log`

3. **Verify extraction**:
   - Open the smaller `payment_failures.log` in VSCode
   - Verify it contains errors with context

## Required Output

- **Settings**: `files.maxMemoryForLargeFilesMB` >= 1024 (workspace or user settings)
- **Extracted file**: `/home/ga/workspace/incident_logs/payment_failures.log`
  - Contains all ~34 critical errors
  - Includes 2 lines before and after each error
  - File size < 500 KB

## Verification

Checks for:
1. Large file memory configuration (30%)
2. Extracted file exists with correct errors (40%)
3. File size optimized (10%)
4. CLI tool usage evidence (20%)

**Pass Threshold**: 80%

## Tips

- DO NOT open the 450MB file directly in VSCode
- Use `Ctrl+` ` to open integrated terminal
- Use `grep -B 2 -A 2 "pattern" file` for context extraction
- Verify extraction worked: `wc -l payment_failures.log`