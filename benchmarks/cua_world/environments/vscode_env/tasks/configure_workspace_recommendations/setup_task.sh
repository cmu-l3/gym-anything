#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Workspace Recommendations Task ==="

WORKSPACE_DIR="/home/ga/workspace/team_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{src,tests}

# Create Python files for a realistic project
cat > "$WORKSPACE_DIR/src/main.py" << 'EOF'
"""Main application module"""

def greet(name: str) -> str:
    """Greet someone by name"""
    return f"Hello, {name}!"

def calculate_factorial(n: int) -> int:
    """Calculate factorial recursively"""
    if n <= 1:
        return 1
    return n * calculate_factorial(n - 1)

if __name__ == "__main__":
    print(greet("World"))
    print(f"Factorial of 5 is {calculate_factorial(5)}")
EOF

cat > "$WORKSPACE_DIR/src/utils.py" << 'EOF'
"""Utility functions"""

def format_name(first: str, last: str) -> str:
    """Format a full name"""
    return f"{first} {last}"

def validate_email(email: str) -> bool:
    """Basic email validation"""
    return "@" in email and "." in email.split("@")[1]
EOF

# Create JavaScript files
cat > "$WORKSPACE_DIR/src/app.js" << 'EOF'
/**
 * Main application entry point
 */

function greet(name) {
  return `Hello, ${name}!`;
}

function calculateFactorial(n) {
  if (n <= 1) return 1;
  return n * calculateFactorial(n - 1);
}

console.log(greet('World'));
console.log(`Factorial of 5 is ${calculateFactorial(5)}`);
EOF

cat > "$WORKSPACE_DIR/src/utils.js" << 'EOF'
/**
 * Utility functions
 */

function formatName(first, last) {
  return `${first} ${last}`;
}

function validateEmail(email) {
  return email.includes('@') && email.split('@')[1].includes('.');
}

module.exports = { formatName, validateEmail };
EOF

# Create test files
cat > "$WORKSPACE_DIR/tests/test_main.py" << 'EOF'
"""Test cases for main module"""
import sys
sys.path.insert(0, '../src')
from main import greet, calculate_factorial

def test_greet():
    assert greet("Alice") == "Hello, Alice!"

def test_factorial():
    assert calculate_factorial(5) == 120
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "team-project",
  "version": "1.0.0",
  "description": "Full-stack team project with Python backend and JavaScript frontend",
  "main": "src/app.js",
  "scripts": {
    "start": "node src/app.js",
    "test": "jest"
  },
  "keywords": ["python", "javascript", "fullstack"],
  "author": "Team",
  "license": "MIT"
}
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
black==23.3.0
pylint==2.17.4
pytest==7.3.1
requests==2.31.0
flask==2.3.2
EOF

# Create README with clear instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Team Project

A full-stack project with Python backend and JavaScript frontend.

## Development Setup

**IMPORTANT**: New team members need to install the correct VSCode extensions!

Currently, developers are using inconsistent tooling:
- Some use Prettier, others use different formatters
- Python linting is inconsistent (Pylint vs Flake8 vs nothing)
- ESLint is not configured for everyone

### TODO: Configure Workspace Extension Recommendations

Please create `.vscode/extensions.json` to recommend essential extensions:

**Required extensions:**
- Python language support
- Python formatter (Black)
- Python linter (Pylint)
- JavaScript/TypeScript linter (ESLint)
- Code formatter for JS/JSON (Prettier)

Optional but helpful:
- Git integration enhancements (GitLens)
- IntelliCode

This will ensure all team members receive a prompt to install these extensions
when they open the project in VSCode.

## Project Structure
