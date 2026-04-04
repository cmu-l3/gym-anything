# Reconstruct Work Context Task

**Difficulty**: 🟡 Medium  
**Skills**: Git integration, workspace search, code navigation, documentation  
**Duration**: 480 seconds (8 minutes)  
**Steps**: ~40

## Objective

You are returning to a project after being away for 3 weeks. You were implementing a feature but were pulled away for emergency work. Now you need to quickly understand what you were working on by investigating the workspace state and creating a comprehensive summary document.

## Scenario

Your workspace contains:
- A Python project on a feature branch (`feature/user-validation`)
- Multiple files with uncommitted changes
- TODO/FIXME comments scattered throughout the code
- Some tests passing, some failing
- A partially implemented user validation feature

## Expected Workflow

1. **Investigate Git State**:
   - Open integrated terminal (Ctrl+`)
   - Run `git status` to see modified files
   - Run `git diff` to see changes
   - Use Source Control view (Ctrl+Shift+G) to inspect changes visually

2. **Search for TODOs**:
   - Use global search (Ctrl+Shift+F)
   - Search for "TODO" and "FIXME"
   - Note locations and descriptions

3. **Review Modified Files**:
   - Navigate through changed files
   - Understand what each modification does

4. **Create Summary Document**:
   - Create file `WORK_CONTEXT.md` in workspace root (`/home/ga/workspace/myproject/`)
   - Document your findings

## Required Document Structure

The `WORK_CONTEXT.md` must include these sections:

- **Modified Files**: List of changed files with descriptions
- **Outstanding TODOs**: List of TODO/FIXME items with locations
- **Current Status**: What's working vs. broken
- **Next Steps**: Recommended actions

## Verification

Checks for:
1. Document exists at workspace root
2. Contains required sections
3. References actual modified files (user_routes.py, validators.py, user.py, test files)
4. Lists TODO/FIXME items with locations
5. Has structured format (headers, lists)
6. Document is substantial (>500 chars)
7. Git commands were used (bash history)

**Pass Threshold**: 70% (5/7 criteria)