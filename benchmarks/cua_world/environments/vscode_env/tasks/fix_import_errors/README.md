# Fix Import Errors Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: Python dependencies, troubleshooting, requirements.txt, package management  
**Duration**: 180 seconds  
**Steps**: ~60

## Objective

Fix a Python project with missing and incorrect dependencies in `requirements.txt`. The project has import errors because:
1. Some required packages are missing from requirements.txt
2. One package name is outdated/incorrect (sklearn vs scikit-learn)

## Scenario

You've inherited a data analysis project from a colleague who's on vacation. When you try to run the script, imports fail. Your task is to identify and fix the dependency issues.

## Expected Workflow

1. Open the project in VSCode (`/home/ga/workspace/data_analysis`)
2. Try running the script to see what fails: `python analyze_data.py`
3. Identify missing dependencies from error messages
4. Open and edit `requirements.txt`
5. Add missing package: `requests`
6. Fix incorrect package name: `sklearn` → `scikit-learn`
7. Save the file
8. Test with: `python test_imports.py`

## Verification

Checks for:
1. `requests` package added to requirements.txt
2. `scikit-learn` (correct name) present in requirements.txt
3. `sklearn` (wrong name) NOT present in requirements.txt
4. Original packages (pandas, numpy, matplotlib) still present

**Pass Threshold**: 100% (all criteria must pass)

## Common Pitfall

The package imported as `from sklearn import ...` is actually installed as `scikit-learn`, not `sklearn`. This is a notorious Python packaging confusion that trips up many developers!