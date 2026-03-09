# Modernize Tutorial Code Task

**Difficulty**: 🟡 Medium  
**Skills**: Code adaptation, Python modernization, refactoring, style compliance  
**Duration**: 480 seconds  
**Steps**: ~100

## Objective

Adapt outdated Python 2 tutorial code to modern Python 3.10+ standards while preserving functionality. This simulates the common real-world scenario of adapting Stack Overflow or blog post examples to match your project's coding standards.

## Scenario

You found a perfect rate limiter decorator example from a 2015 blog post that does exactly what you need. However, the code uses Python 2 syntax, has hardcoded values, inconsistent naming conventions, and lacks type hints. Your tech lead will reject any PR that doesn't follow the project's Python 3.10+ standards.

## Task Requirements

1. **Study the example code** in `rate_limiter_example.py`
2. **Modernize it** in `utils/decorators.py` following project standards:
   - Use Python 3 syntax (print functions, f-strings)
   - Add comprehensive type hints
   - Use snake_case naming (not camelCase)
   - Replace print statements with proper logging
   - Add Google-style docstrings
3. **Preserve functionality** - tests must pass
4. **Follow style guide** - pylint and black compliance

## Expected Implementation

The decorator should:
- Accept `max_calls` and `time_window_seconds` parameters
- Track calls in a sliding time window
- Delay execution when rate limit is exceeded
- Use logging instead of print statements
- Include type hints for all parameters and return values

## Verification

Checks for:
1. **Functional correctness** (50%): All tests pass
2. **Code modernization** (30%): Type hints, f-strings, docstrings, logging, snake_case
3. **Style compliance** (20%): pylint score >= 8.0, black formatting

**Pass Threshold**: 75% overall score