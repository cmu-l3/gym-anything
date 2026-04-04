# Competitive Coding Setup Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: VSCode tasks, keybindings, snippets, automated testing  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure VSCode for competitive programming by creating automated test validation, keyboard shortcuts, and code snippets. Then solve a simple problem (sum of two numbers) using the setup.

## Expected Workflow

1. **Create VSCode Task** (`.vscode/tasks.json`):
   - Create a task named "Run All Tests"
   - Task should run solution against all test cases
   - Compare output with expected output
   - Report pass/fail for each test

2. **Create Keybinding** (`.vscode/keybindings.json`):
   - Bind `Ctrl+Shift+T` to run the task

3. **Create Code Snippet** (`.vscode/cp_template.code-snippets`):
   - Create snippet with prefix "cp"
   - Include basic competitive programming template

4. **Solve Problem**:
   - Implement solution in `problem_A.py`
   - Read two integers from stdin
   - Output their sum
   - Test against provided test cases

## Files to Create

- `.vscode/tasks.json` - Automated test runner
- `.vscode/keybindings.json` - Keyboard shortcut
- `.vscode/cp_template.code-snippets` - Code template
- `problem_A.py` - Solution implementation
- `run_tests.sh` (optional helper script for task)

## Verification

Checks for:
1. Tasks.json contains "Run All Tests" task
2. Keybinding for Ctrl+Shift+T exists
3. Code snippet with prefix "cp" exists
4. Solution file has implementation
5. Solution passes all test cases

**Pass Threshold**: 70% (3.5/5 criteria)