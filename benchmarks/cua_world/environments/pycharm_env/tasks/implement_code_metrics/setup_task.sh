#!/bin/bash
set -e
echo "=== Setting up implement_code_metrics task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/code_metrics"

# Clean previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/code_metrics_result.json /tmp/task_start_time

# Create directories
su - ga -c "mkdir -p $PROJECT_DIR/metrics $PROJECT_DIR/tests $PROJECT_DIR/sample_code"

# --- Create Sample Code (Data) ---

# 1. simple_utils.py (Low complexity)
cat > "$PROJECT_DIR/sample_code/simple_utils.py" << 'PYEOF'
def clamp(val, min_val, max_val):
    """Restrict value to range."""
    return max(min(val, max_val), min_val)

def slugify(text):
    """Simple slugify."""
    return text.lower().replace(" ", "-")

def flatten_list(nested):
    """Flatten a list of lists."""
    result = []
    for sublist in nested:
        for item in sublist:
            result.append(item)
    return result

def retry_decorator(func):
    """Dummy decorator."""
    def wrapper():
        try:
            return func()
        except Exception:
            return None
    return wrapper
PYEOF

# 2. data_processor.py (Medium complexity)
cat > "$PROJECT_DIR/sample_code/data_processor.py" << 'PYEOF'
class DataProcessor:
    def __init__(self, data):
        self.data = data

    def process(self):
        results = []
        for row in self.data:
            if not row:
                continue
            
            if row.get("status") == "active":
                val = row.get("value", 0)
                if val > 100:
                    results.append(val * 0.9)
                elif val > 50:
                    results.append(val * 0.95)
                else:
                    results.append(val)
            elif row.get("status") == "pending":
                pass
            else:
                break
        return results
PYEOF

# 3. legacy_handler.py (High complexity)
cat > "$PROJECT_DIR/sample_code/legacy_handler.py" << 'PYEOF'
def handle_request(req):
    if req.auth:
        if req.user.is_admin:
            if req.method == "POST":
                if req.body:
                    save(req.body)
                    return 201
                else:
                    return 400
            elif req.method == "GET":
                return 200
            else:
                return 405
        else:
            if req.method == "GET":
                return 200
            else:
                return 403
    else:
        return 401

def complex_calc(x, y, z):
    # Boolean logic complexity
    if (x > 0 and y > 0) or (z < 0 and x < z):
        return True
    return False
PYEOF


# --- Create Implementation Stubs ---

# metrics/__init__.py
touch "$PROJECT_DIR/metrics/__init__.py"

# metrics/loc.py
cat > "$PROJECT_DIR/metrics/loc.py" << 'PYEOF'
def count_lines(source: str) -> dict:
    """
    Analyze lines of code in source string.
    
    Returns dictionary with keys:
        - "total": Total lines (including blank)
        - "code": Lines containing executable code
        - "comment": Lines containing only comments
        - "blank": Empty or whitespace-only lines
        - "docstring": Lines inside triple-quoted docstrings
        
    Note: A line with code and an inline comment counts as 'code'.
    """
    raise NotImplementedError("TODO: implement this function")
PYEOF

# metrics/complexity.py
cat > "$PROJECT_DIR/metrics/complexity.py" << 'PYEOF'
import ast

def cyclomatic_complexity(source: str) -> list:
    """
    Compute McCabe's Cyclomatic Complexity for each function/method.
    
    Returns list of dicts sorted by line number:
    [
        {
            "name": function_name,
            "lineno": start_line,
            "complexity": int_score,
            "type": "function" or "method"
        },
        ...
    ]
    
    Scoring rules:
    - Base complexity = 1
    - +1 for each: if, elif, for, while, except, assert, with, async for, async with
    - +1 for each boolean operator (and, or)
    - +1 for each ternary operator (if expression)
    - +1 for comprehensions with 'if' filters
    """
    raise NotImplementedError("TODO: implement this function")
PYEOF

# metrics/halstead.py
cat > "$PROJECT_DIR/metrics/halstead.py" << 'PYEOF'
import ast
import math

def halstead_metrics(source: str) -> dict:
    """
    Compute Halstead Software Science Metrics.
    
    Returns dict:
    {
        "n1": int,       # Distinct operators
        "n2": int,       # Distinct operands
        "N1": int,       # Total operators
        "N2": int,       # Total operands
        "vocabulary": int,
        "length": int,
        "volume": float,
        "difficulty": float,
        "effort": float,
        "time": float,
        "bugs": float
    }
    
    Definitions:
    - Operators: keywords (if, return, etc), arithmetic/logic ops, decorators, etc.
    - Operands: variable names, literals (numbers, strings)
    """
    raise NotImplementedError("TODO: implement this function")
PYEOF

# metrics/analyzer.py
cat > "$PROJECT_DIR/metrics/analyzer.py" << 'PYEOF'
import os
from .loc import count_lines
from .complexity import cyclomatic_complexity
from .halstead import halstead_metrics

def analyze_file(filepath: str) -> dict:
    """
    Read file and return full analysis:
    {
        "filepath": str,
        "loc": dict,
        "complexity": list,
        "halstead": dict
    }
    """
    raise NotImplementedError("TODO: implement this function")

def analyze_directory(dirpath: str) -> dict:
    """
    Analyze all .py files in directory (non-recursive).
    
    Returns:
    {
        "directory": str,
        "files": list of analyze_file results,
        "summary": {
            "total_files": int,
            "total_loc": int (sum of code lines),
            "avg_complexity": float (average across all functions in all files),
            "max_complexity": { ... complexity dict of highest scoring function ... }
        }
    }
    """
    raise NotImplementedError("TODO: implement this function")
PYEOF


