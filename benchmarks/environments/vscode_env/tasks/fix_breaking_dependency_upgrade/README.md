# Fix Breaking Dependency Upgrade Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-file search, API migration, refactoring, dependency management  
**Duration**: 600 seconds (10 minutes)  
**Steps**: ~40

## Objective

Upgrade the `requests` library from version 2.25.1 to 2.31.0 and fix all breaking API changes across the codebase. This simulates a common real-world scenario where security vulnerabilities force immediate dependency upgrades that break existing code.

## Scenario

You maintain a Python web scraping service that monitors competitor prices. A security audit has flagged `requests==2.25.1` as vulnerable (CVE-2023-32681). You must upgrade to `requests>=2.31.0` immediately and fix all breaking changes.

## Breaking Changes (Documented in UPGRADE_NOTES.md)

The main breaking change is the **timeout parameter**:
- **Old API (2.25.1)**: `timeout=30` (single integer)
- **New API (2.31.0)**: `timeout=(5, 30)` (tuple: connect_timeout, read_timeout)

Recommended migration: Use `timeout=(old_value/3, old_value)` for backward compatibility.

## Files to Update

1. **requirements.txt** - Change `requests==2.25.1` to `requests>=2.31.0`
2. **scraper/core.py** - Has 2 timeout parameters to fix
3. **scraper/utils.py** - Has 3 timeout parameters to fix
4. **scraper/proxy_handler.py** - Has 2 timeout parameters to fix
5. **tests/test_scraper.py** - Has 1 timeout parameter to fix

**Total**: 8 timeout parameters need conversion to tuple format.

## Expected Workflow

1. Open the workspace in VSCode
2. Read `UPGRADE_NOTES.md` to understand the breaking changes
3. Use **Find in Files** (Ctrl+Shift+F) to search for `timeout=` patterns
4. Update `requirements.txt` to specify `requests>=2.31.0`
5. Navigate through each file and convert `timeout=<int>` to `timeout=(<int/3>, <int>)`
6. Save all modified files (Ctrl+K S or File → Save All)

## Verification

Checks for:
1. ✅ requirements.txt updated to >=2.31.0
2. ✅ No old single-integer timeout patterns remain
3. ✅ At least 6 new tuple timeout patterns exist
4. ✅ All Python files are syntactically valid

**Pass Threshold**: All 4 criteria must pass (100%)

## Tips

- Use workspace search (Ctrl+Shift+F) to find all `timeout=` occurrences
- The UPGRADE_NOTES.md file documents exactly what needs to change
- Use Find & Replace (Ctrl+H) for systematic updates
- Don't forget to save all files when done