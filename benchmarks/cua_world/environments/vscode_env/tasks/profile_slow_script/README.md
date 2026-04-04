# Profile Slow Script Task

**Difficulty**: 🟡 Medium  
**Skills**: Performance profiling, timing instrumentation, data analysis, documentation  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Investigate a slow data processing script by adding performance timing instrumentation, identifying the bottleneck, and documenting findings.

## Scenario

A batch data processing script (`data_processor.py`) has become unacceptably slow after recent changes. Users are complaining that processing 1000 rows takes several seconds. Your task is to add timing measurements to identify which stage is causing the slowdown.

## Expected Workflow

1. Open the workspace containing `data_processor.py`
2. Read the script to understand its structure (read → validate → transform → write)
3. Add timing instrumentation:
   - Import `time` module
   - Measure duration of each processing stage
   - Print timing results
4. Execute the script to observe timing
5. Identify the bottleneck from timing data
6. Document findings in `performance_analysis.md`

## Verification

Checks for:
1. Timing code added (import time, timing measurements)
2. Script executes successfully (output file created)
3. Documentation file created (`performance_analysis.md`)
4. Bottleneck correctly identified (validation stage)
5. Evidence provided (timing numbers in document)

**Pass Threshold**: 70% (requires functional timing, correct identification, and basic documentation)