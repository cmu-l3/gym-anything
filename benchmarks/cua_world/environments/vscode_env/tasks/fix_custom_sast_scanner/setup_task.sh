#!/bin/bash
set -e

echo "=== Setting up Custom SAST Scanner Task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/sast_scanner"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/target_codebase"

# Install pytest just in case
pip3 install pytest > /dev/null 2>&1 || true

# ──────────────────────────────────────────────────────────
# 1. scanner.py (CLI Entry Point)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/scanner.py" << 'EOF'
import ast
import os
import json
import sys
from visitor import SASTVisitor

def scan_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        source = f.read()
    
    try:
        tree = ast.parse(source, filename=filepath)
    except Exception as e:
        return [{"type": "ParseError", "line": 0, "message": str(e)}]

    visitor = SASTVisitor()
    visitor.visit(tree)
    return visitor.findings

def main():
    if len(sys.argv) < 2:
        print("Usage: python scanner.py <directory> [-o output.json]")
        sys.exit(1)
        
    target_dir = sys.argv[1]
    all_findings = {}

    for root, _, files in os.walk(target_dir):
        for file in files:
            if file.endswith('.py'):
                filepath = os.path.join(root, file)
                findings = scan_file(filepath)
                if findings:
                    all_findings[filepath] = findings

    if "-o" in sys.argv:
        out_idx = sys.argv.index("-o") + 1
        with open(sys.argv[out_idx], 'w') as f:
            json.dump(all_findings, f, indent=2)
    else:
        print(json.dumps(all_findings, indent=2))

if __name__ == "__main__":
    main()
EOF

# ──────────────────────────────────────────────────────────
# 2. visitor.py (Buggy AST Visitor)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/visitor.py" << 'EOF'
import ast

class StrictNodeVisitor(ast.NodeVisitor):
    """Base class that rejects unhandled modern syntax."""
    def generic_visit(self, node):
        # BUG 5: Match statements cause a crash
        if type(node).__name__ == 'Match':
            raise NotImplementedError("Modern Python syntax (Match/Case) is not supported yet.")
        super().generic_visit(node)

class SASTVisitor(StrictNodeVisitor):
    def __init__(self):
        self.findings = []
        # BUG 4: Flat dictionary used for variable scope, causing leakage across functions
        self.local_vars = {} 
        self.banned_funcs = {'md5', 'sha1', 'eval', 'exec'}

    def visit_Call(self, node):
        # BUG 2: Detects banned functions directly by name, ignores import aliases
        if isinstance(node.func, ast.Name):
            if node.func.id in self.banned_funcs:
                self.findings.append({"type": "BannedFunction", "line": node.lineno})
        elif isinstance(node.func, ast.Attribute):
            if node.func.attr in self.banned_funcs:
                self.findings.append({"type": "BannedFunction", "line": node.lineno})

        # Detect SQL injection via cursor.execute
        if isinstance(node.func, ast.Attribute) and node.func.attr == 'execute':
            if node.args:
                arg = node.args[0]
                # BUG 1: Only checks BinOp (+ concatenation), misses ast.JoinedStr (f-strings)
                if isinstance(arg, ast.BinOp):
                    self.findings.append({"type": "SQLInjection", "line": node.lineno})
                # Check for tainted variables passed to execute
                elif isinstance(arg, ast.Name) and self.local_vars.get(arg.id) == 'tainted':
                    self.findings.append({"type": "SQLInjection", "line": node.lineno})

        self.generic_visit(node)

    def visit_Assign(self, node):
        # Track taint: if assigned from user_input(), mark as tainted
        is_tainted = False
        if isinstance(node.value, ast.Call) and getattr(node.value.func, 'id', '') == 'get_user_input':
            is_tainted = True

        for target in node.targets:
            if isinstance(target, ast.Name):
                if is_tainted:
                    self.local_vars[target.id] = 'tainted'
                else:
                    self.local_vars[target.id] = 'safe'

                # BUG 3: Flags any variable with 'secret' in its name, even if safely loaded from env vars
                if 'secret' in target.id.lower():
                    # Should verify that the assigned value is a hardcoded string literal (ast.Constant)
                    self.findings.append({"type": "HardcodedSecret", "line": node.lineno})

        self.generic_visit(node)

    # Missing visit_FunctionDef to manage scope_stack
    # Missing visit_Import and visit_ImportFrom to track aliases
