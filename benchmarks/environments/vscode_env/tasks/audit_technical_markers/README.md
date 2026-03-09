# Audit Technical Markers Task

**Difficulty**: 🟡 Medium  
**Skills**: Search, code navigation, bug fixing, documentation, technical debt management  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Systematically audit and address technical debt markers (TODO/FIXME/HACK/XXX) scattered throughout a Python project before code review. This simulates the real-world scenario where a developer has been prototyping fast and needs to clean up before submitting code.

## Scenario

You've been rapidly developing an inventory API over the past week. To move quickly, you left yourself TODO, FIXME, and HACK comments as breadcrumbs. The sprint review is tomorrow, and your team lead reminded you: "No unaddressed TODOs in reviewed code."

## Task Requirements

You must:

1. **Find all technical debt markers** across the project using VSCode search
   - Search for patterns: TODO, FIXME, HACK, XXX
   - Identify which ones are critical bugs vs. nice-to-haves

2. **Create an audit document** at `/home/ga/workspace/inventory-api/TECHNICAL_DEBT.md` containing:
   - List of all markers with file and line references
   - Categorization by severity (Critical / Normal / Deferred)
   - Status for each (Fixed / Documented / Tracked)

3. **Fix critical bugs**:
   - **database.py**: Fix the params=None bug in `execute_query()` function
   - **api.py**: Fix the 404 error handling in `get_item()` function
   - Remove or update FIXME comments after fixing

4. **Document remaining markers** in TECHNICAL_DEBT.md with proper context

## Expected Workflow

1. Use Search (Ctrl+Shift+F) to find all TODO/FIXME/HACK/XXX markers
2. Review each marker and assess severity
3. Fix the critical bugs in database.py and api.py
4. Create TECHNICAL_DEBT.md with structured audit
5. Save all files

## Verification

The verifier checks:
1. TECHNICAL_DEBT.md exists and references multiple files (25 pts)
2. Critical database.py bug fixed (params handling) (30 pts)
3. Critical api.py bug fixed (404 status) (30 pts)
4. Audit document quality (references, categorization, status tracking) (15 pts)

**Pass Threshold**: 70% (70/100 points)

## Tips

- Use Ctrl+Shift+F for workspace-wide search
- Use regex search pattern: `(TODO|FIXME|HACK|XXX)`
- Test your bug fixes mentally before removing comments
- Be thorough - missing markers will reduce audit quality score