# --- Create Tests ---

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import os

@pytest.fixture
def sample_code_dir():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'sample_code'))

@pytest.fixture
def simple_utils_source(sample_code_dir):
    with open(os.path.join(sample_code_dir, 'simple_utils.py'), 'r') as f:
        return f.read()

@pytest.fixture
def legacy_handler_source(sample_code_dir):
    with open(os.path.join(sample_code_dir, 'legacy_handler.py'), 'r') as f:
        return f.read()
PYEOF

# tests/test_loc.py
cat > "$PROJECT_DIR/tests/test_loc.py" << 'PYEOF'
from metrics.loc import count_lines

def test_loc_simple_function():
    code = """
def hello():
    print("world")
    return True
"""
    result = count_lines(code.strip())
    assert result["total"] == 3
    assert result["code"] == 3

def test_loc_comments_and_blanks():
    code = """
# This is a comment

def foo():
    # Inner comment
    pass

    
"""
    result = count_lines(code.strip())
    # line 1: comment
    # line 2: blank
    # line 3: code
    # line 4: code (inline comment counts as code if mixed, but here it is indented comment line)
    # line 5: code
    # line 6: blank
    # Analysis:
    # 1: # This is a comment (comment)
    # 2: (blank)
    # 3: def foo(): (code)
    # 4:     # Inner comment (comment)
    # 5:     pass (code)
    # 6: (blank)
    
    assert result["total"] == 6
    assert result["code"] == 2
    assert result["comment"] == 2
    assert result["blank"] == 2

def test_loc_docstrings():
    code = '"""Module docstring."""\n\ndef func():\n    """Func docstring."""\n    pass'
    result = count_lines(code)
    # 1: """Module docstring.""" (docstring)
    # 2: (blank) -> actually blank
    # 3: def func(): (code)
    # 4:     """Func docstring.""" (docstring)
    # 5:     pass (code)
    
    assert result["docstring"] >= 2
    assert result["code"] >= 2
PYEOF

# tests/test_complexity.py
cat > "$PROJECT_DIR/tests/test_complexity.py" << 'PYEOF'
from metrics.complexity import cyclomatic_complexity

def test_complexity_linear():
    code = "def linear():\n    return 1"
    res = cyclomatic_complexity(code)
    assert len(res) == 1
    assert res[0]["complexity"] == 1

def test_complexity_branches():
    code = """
def branching(x):
    if x > 0:
        return 1
    elif x < 0:
        return -1
    else:
        return 0
"""
    res = cyclomatic_complexity(code)
    # Base 1 + if(1) + elif(1) = 3. Else does not add complexity in McCabe.
    assert res[0]["complexity"] == 3

def test_complexity_boolean_ops():
    code = """
def logic(a, b):
    if a and b:
        return True
"""
    res = cyclomatic_complexity(code)
    # Base 1 + if(1) + and(1) = 3
    assert res[0]["complexity"] == 3

def test_complexity_sample_legacy(legacy_handler_source):
    res = cyclomatic_complexity(legacy_handler_source)
    # Find handle_request function
    handler = next(r for r in res if r["name"] == "handle_request")
    # It has significant nesting.
    # Count:
    # Base: 1
    # if req.auth: +1
    #   if req.user.is_admin: +1
    #     if req.method == "POST": +1
    #       if req.body: +1
    #       else (0)
    #     elif req.method == "GET": +1
    #     else (0)
    #   else: (0)
    #     if req.method == "GET": +1
    #     else (0)
    # else (0)
    # Total = 1 + 6 = 7
    assert handler["complexity"] == 7
    
    calc = next(r for r in res if r["name"] == "complex_calc")
    # Base 1
    # if (x>0 and y>0) or (z<0 and x<z):
    # if +1
    # and +1
    # or +1
    # and +1
    # Total = 1 + 4 = 5
    assert calc["complexity"] == 5
PYEOF

# tests/test_halstead.py
cat > "$PROJECT_DIR/tests/test_halstead.py" << 'PYEOF'
from metrics.halstead import halstead_metrics

def test_halstead_simple():
    code = "x = a + b"
    # Operands: x, a, b (n2=3, N2=3)
    # Operators: =, + (n1=2, N1=2)
    # Vocabulary: 5
    # Length: 5
    m = halstead_metrics(code)
    assert m["n1"] > 0
    assert m["n2"] > 0
    assert m["vocabulary"] == m["n1"] + m["n2"]
    assert m["length"] == m["N1"] + m["N2"]

def test_halstead_empty():
    m = halstead_metrics("")
    assert m["vocabulary"] == 0
    assert m["volume"] == 0
PYEOF

# tests/test_analyzer.py
cat > "$PROJECT_DIR/tests/test_analyzer.py" << 'PYEOF'
import os
from metrics.analyzer import analyze_file, analyze_directory

def test_analyze_file(tmp_path):
    f = tmp_path / "test.py"
    f.write_text("def foo():\n    pass")
    res = analyze_file(str(f))
    assert res["filepath"] == str(f)
    assert "loc" in res
    assert "complexity" in res
    assert "halstead" in res

def test_analyze_directory(sample_code_dir):
    res = analyze_directory(sample_code_dir)
    assert res["summary"]["total_files"] >= 3
    assert res["summary"]["total_loc"] > 0
    assert res["summary"]["avg_complexity"] > 0
PYEOF

# requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'TXT'
pytest>=7.0
pytest-cov>=4.0
TXT

# Initialize timestamp for anti-gaming
echo "$(date +%s)" > /tmp/task_start_time

# Launch PyCharm
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /dev/null 2>&1 &"

# Wait for it
source /workspace/scripts/task_utils.sh
wait_for_pycharm 60
focus_pycharm_window
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="