# Fix Broken IntelliSense Task

**Difficulty**: 🟡 Medium  
**Skills**: Python environment troubleshooting, language server debugging, interpreter configuration  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Diagnose and fix a broken Python IntelliSense/language server in VSCode. The scenario involves a data scientist whose IntelliSense stopped working after package installation - imports show red errors, no autocomplete, go-to-definition fails, but code executes correctly.

## Problem Context

A Python workspace has a virtual environment with all required packages installed (`numpy`, `pandas`, `scikit-learn`). However, VSCode is configured to use the global Python interpreter instead of the venv, causing IntelliSense to fail because it can't find the installed packages.

## Expected Workflow

1. Notice import statements have red squiggly underlines in Python files
2. Open Command Palette (Ctrl+Shift+P)
3. Type "Python: Select Interpreter"
4. Select the correct interpreter (venv: `./venv/bin/python` or similar)
5. Reload window (Ctrl+Shift+P → "Developer: Reload Window")
6. Verify imports no longer show errors

## Verification

Checks for:
1. Workspace settings configured with correct interpreter (venv path)
2. Pylance extension installed and enabled
3. Settings.json contains venv interpreter path
4. Extension directory shows Python + Pylance present

**Pass Threshold**: 70% (requires correct interpreter configuration + extensions healthy)