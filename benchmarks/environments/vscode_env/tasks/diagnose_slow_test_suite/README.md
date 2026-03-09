# Diagnose Slow Test Suite Task

**Difficulty**: 🟡 Medium  
**Skills**: Performance analysis, pytest profiling, code investigation, technical documentation  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Investigate a Python test suite that has degraded from ~45 seconds to 6+ minutes execution time. Identify slow tests, analyze root causes, and document findings with actionable recommendations.

## Scenario

You're a mid-level backend developer. Over the past 2 months, the test suite has become painfully slow, killing productivity. Developers are now skipping tests locally and waiting too long for CI feedback. Your team needs to know which tests got slow and why.

## Expected Workflow

1. **Read instructions** in `TASK_INSTRUCTIONS.md`
2. **Run pytest with profiling**: Execute `pytest --durations=20` to identify slow tests
3. **Investigate slow tests**: 
   - Open test files in VSCode
   - Search for anti-patterns: `time.sleep`, `requests.get`, real database calls
   - Check fixtures in `conftest.py`
4. **Document findings**: Create `TEST_PERFORMANCE_ANALYSIS.md` with:
   - Top 5 slowest individual tests (with times and locations)
   - Top 3 slowest test files (with aggregate times)
   - At least 3 specific performance issues (e.g., "test_auth.py:42 has time.sleep(5)")
   - At least 3 actionable recommendations (e.g., "Replace sleep with mock time")

## Project Structure
