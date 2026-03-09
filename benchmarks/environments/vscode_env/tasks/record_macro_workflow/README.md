# Record Macro Workflow Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-cursor editing, find-and-replace, pattern recognition, bulk operations  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Transform 20 similar Python functions by applying a consistent editing pattern using multi-cursor editing, find-and-replace with regex, or macro-like approaches. This tests the ability to automate repetitive edits efficiently.

## Scenario

You're refactoring a legacy Python module (`data_processors.py`) containing 20 data transformation functions. Each function follows an identical pattern but needs the same three modifications:
1. Add type hints to function signature: `(raw_data: str) -> str`
2. Insert a logging statement at the start: `logging.info(f"Processing {name} data")`
3. Wrap the core logic in a try-except block with error logging

## Initial State

File `data_processors.py` contains 20 functions with this structure: