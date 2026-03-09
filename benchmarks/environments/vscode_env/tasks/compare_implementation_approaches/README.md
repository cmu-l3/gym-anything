# Compare Implementation Approaches Task

**Difficulty**: 🟡 Medium  
**Skills**: Code comparison, testing, decision-making, documentation  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Compare two competing Python implementations, test their performance, make an evidence-based decision on which to keep, document your reasoning, and archive the non-selected implementation.

## Scenario

You've experimented with two approaches to implement a data processing function:
- `data_processor_iterative.py` - Traditional loop-based approach
- `data_processor_functional.py` - Functional programming style (map/filter)

Both implementations work, but you need to systematically compare them and choose one.

## Expected Workflow

1. Open both implementation files in VSCode
2. Use VSCode's compare/diff feature:
   - Right-click one file → "Select for Compare"
   - Right-click other file → "Compare with Selected"
   - OR use `Ctrl+Shift+P` → "File: Compare Active File With..."
3. Open integrated terminal (`Ctrl+`\`)
4. Run tests: `python test_processor.py`
5. Analyze output (correctness, performance)
6. Create file `DECISION.md` documenting:
   - Which implementation you chose
   - Why (performance, readability, maintainability)
   - Trade-offs considered
7. Rename non-selected file to add `.archived` extension (e.g., `data_processor_iterative.py.archived`)

## Verification

Checks for:
1. `DECISION.md` exists with sufficient content (>50 chars)
2. Exactly one implementation has `.archived` extension
3. One implementation remains active (no extension)
4. Decision mentions the chosen implementation name
5. Decision includes justification keywords

**Pass Threshold**: 80% (4/5 criteria)