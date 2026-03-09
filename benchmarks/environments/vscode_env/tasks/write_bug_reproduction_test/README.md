# Write Bug Reproduction Test Task

**Difficulty**: 🟡 Medium  
**Skills**: Testing, debugging, pytest, code reading, test-driven development  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Convert a vague bug report into a concrete, failing test case. This task simulates the common developer workflow of test-driven debugging: write a test that proves the bug exists before fixing it.

## Scenario

A QA engineer filed bug report #4729:
> "The `normalize_whitespace` function crashes when processing certain edge cases with empty inputs. This breaks the import pipeline on production."

Your job:
1. Locate the buggy `normalize_whitespace` function in `src/text_utils.py`
2. Read the implementation to understand what might cause crashes
3. Write a test in `tests/test_text_utils.py` that reproduces the bug
4. Run the test to verify it fails (proving the bug exists)
5. Document what you're testing

## Expected Test Structure
