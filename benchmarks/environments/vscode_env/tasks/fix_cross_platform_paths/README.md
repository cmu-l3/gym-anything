# Fix Cross-Platform Paths Task

**Difficulty**: 🟡 Medium  
**Skills**: Code refactoring, cross-platform compatibility, Python path handling  
**Duration**: 600 seconds (10 minutes)  
**Steps**: ~50

## Objective

Fix hardcoded Unix-style paths in a Python application to make it work correctly on Windows. Replace string concatenations like `"config/database.conf"` with platform-agnostic alternatives using `pathlib.Path` or `os.path.join()`.

## Scenario

A Python data processing application works perfectly on macOS/Linux but crashes on Windows with: