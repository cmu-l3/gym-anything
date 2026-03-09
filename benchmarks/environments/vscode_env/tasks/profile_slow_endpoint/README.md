# Profile Slow Endpoint Task

**Difficulty**: 🟡 Medium  
**Skills**: Performance profiling, terminal usage, documentation, code analysis  
**Duration**: 480 seconds  
**Steps**: ~50

## Objective

Profile a slow API endpoint to identify the performance bottleneck, document your findings, and annotate the problematic code.

## Scenario

You're a backend developer investigating why the `/api/process-orders` endpoint is timing out. Response times are 5+ seconds during peak traffic. You need to profile the code, identify which function is causing the slowdown, and document your findings.

## Expected Workflow

1. Open integrated terminal (Ctrl+`)
2. Navigate to workspace root
3. Run profiling script: `python tests/test_performance.py`
4. Analyze the generated `profile_results.txt`
5. Identify the bottleneck function (`enrich_customer_data`)
6. Document findings in `PERFORMANCE.md`
7. Add TODO comment to `src/utils/external_api.py`

## Verification

Checks for:
1. Profiling script was executed (profile_results.txt exists)
2. Performance documentation created (PERFORMANCE.md)
3. Correct bottleneck identified (enrich_customer_data)
4. TODO comment added to problematic code

**Pass Threshold**: 95% (all criteria met)