# Experiment with Compiler Flags Task

**Difficulty**: 🟡 Medium  
**Skills**: Build configuration, VSCode tasks, compiler optimization  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure VSCode's task system to enable rapid experimentation with GCC compiler optimization flags. Create multiple build configurations that compile the same C++ source file with different optimization levels (-O0, -O2, -O3, -Ofast).

## Expected Workflow

1. Open the workspace in VSCode
2. Create `.vscode/` directory in the workspace
3. Create `tasks.json` file
4. Define at least 4 build tasks with different optimization flags
5. Ensure each task produces uniquely named output binaries
6. Give each task a descriptive label

## Example Task Structure
