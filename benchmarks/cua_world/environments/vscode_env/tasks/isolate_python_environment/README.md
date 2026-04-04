# Isolate Python Environment Task

**Difficulty**: 🟡 Medium  
**Skills**: Python virtual environments, dependency management, VSCode interpreter configuration  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Set up a Python virtual environment for a project with specific dependency versions and configure VSCode to use it. This simulates the common scenario where a project requires different package versions than your global Python environment.

## Scenario

You've cloned a Python data analysis project that requires specific versions of pandas (1.5.3) and numpy (1.23.5). Your global Python has newer versions installed, causing import conflicts. You need to:

1. Create an isolated virtual environment
2. Install the correct dependency versions
3. Configure VSCode to use the virtual environment

## Expected Workflow

1. Open VSCode's integrated terminal (Ctrl+` or View → Terminal)
2. Create virtual environment: `python3 -m venv venv`
3. Activate environment: `source venv/bin/activate`
4. Install dependencies: `pip install -r requirements.txt`
5. Configure VSCode interpreter:
   - Open Command Palette (Ctrl+Shift+P)
   - Type "Python: Select Interpreter"
   - Choose `./venv/bin/python` or create workspace settings manually

## Verification

Checks for:
1. Virtual environment created at `/home/ga/workspace/sales_analysis/venv/`
2. Required packages installed (pandas, numpy, matplotlib) with correct versions
3. VSCode workspace settings point to venv interpreter
4. Imports work from venv Python

**Pass Threshold**: 75% (3/4 criteria)

## Tips

- The requirements.txt file specifies exact versions to install
- VSCode should auto-detect the venv, but you may need to select it manually
- Check the bottom-left status bar to see which Python interpreter is active
- You can verify installation with: `venv/bin/python -c "import pandas; print(pandas.__version__)"`