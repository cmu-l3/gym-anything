#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Autograder Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/autograder"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create directories
sudo -u ga mkdir -p test_cases submissions

# ─────────────────────────────────────────────────────────────
# 1. Pipeline Source Files (with bugs injected)
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/config.py" << 'EOF'
TIMEOUT_SEC = 0.5
TIMEOUT_CREDIT_PCT = 25
REL_TOLERANCE = 1e-4
EOF

cat > "$WORKSPACE_DIR/test_parser.py" << 'EOF'
def parse(filepath):
    with open(filepath, 'r') as f:
        content = f.read().strip()
    
    # BUG: Greedily splits on any "---", breaking test cases that contain "---" in output
    parts = content.split("---")
    
    tests = []
    for i in range(0, len(parts)-1, 2):
        tests.append({
            "input": parts[i].strip(),
            "expected": parts[i+1].strip()
        })
    return tests
EOF

cat > "$WORKSPACE_DIR/test_runner.py" << 'EOF'
import subprocess
import config

def run_test(script, input_data):
    try:
        res = subprocess.run(
            ['python3', script],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=config.TIMEOUT_SEC
        )
        if res.returncode != 0:
            return {"status": "error", "output": res.stderr.strip()}
        return {"status": "success", "output": res.stdout.strip()}
    except subprocess.TimeoutExpired:
        # BUG: Status should be "timeout" to award partial credit
        return {"status": "error", "output": ""}
EOF

cat > "$WORKSPACE_DIR/output_comparator.py" << 'EOF'
import config
import math

def compare(actual, expected):
    a_lines = actual.strip().split('\n')
    e_lines = expected.strip().split('\n')
    
    if len(a_lines) != len(e_lines):
        return False
        
    for a, e in zip(a_lines, e_lines):
        # BUG: lstrip() leaves trailing whitespace, failing exact matches
        a = a.lstrip()
        e = e.strip()
        
        if a == e:
            continue
            
        try:
            # BUG: Absolute tolerance is too strict for student answers
            if abs(float(a) - float(e)) < 1e-9:
                continue
            return False
        except ValueError:
            return False
            
    return True
EOF

cat > "$WORKSPACE_DIR/score_calculator.py" << 'EOF'
import config

def calculate(passed, total, timeouts):
    if total == 0:
        return 0
    
    score = 0
    # BUG: int(passed / total) truncates to 0 for any non-perfect score
    score += int(passed / total) * 100
    score += int(timeouts / total) * config.TIMEOUT_CREDIT_PCT
    
    return min(100, score)
EOF

cat > "$WORKSPACE_DIR/run_grader.py" << 'EOF'
import os
import json
import glob
from test_parser import parse
from test_runner import run_test
from output_comparator import compare
from score_calculator import calculate

def grade_all(submissions_dir, testcases_dir):
    results = {}
    for script in sorted(glob.glob(f"{submissions_dir}/*.py")):
        student = os.path.basename(script).split('_')[0]
        assignment = os.path.basename(script).split('_')[1].split('.')[0]
        testcase_file = f"{testcases_dir}/{assignment}.testcase"
        
        try:
            tests = parse(testcase_file)
        except Exception as e:
            results[student] = 0
            continue
            
        passed = 0
        timeouts = 0
        total = len(tests)
        
        for t in tests:
            res = run_test(script, t["input"])
            if res["status"] == "success":
                if compare(res["output"], t["expected"]):
                    passed += 1
            elif res["status"] == "timeout":
                timeouts += 1
                
        score = calculate(passed, total, timeouts)
        results[student] = score
        
    return results

if __name__ == "__main__":
    scores = grade_all("submissions", "test_cases")
    print(json.dumps(scores, indent=2))
EOF

# ─────────────────────────────────────────────────────────────
# 2. Test Cases Data
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/test_cases/factorial.testcase" << 'EOF'
0
---
1
---
3
---
6
---
5
---
120
---
6
---
720
---
10
---
3628800
EOF

cat > "$WORKSPACE_DIR/test_cases/geometry.testcase" << 'EOF'
2.0
---
12.5664
---
5.0
---
78.5398
---
10.0
---
314.1593
---
-1.0
---
Error
EOF

cat > "$WORKSPACE_DIR/test_cases/formatter.testcase" << 'EOF'
Hello
---
+--- Hello ---+
---
World
---
+--- World ---+
---

---
+---  ---+
EOF

# ─────────────────────────────────────────────────────────────
# 3. Student Submissions
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/submissions/alice_factorial.py" << 'EOF'
import sys, math
print(math.factorial(int(sys.stdin.read().strip())))
EOF

cat > "$WORKSPACE_DIR/submissions/bob_factorial.py" << 'EOF'
import sys, math
n = int(sys.stdin.read().strip())
if n > 5:
    print(0)
else:
    print(math.factorial(n))
EOF

cat > "$WORKSPACE_DIR/submissions/carol_geometry.py" << 'EOF'
import sys, math
r = float(sys.stdin.read().strip())
if r < 0:
    print("Error")
else:
    print(f"{math.pi * r * r:.7f}")
EOF

cat > "$WORKSPACE_DIR/submissions/dave_geometry.py" << 'EOF'
import sys, math
r = float(sys.stdin.read().strip())
while r < 0:
    pass
print(f"{math.pi * r * r:.4f}")
EOF

cat > "$WORKSPACE_DIR/submissions/eve_formatter.py" << 'EOF'
import sys
text = sys.stdin.read().strip()
print(f"+--- {text} ---+")
EOF

cat > "$WORKSPACE_DIR/submissions/frank_formatter.py" << 'EOF'
import sys
text = sys.stdin.read().strip()
if not text:
    print("FAIL")
else:
    print(f"+--- {text} ---+")
EOF

cat > "$WORKSPACE_DIR/submissions/grace_formatter.py" << 'EOF'
import sys
text = sys.stdin.read().strip()
print(f"+--- {text} ---+ ")
EOF

cat > "$WORKSPACE_DIR/submissions/hank_factorial.py" << 'EOF'
print("0")
EOF

# Hidden submission for anti-gaming checks
cat > "$WORKSPACE_DIR/submissions/hidden_factorial.py" << 'EOF'
import sys, math
n = int(sys.stdin.read().strip())
if n == 10:
    print(0)
else:
    print(math.factorial(n))
EOF

# Provide descriptive README
cat > "$WORKSPACE_DIR/README_BUGS.md" << 'EOF'
# Autograder Issues

Instructor Notes:
Students are complaining about grades.
- Dave says he should get partial credit for his geometry code timing out.
- Carol says her geometry code is numerically correct but failing.
- Grace says her formatter is visually perfect but failing exact match.
- Bob says he passed 3 out of 5 tests but got 0%.
- Eve says her formatter is completely correct but failing.
EOF

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code for user ga
sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" > /dev/null 2>&1 &
sleep 5
focus_vscode_window 2>/dev/null || true

# Maximize VS Code window
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="