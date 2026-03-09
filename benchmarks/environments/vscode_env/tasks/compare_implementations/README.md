# Compare Implementations Task

**Difficulty**: 🟡 Medium  
**Skills**: Split editor, side-by-side comparison, code analysis  
**Duration**: 120 seconds  
**Steps**: ~15

## Objective

Compare two different implementations of the same data processing pipeline side-by-side in VSCode to identify the key optimization in the functional version.

## Expected Workflow

1. Open File Explorer (Ctrl+Shift+E)
2. Navigate to `pipelines/traditional_pipeline.py` and open it
3. Split editor view (Ctrl+\ or right-click → "Split Right")
4. In the right pane, open `pipelines/functional_pipeline.py`
5. Compare both implementations visually
6. Identify the optimization in the functional version (memoization with @lru_cache)
7. Create `comparison_notes.txt` documenting the optimization

## Implementations

**traditional_pipeline.py**: Loop-based imperative approach  
**functional_pipeline.py**: Functional programming with @lru_cache optimization

## Verification

Checks for:
1. Both implementation files exist and contain expected patterns
2. comparison_notes.txt exists
3. Comparison notes mention the optimization (memoization/lru_cache/cache)
4. Files were actually compared (notes have specific details)

**Pass Threshold**: 70% (requires notes file with optimization identified)