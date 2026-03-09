#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Modernize Tutorial Code Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_client"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create the outdated tutorial code (Python 2 style)
cat > "$WORKSPACE_DIR/rate_limiter_example.py" << 'EOF'
# Rate Limiter Example from Tutorial (2015)
# Source: https://example-blog.com/python-rate-limiting

import time
from functools import wraps

def rateLimiter(maxCalls, timePeriod):
    """Decorator to limit function calls"""
    calls = []
    
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            now = time.time()
            # Remove old calls
            calls_in_window = [c for c in calls if now - c < timePeriod]
            calls[:] = calls_in_window
            
            if len(calls) >= maxCalls:
                sleep_time = timePeriod - (now - calls[0])
                print "Rate limit exceeded, sleeping for %s seconds" % sleep_time
                time.sleep(sleep_time)
                calls.pop(0)
            
            calls.append(time.time())
            return func(*args, **kwargs)
        return wrapper
    return decorator


# Example usage
@rateLimiter(5, 1.0)
def apiCall(endpoint):
    print "Calling API:", endpoint
    return {"status": "success"}


if __name__ == "__main__":
    for i in range(10):
        result = apiCall("/users/%d" % i)
        print "Result:", result
EOF

# Create target file with template
cat > "$WORKSPACE_DIR/utils/decorators.py" << 'EOF'
"""
API utility decorators

Adapt the rate limiter from rate_limiter_example.py to modern Python standards.
"""
import time
from functools import wraps
from typing import Callable, Any

# TODO: Implement rate_limit decorator here
# Requirements:
# - Function name: rate_limit (snake_case)
# - Parameters: max_calls (int), time_window_seconds (float)
# - Use Python 3.10+ syntax (f-strings, type hints)
# - Use logging instead of print statements
# - Add comprehensive docstrings (Google style)
# - Preserve the sliding window functionality from the example

EOF

# Create __init__.py for utils package
cat > "$WORKSPACE_DIR/utils/__init__.py" << 'EOF'
"""API client utilities"""
from .decorators import rate_limit

__all__ = ['rate_limit']
EOF

# Create test file
cat > "$WORKSPACE_DIR/tests/test_rate_limiter.py" << 'EOF'
"""Tests for rate limiter decorator"""
import time
import pytest
from utils.decorators import rate_limit


def test_rate_limiter_allows_calls_within_limit():
    """Test that calls within rate limit are allowed"""
    call_count = 0
    
    @rate_limit(max_calls=5, time_window_seconds=1.0)
    def test_func():
        nonlocal call_count
        call_count += 1
        return "success"
    
    # Should complete quickly (all within limit)
    start = time.time()
    for _ in range(5):
        test_func()
    duration = time.time() - start
    
    assert call_count == 5
    assert duration < 0.5  # Should be nearly instant


def test_rate_limiter_enforces_limit():
    """Test that rate limiter delays calls exceeding limit"""
    call_times = []
    
    @rate_limit(max_calls=3, time_window_seconds=1.0)
    def test_func():
        call_times.append(time.time())
        return "success"
    
    # Make 6 calls (should trigger rate limiting)
    for _ in range(6):
        test_func()
    
    assert len(call_times) == 6
    
    # Check that calls are properly spaced
    # First 3 should be fast, next 3 should be delayed
    first_batch_duration = call_times[2] - call_times[0]
    total_duration = call_times[5] - call_times[0]
    
    assert first_batch_duration < 0.5
    assert total_duration >= 1.0  # Should take at least 1 second due to rate limiting


def test_rate_limiter_returns_function_result():
    """Test that decorator preserves return values"""
    @rate_limit(max_calls=10, time_window_seconds=1.0)
    def test_func(x, y):
        return x + y
    
    result = test_func(5, 3)
    assert result == 8
EOF

# Create tests __init__.py
touch "$WORKSPACE_DIR/tests/__init__.py"

# Create pylintrc
cat > "$WORKSPACE_DIR/.pylintrc" << 'EOF'
[MESSAGES CONTROL]
disable=missing-module-docstring,too-few-public-methods

[FORMAT]
max-line-length=100

[BASIC]
good-names=i,j,k,ex,_,f,fp,fn

[DESIGN]
max-args=5
max-locals=15
EOF

# Create pyproject.toml
cat > "$WORKSPACE_DIR/pyproject.toml" << 'EOF'
[tool.black]
line-length = 100
target-version = ['py310']

[tool.isort]
profile = "black"
line_length = 100

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = "test_*.py"
python_functions = "test_*"
EOF

# Create README for context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# API Client Library

## Task: Modernize Rate Limiter

The file `rate_limiter_example.py` contains a working rate limiter from a 2015 tutorial,
but it uses outdated Python 2 syntax and doesn't follow our coding standards.

Your task is to adapt it to modern Python 3.10+ standards in `utils/decorators.py`.

### Requirements:
- Function name: `rate_limit` (not `rateLimiter`)
- Parameters: `max_calls`, `time_window_seconds` (not `maxCalls`, `timePeriod`)
- Use f-strings instead of % formatting
- Use `logging` module instead of print statements
- Add type hints (from typing import Callable, Any, etc.)
- Add Google-style docstrings
- Pass all tests in `tests/test_rate_limiter.py`

### Run tests: