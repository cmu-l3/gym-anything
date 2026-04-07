#!/bin/bash
echo "=== Setting up fix_security_linter task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_security_linter"
PROJECT_DIR="/home/ga/PycharmProjects/security_linter"

# 1. Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts 2>/dev/null || true

# 2. Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/linter $PROJECT_DIR/tests $PROJECT_DIR/examples"

# 3. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# 4. Create Source Files

# --- linter/__init__.py ---
touch "$PROJECT_DIR/linter/__init__.py"

# --- linter/analyzer.py (Entry point - NO BUGS) ---
cat > "$PROJECT_DIR/linter/analyzer.py" << 'EOF'
import ast
import sys
from typing import List, Dict
from .visitors import DangerousCallVisitor, SecretVisitor

class SecurityAnalyzer:
    def __init__(self):
        self.violations = []

    def scan_file(self, filepath: str) -> List[str]:
        with open(filepath, 'r') as f:
            try:
                tree = ast.parse(f.read(), filename=filepath)
            except SyntaxError as e:
                return [f"Syntax Error: {e}"]

        # Run visitors
        visitors = [
            DangerousCallVisitor(),
            SecretVisitor()
        ]

        file_violations = []
        for visitor in visitors:
            visitor.visit(tree)
            file_violations.extend(visitor.violations)
        
        return file_violations
EOF

# --- linter/visitors.py (CONTAINS 3 BUGS) ---
cat > "$PROJECT_DIR/linter/visitors.py" << 'EOF'
import ast

class DangerousCallVisitor(ast.NodeVisitor):
    def __init__(self):
        self.violations = []

    def visit_Call(self, node):
        # Check for eval() or exec()
        if isinstance(node.func, ast.Name):
            if node.func.id in ['eval', 'exec']:
                self.violations.append(f"Dangerous function call '{node.func.id}' detected on line {node.lineno}")

        # Check for subprocess with shell=True
        # BUG 3: Logic Error - Checks if the AST node *is* True, not if its value is True
        if isinstance(node.func, ast.Attribute) and node.func.attr == 'Popen':
            # rudimentary check for subprocess module usage context
            for keyword in node.keywords:
                # This logic is flawed. keyword.value is an ast.Constant (or ast.NameConstant in older python), 
                # not a boolean.
                if keyword.arg == 'shell' and keyword.value is True:
                    self.violations.append(f"subprocess called with shell=True on line {node.lineno}")
        
        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        # BUG 1: Missing Recursion - Stops traversal at function definitions
        # Should call self.generic_visit(node) to visit children
        pass


class SecretVisitor(ast.NodeVisitor):
    def __init__(self):
        self.violations = []

    def visit_Assign(self, node):
        # Check for hardcoded secrets
        for target in node.targets:
            if isinstance(target, ast.Name):
                target_name = target.id.lower()
                # BUG 2: False Positive - Flags variable names regardless of value source
                # Should check if node.value is a string literal (ast.Constant/ast.Str)
                if 'password' in target_name or 'secret' in target_name or 'key' in target_name:
                    self.violations.append(f"Possible hardcoded secret assigned to '{target.id}' on line {node.lineno}")
        
        self.generic_visit(node)
EOF

# 5. Create Test Files

# --- tests/__init__.py ---
touch "$PROJECT_DIR/tests/__init__.py"

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import ast
from linter.visitors import DangerousCallVisitor, SecretVisitor

@pytest.fixture
def dangerous_visitor():
    return DangerousCallVisitor()

@pytest.fixture
def secret_visitor():
    return SecretVisitor()

@pytest.fixture
def analyze_code():
    def _analyze(visitor, code):
        tree = ast.parse(code)
        visitor.visit(tree)
        return visitor.violations
    return _analyze
EOF

# --- tests/test_linter.py ---
cat > "$PROJECT_DIR/tests/test_linter.py" << 'EOF'
import pytest

# --- Test DangerousCallVisitor (eval/exec) ---

def test_detect_eval_top_level(dangerous_visitor, analyze_code):
    code = "eval('2 + 2')"
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 1
    assert "eval" in violations[0]

def test_detect_nested_eval(dangerous_visitor, analyze_code):
    # This fails due to Bug 1 (missing recursion in visit_FunctionDef)
    code = """
def run_code():
    eval('import os')
"""
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 1
    assert "eval" in violations[0]

def test_detect_class_method_eval(dangerous_visitor, analyze_code):
    # Also fails due to Bug 1
    code = """
class Executor:
    def execute(self):
        exec('print(1)')
"""
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 1
    assert "exec" in violations[0]

def test_safe_function_def(dangerous_visitor, analyze_code):
    code = "def eval_something(): pass"
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 0


# --- Test DangerousCallVisitor (subprocess shell=True) ---

def test_subprocess_shell_false(dangerous_visitor, analyze_code):
    code = "subprocess.Popen(['ls'], shell=False)"
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 0

def test_subprocess_no_shell(dangerous_visitor, analyze_code):
    code = "subprocess.Popen(['ls'])"
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 0

def test_subprocess_shell_true(dangerous_visitor, analyze_code):
    # This fails due to Bug 3 (wrong AST node check)
    code = "subprocess.Popen('ls', shell=True)"
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 1
    assert "shell=True" in violations[0]

def test_subprocess_shell_true_variable(dangerous_visitor, analyze_code):
    # We only flag literal True, so this should pass (naive linter)
    code = """
use_shell = True
subprocess.Popen('ls', shell=use_shell)
"""
    violations = analyze_code(dangerous_visitor, code)
    assert len(violations) == 0


# --- Test SecretVisitor ---

def test_detect_hardcoded_password(secret_visitor, analyze_code):
    code = "db_password = 'super_secret_value'"
    violations = analyze_code(secret_visitor, code)
    assert len(violations) == 1
    assert "hardcoded secret" in violations[0]

def test_safe_password_assignment(secret_visitor, analyze_code):
    # This fails due to Bug 2 (False positive on non-literals)
    code = "user_password = os.getenv('DB_PASS')"
    violations = analyze_code(secret_visitor, code)
    assert len(violations) == 0

def test_safe_password_function_call(secret_visitor, analyze_code):
    # Fails due to Bug 2
    code = "api_key = get_key_from_vault()"
    violations = analyze_code(secret_visitor, code)
    assert len(violations) == 0

def test_detect_hardcoded_key(secret_visitor, analyze_code):
    code = "aws_key = 'AKIA...'"
    violations = analyze_code(secret_visitor, code)
    assert len(violations) == 1

def test_ignore_non_secret_assignment(secret_visitor, analyze_code):
    code = "username = 'admin'"
    violations = analyze_code(secret_visitor, code)
    assert len(violations) == 0
EOF

# 6. Record timestamps
date +%s > /tmp/${TASK_NAME}_start_ts

# 7. Open Project in PyCharm
echo "Opening PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "security_linter"

# 8. Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="