# Add License Headers Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-file editing, bulk operations, syntax awareness, file filtering  
**Duration**: 600 seconds  
**Steps**: ~40

## Objective

Add proper MIT license headers to all Python, JavaScript, and TypeScript source files in a project that currently lack them. This task simulates preparing an internal codebase for open-source release.

## Scenario

Your team's internal CLI tool `data-transformer` has been approved for open-sourcing under the MIT license. The legal team requires that all source files contain proper copyright and license headers before the repository can be made public.

## Requirements

1. **Add headers to files missing them:**
   - All `.py` files in `src/` directory
   - All `.js` files in `src/` directory
   - All `.ts` files in `src/` directory

2. **Use correct comment syntax:**
   - Python: `#` comment style
   - JavaScript/TypeScript: `//` comment style

3. **Header content must include:**
   - Copyright line: `Copyright (c) 2024 DataTransformer Contributors`
   - License: `SPDX-License-Identifier: MIT`
   - Permission statement (3-4 lines summarizing MIT terms)

4. **Placement rules:**
   - Python: Place header AFTER shebang (`#!/usr/bin/env python3`) if present
   - JS/TS: Place header at very beginning of file
   - Leave one blank line between header and code

5. **Skip files:**
   - Files that already have "MIT" or "SPDX-License-Identifier" in first 10 lines
   - Files in `tests/`, `node_modules/`, `__pycache__/`, `.venv/` directories

6. **Reference templates:**
   - See `.templates/license_header_python.txt` for Python format
   - See `.templates/license_header_js.txt` for JavaScript/TypeScript format

## Expected Workflow

1. Open workspace in VSCode
2. Find all Python files in `src/` directory (use Find in Files or Explorer)
3. For each Python file without a license header:
   - Open the file
   - Check if it starts with shebang
   - Add header after shebang (or at start if no shebang)
   - Save file
4. Repeat for JavaScript and TypeScript files (header at file start)
5. Verify excluded files and already-licensed files remain unchanged

## Verification

Checks for:
1. All 3 Python files have valid headers with `#` syntax
2. All 3 JS/TS files have valid headers with `//` syntax
3. Header placed after shebang in `main.py`
4. All headers contain copyright, SPDX-License-Identifier, and permission text
5. Files with existing licenses not modified (no duplicates)
6. Files in excluded directories remain unchanged

**Pass Threshold**: 85% (5/6 criteria or 6/6 with minor issues)

## Tips

- Use multi-cursor editing or Find/Replace to work efficiently
- Reference the template files for exact format
- Check first few lines of each file before adding header
- Test on one file first to ensure correct format