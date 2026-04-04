# VSCode Technical Interview Environment Setup Task (`setup_interview_environment@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Workspace management, configuration, file creation, multi-language setup  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Create an isolated, professional coding environment suitable for conducting technical interviews. The environment must be clean, privacy-protected, and support multiple programming languages.

## Expected Workflow

1. Create interview workspace directory: `/home/ga/interview_workspace/`
2. Create `.vscode/` subdirectory inside workspace
3. Create `.vscode/settings.json` with professional settings:
   - Theme: "Default Light+"
   - Font size: 14
   - Auto-save: "afterDelay"
   - Minimap: disabled
   - Activity bar: hidden
4. Create `.vscode/tasks.json` with three language runners:
   - Python: `python3 ${file}`
   - JavaScript: `node ${file}`
   - Java: compile and run
5. Create three starter template files:
   - `starter.py` with function template
   - `starter.js` with function template
   - `Starter.java` with class template
6. Open VSCode with the interview workspace

## Verification

Checks for:
1. Workspace directory structure exists
2. Settings.json configured correctly (theme, font, auto-save, etc.)
3. Tasks.json contains all three language runners
4. All three starter files exist with proper templates
5. Privacy: no personal project references
6. Professional appearance settings applied

**Pass Threshold**: 80% (5/6 criteria with subchecks)