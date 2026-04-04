# Audit TODO Comments Task

**Difficulty**: 🟡 Medium  
**Skills**: Search & Find, Regex patterns, Documentation, Code review preparation  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Audit and document all TODO/FIXME/HACK markers in a Python authentication service codebase before code review. Create a comprehensive inventory in a markdown file.

## Scenario

You're a backend developer preparing for tomorrow's code review. Over the past two weeks, you've left scattered TODO comments throughout your authentication service implementation. Now you need to inventory them to decide which must be resolved before the PR and which can become follow-up tickets.

## Expected Workflow

1. Open the workspace (`/home/ga/workspace/auth_service`)
2. Use Find in Files (Ctrl+Shift+F) to search for TODO markers
3. Enable regex search and use pattern: `TODO|FIXME|HACK|XXX|NOTE`
4. Review all search results across files
5. Create a new file: `TODO_AUDIT.md`
6. Document each finding with:
   - File path and line number
   - The actual comment text
   - Optional: Categorization (Critical, Follow-up, etc.)
7. Add structure using markdown headers, bullet points
8. Save the file (Ctrl+S)

## Files in the Workspace

- `auth.py` - Main authentication logic (has TODO/FIXME/XXX comments)
- `middleware.py` - Request middleware (has TODO/FIXME/XXX comments)
- `config.py` - Configuration settings (has FIXME/TODO comments)
- `tests/test_auth.py` - Unit tests (has TODO/NOTE comments)
- `README.md` - Project readme (has TODO/FIXME comments)

## Verification

Checks for:
1. `TODO_AUDIT.md` file exists
2. Contains references to source files
3. Documents actual TODO markers found in code
4. Has structure (headers, bullets, line numbers)
5. **BONUS**: Resolving or removing some TODOs

**Pass Threshold**: 60% (score ≥ 0.6)

## Tips

- Use **Ctrl+Shift+F** to open Find in Files
- Click the regex button (.*) in the search box
- Search for: `(TODO|FIXME|HACK|XXX|NOTE):`
- You can click on search results to jump to the file location
- Use markdown formatting in TODO_AUDIT.md for better readability