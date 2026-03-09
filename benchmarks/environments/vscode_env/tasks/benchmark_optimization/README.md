# Benchmark Optimization Task

**Difficulty**: 🟡 Medium  
**Skills**: Performance analysis, code evaluation, terminal usage, empirical testing  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Empirically benchmark two implementations of a data processing function, verify correctness, and keep the faster version only if output is identical.

## Scenario

You inherited a Python data processing script that's become a pipeline bottleneck. A colleague suggested an optimized implementation. Before committing the change, you must:
1. Measure original execution time
2. Apply the optimization
3. Measure optimized execution time
4. Verify both produce identical output
5. Make data-driven decision (keep faster if correct)
6. Document findings

## Expected Workflow

1. Open integrated terminal (Ctrl+` or View → Terminal)
2. Navigate to `/home/ga/workspace/benchmark_task/`
3. Run original: `python data_processor.py test_data.json`
4. Note execution time (printed at end)
5. Backup original output: `cp output.json output_original.json`
6. Open both `data_processor.py` and `optimized_transform.py`
7. Replace `transform_records()` function with optimized version
8. Run optimized: `python data_processor.py test_data.json`
9. Note new execution time
10. Verify outputs match: `diff output_original.json output.json` or manual check
11. Create `benchmark_report.txt` documenting results
12. Keep faster version if output matches; otherwise revert

## Report Format

Create `benchmark_report.txt` with: