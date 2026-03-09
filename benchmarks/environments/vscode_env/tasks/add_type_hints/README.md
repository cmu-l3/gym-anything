# Add Type Hints Task

**Difficulty**: 🟡 Medium  
**Skills**: Python type hints, typing module, code modernization, AST analysis  
**Duration**: 240 seconds  
**Steps**: ~20

## Objective

Modernize legacy Python code by adding comprehensive type hints to all function signatures. Add necessary imports from the `typing` module and annotate parameters and return types for all functions in `data_processor.py`.

## Context

A development team inherited a Python 2.7 codebase that was mechanically converted to Python 3.8. The code runs but lacks type annotations. The team wants to enable mypy for static type checking but needs type hints first. Your job is to add comprehensive type hints to the `data_processor.py` module.

## Expected Implementation

The file contains 5 functions that need type hints:
1. `calculate_average` - Takes list of numbers, returns optional float
2. `format_user_data` - Takes user fields, returns dictionary
3. `filter_by_threshold` - Takes list and threshold, returns filtered list
4. `merge_configs` - Takes two config dicts (second optional), returns merged dict
5. `process_records` - Takes records and optional max limit, returns processed records

## Required Changes

1. Add typing imports: `from typing import List, Dict, Optional, Any`
2. Add type hints to all parameters
3. Add return type annotations to all functions
4. Use `Optional[T]` for parameters/returns that can be None
5. Use collection generics: `List[T]`, `Dict[K, V]` (not bare `list`, `dict`)

## Verification

Checks for:
1. Correct typing imports present (20%)
2. All 5 functions fully annotated (30%)
3. Optional types used correctly (25%)
4. Collection generics used properly (25%)

**Pass Threshold**: 80% (requires all 4 criteria with minimal issues)