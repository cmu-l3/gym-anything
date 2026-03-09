#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Code Archaeology Task ==="

WORKSPACE_DIR="/home/ga/workspace/email_validator"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

cd "$WORKSPACE_DIR"

# Initialize Git repository
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git config user.name "Dev Team"
sudo -u ga git config user.email "dev@company.com"

# Create initial version of validators.py (CORRECT implementation)
cat > "$WORKSPACE_DIR/src/validators.py" << 'EOF'
"""Email validation utilities"""
import re

def validate_email_format(email):
    """Basic email format validation"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))

def validate_email_domain(email):
    """Validate email domain exists and is properly formatted"""
    if not email or '@' not in email:
        return False
    
    domain = email.split('@')[1].strip()
    
    # Check domain has at least one dot
    if '.' not in domain:
        return False
    
    # Check domain parts are non-empty
    parts = domain.split('.')
    if any(len(part) == 0 for part in parts):
        return False
    
    return True

def validate_email(email):
    """Complete email validation"""
    return validate_email_format(email) and validate_email_domain(email)
EOF

cat > "$WORKSPACE_DIR/tests/test_validators.py" << 'EOF'
"""Test email validators"""
import sys
sys.path.insert(0, '../src')
from validators import validate_email

def test_basic():
    assert validate_email("user@example.com")
    assert not validate_email("invalid")
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Email Validator

Email validation utilities for production use.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Commit 1: Initial implementation
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial email validator implementation" --date="2023-01-15 10:00:00"

# Commit 2: Add more tests
echo "" >> "$WORKSPACE_DIR/tests/test_validators.py"
echo "def test_edge_cases():" >> "$WORKSPACE_DIR/tests/test_validators.py"
echo "    assert not validate_email('')" >> "$WORKSPACE_DIR/tests/test_validators.py"
sudo -u ga git add tests/test_validators.py
sudo -u ga git config user.name "Alice Chen"
sudo -u ga git commit -m "Add edge case tests" --date="2023-02-01 14:30:00"

# Commit 3: Update README
echo "" >> "$WORKSPACE_DIR/README.md"
echo "## Usage" >> "$WORKSPACE_DIR/README.md"
echo "See tests for examples." >> "$WORKSPACE_DIR/README.md"
sudo -u ga git add README.md
sudo -u ga git config user.name "Bob Smith"
sudo -u ga git commit -m "Update documentation" --date="2023-02-10 09:15:00"

# Commit 4: Add type hints
sed -i 's/def validate_email_format(email):/def validate_email_format(email: str) -> bool:/' "$WORKSPACE_DIR/src/validators.py"
sed -i 's/def validate_email_domain(email):/def validate_email_domain(email: str) -> bool:/' "$WORKSPACE_DIR/src/validators.py"
sed -i 's/def validate_email(email):/def validate_email(email: str) -> bool:/' "$WORKSPACE_DIR/src/validators.py"
sudo -u ga git add src/validators.py
sudo -u ga git config user.name "Alice Chen"
sudo -u ga git commit -m "Add type hints for better IDE support" --date="2023-03-05 11:20:00"

# Commit 5: THE PROBLEMATIC COMMIT - Add .upper() that breaks international domains
# This is the commit we want the agent to find
sed -i 's/domain = email.split.*$/domain = email.split('\''@'\'')[1].strip().upper()/' "$WORKSPACE_DIR/src/validators.py"
sudo -u ga git add src/validators.py
sudo -u ga git config user.name "Charlie Davis"
sudo -u ga git commit -m "Fix case sensitivity in domain validation" --date="2023-04-12 16:45:00"

# Store the problematic commit hash for verification
PROBLEM_COMMIT=$(cd "$WORKSPACE_DIR" && sudo -u ga git log -1 --format="%H")
echo "$PROBLEM_COMMIT" > /tmp/expected_commit_hash.txt
echo "Problematic commit hash: $PROBLEM_COMMIT"

# Commit 6: Unrelated change
echo "" >> "$WORKSPACE_DIR/README.md"
echo "## License" >> "$WORKSPACE_DIR/README.md"
echo "MIT" >> "$WORKSPACE_DIR/README.md"
sudo -u ga git add README.md
sudo -u ga git config user.name "Bob Smith"
sudo -u ga git commit -m "Add license information" --date="2023-04-20 10:00:00"

# Commit 7: Add more validation
cat >> "$WORKSPACE_DIR/src/validators.py" << 'EOF'

def validate_email_length(email: str) -> bool:
    """Check email length constraints"""
    return len(email) <= 254
EOF
sudo -u ga git add src/validators.py
sudo -u ga git config user.name "Alice Chen"
sudo -u ga git commit -m "Add email length validation" --date="2023-05-03 13:30:00"

# Commit 8: Update tests
echo "def test_length():" >> "$WORKSPACE_DIR/tests/test_validators.py"
echo "    assert validate_email_length('a@b.co')" >> "$WORKSPACE_DIR/tests/test_validators.py"
sudo -u ga git add tests/test_validators.py
sudo -u ga git config user.name "Charlie Davis"
sudo -u ga git commit -m "Add length validation tests" --date="2023-05-10 15:00:00"

# Final state: Create a file with the current function for reference
cat > "$WORKSPACE_DIR/.vscode/settings.json" << 'EOF'
{
  "git.blame.enabled": true,
  "gitlens.codeLens.enabled": true
}
EOF
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode with email validator project..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/src/validators.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Try to position cursor near the problematic function (around line 45)
sleep 1
su - ga -c "DISPLAY=:1 xdotool key ctrl+g" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type '15'" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" || true

echo "=== Code Archaeology Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. You are viewing src/validators.py with the validate_email_domain() function"
echo "  2. Use Git Blame (right-click → 'Git: View Line History' or Ctrl+Shift+P → 'Git: Toggle File Blame')"
echo "  3. Identify the commit that added .strip().upper() to the domain variable"
echo "  4. Use Timeline view or file history to investigate the change"
echo "  5. Create FINDINGS.md in the project root documenting:"
echo "     - The commit hash"
echo "     - The author"
echo "     - What changed"
echo "     - Why it's problematic"
echo ""
echo "Project location: $WORKSPACE_DIR"
echo "Commits in history: $(cd $WORKSPACE_DIR && sudo -u ga git log --oneline | wc -l)"