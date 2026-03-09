# Prepare Tutorial Snippet Task

**Difficulty**: 🟡 Medium  
**Skills**: Code comprehension, simplification, documentation, teaching  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Extract and simplify production-grade code into an educational tutorial snippet suitable for a blog post. You'll transform a complex rate limiter implementation into a clear, beginner-friendly example.

## Scenario

You're writing a blog post about implementing rate limiting in Python. You have production code with Redis, logging, error handling, and metrics—but readers need to understand the CORE CONCEPT without drowning in infrastructure complexity.

## Expected Workflow

1. Read `/home/ga/workspace/production/rate_limiter.py` (production code)
2. Understand the token bucket algorithm at its core
3. Create `/home/ga/workspace/tutorial/simple_rate_limiter.py`
4. Extract ONLY the essential algorithm logic
5. Simplify variable names to be educational (e.g., `tokens_available`, `last_refill_time`)
6. Remove production concerns: Redis, logging, error handling, config, metrics
7. Add explanatory comments for tutorial readers
8. Keep it under 50 lines and syntactically valid

## Requirements

Your tutorial version must:
- Be valid Python (no syntax errors)
- Contain the core token bucket logic (token refill calculation, token consumption)
- Use descriptive variable names (no abbreviations like `tkn`, `rt`)
- Include at least 3 explanatory comments
- Be under 50 lines of code
- Remove all production infrastructure (Redis, logging, Config, MetricsCollector)
- Be self-contained (only stdlib imports like `time`)

## Verification

Checks for:
1. File exists at correct path
2. Valid Python syntax
3. Line count < 50
4. Production concerns removed
5. Core token bucket logic present
6. Explanatory comments added
7. Descriptive variable names used

**Pass Threshold**: 75% (score >= 0.75)