EOF

# ──────────────────────────────────────────────────────────
# 3. tests/test_visitor.py (The Test Suite)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_visitor.py" << 'EOF'
import ast
import pytest
from visitor import SASTVisitor

def scan_code(source_code):
    tree = ast.parse(source_code)
    visitor = SASTVisitor()
    visitor.visit(tree)
    return visitor.findings

def test_fstring_sqli():
    code = """
def query(cursor, uid):
    # This should be flagged as SQLInjection
    cursor.execute(f"SELECT * FROM users WHERE id={uid}")
"""
    findings = scan_code(code)
    assert any(f['type'] == 'SQLInjection' for f in findings), "Failed to detect f-string SQLi"

def test_aliased_imports():
    code = """
from hashlib import md5 as insecure_hash
def do_hash(data):
    # This should be flagged as BannedFunction
    return insecure_hash(data)
"""
    findings = scan_code(code)
    assert any(f['type'] == 'BannedFunction' for f in findings), "Failed to detect aliased banned function"

def test_safe_secret_assignment():
    code = """
import os
def get_creds():
    # This should NOT be flagged (safe environment variable retrieval)
    aws_secret_key = os.getenv("AWS_SECRET")
    
    # This SHOULD be flagged (hardcoded literal string)
    my_secret = "AKIAIOSFODNN7EXAMPLE"
"""
    findings = scan_code(code)
    hardcoded = [f for f in findings if f['type'] == 'HardcodedSecret']
    assert len(hardcoded) == 1, f"Expected exactly 1 HardcodedSecret, got {len(hardcoded)}"
    assert hardcoded[0]['line'] == 8, "Flagged the wrong line for HardcodedSecret"

def test_variable_scope_isolation():
    code = """
def read_input():
    data = get_user_input() # 'data' is tainted

def do_query(cursor):
    data = "SELECT * FROM users" # 'data' is safe literal here
    cursor.execute(data) # Should NOT be flagged as SQLInjection
"""
    findings = scan_code(code)
    sqli = [f for f in findings if f['type'] == 'SQLInjection']
    assert len(sqli) == 0, "Variable scope leaked between functions! False positive SQLi detected."

def test_python_310_match_case():
    code = """
def handle_status(status):
    match status:
        case 200: return "OK"
        case 404: return "Not Found"
"""
    try:
        scan_code(code)
    except NotImplementedError:
        pytest.fail("Visitor crashed on Python 3.10 match/case statement")
EOF

# ──────────────────────────────────────────────────────────
# 4. Create Hidden Evaluation Codebase (for Anti-Gaming)
# ──────────────────────────────────────────────────────────
HIDDEN_DIR="/var/lib/app/hidden_eval_codebase"
sudo mkdir -p "$HIDDEN_DIR"

cat > "$HIDDEN_DIR/eval_sqli.py" << 'EOF'
def update_profile(cursor, bio):
    cursor.execute("UPDATE users SET bio='" + bio + "' WHERE id=1")
    cursor.execute(f"UPDATE users SET age={age} WHERE id=1")
EOF

cat > "$HIDDEN_DIR/eval_alias.py" << 'EOF'
import hashlib as hl
def calc():
    hl.sha1(b"test")
EOF

cat > "$HIDDEN_DIR/eval_secret.py" << 'EOF'
def load_keys():
    db_secret = retrieve_from_vault()
    api_secret = "super_secret_token_123"
EOF

cat > "$HIDDEN_DIR/eval_scope.py" << 'EOF'
def a():
    query = get_user_input()
def b(cursor):
    query = "SELECT 1"
    cursor.execute(query)
EOF

cat > "$HIDDEN_DIR/eval_match.py" << 'EOF'
def route(path):
    match path:
        case "/": pass
EOF

sudo chown -R root:root "$HIDDEN_DIR"
sudo chmod -R 755 "$HIDDEN_DIR"

# ──────────────────────────────────────────────────────────
# Set proper ownership for workspace
# ──────────────────────────────────────────────────────────
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VSCode is running and focused
echo "Starting VS Code..."
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Visual Studio Code"; then
        echo "VS Code window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Open the buggy file
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/visitor.py"
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="