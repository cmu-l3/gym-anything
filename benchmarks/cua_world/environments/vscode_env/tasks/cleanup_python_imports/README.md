# Cleanup Python Imports Task

**Difficulty**: 🟡 Medium  
**Skills**: Python imports, code organization, PEP 8, code hygiene  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Clean up and organize Python imports in a messy file by removing unused imports and organizing them according to PEP 8 guidelines (standard library, third-party, local imports).

## Scenario

You've just merged code from multiple team members. Each contributor had different import styles, and many imports became unused after refactoring. Before pushing to main, you need to clean up `data_processor.py` to remove unused imports and organize the remaining ones.

## Expected Workflow

1. Open `/home/ga/workspace/cleanup_imports_task/myproject/data_processor.py`
2. Identify unused imports (VSCode Python extension grays them out)
3. Remove all unused imports
4. Organize remaining imports into PEP 8 sections:
   - Standard library imports (e.g., `json`, `logging`)
   - Third-party imports (e.g., `pandas`, `numpy`)
   - Local imports (e.g., `from .utils import ...`)
5. Save the file

## Verification

Checks for:
1. All unused imports removed (9 imports should be removed)
2. All used imports preserved (no false removals)
3. Imports organized (local imports after standard/third-party)
4. No syntax errors introduced

**Pass Threshold**: 80% (reward >= 0.8)