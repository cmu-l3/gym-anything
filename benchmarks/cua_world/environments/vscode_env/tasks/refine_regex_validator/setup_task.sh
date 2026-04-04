#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Refine Regex Validator Task ==="

WORKSPACE_DIR="/home/ga/workspace/email_validation"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create validator.py with broken regex pattern
cat > "$WORKSPACE_DIR/validator.py" << 'EOF'
import re

# TODO: Fix this regex pattern to handle all test cases
# Current pattern is too restrictive and misses valid cases
EMAIL_PATTERN = r'^[a-z0-9]+@[a-z]+\.[a-z]+$'

def validate_email(email):
    """Validate email address against pattern"""
    return bool(re.match(EMAIL_PATTERN, email))
EOF

# Create test_cases.txt with test cases
cat > "$WORKSPACE_DIR/test_cases.txt" << 'EOF'
# Email Validation Test Cases
# Format: email | expected_result (VALID or INVALID)

# Should be VALID
user@example.com | VALID
john.doe@company.co.uk | VALID
alice+spam@test-domain.org | VALID
user123@subdomain.example.com | VALID
first_last@example.io | VALID
admin@test.museum | VALID
user@123.456.789.012 | VALID
a@b.co | VALID

# Should be INVALID
@example.com | INVALID
user@.com | INVALID
user name@example.com | INVALID
user@example | INVALID
EOF

# Create README.md with detailed instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Email Validation Task

Fix the regex in `validator.py` to correctly validate all test cases in `test_cases.txt`.

## Current Issues
- Fails on emails with dots in username (john.doe@example.com)
- Fails on plus addressing (user+tag@example.com)
- Fails on hyphens in domains
- Fails on multi-part TLDs (.co.uk)
- Fails on underscores, numbers in various positions
- May incorrectly accept some invalid patterns

## Goal
All 12 test cases should pass when you run your test script.

## Steps
1. Create a test runner script (test_validator.py or similar)
2. Run tests to identify failures
3. Modify EMAIL_PATTERN in validator.py
4. Re-run tests
5. Repeat steps 3-4 until all tests pass
6. Add comments documenting the regex pattern
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode with email_validation workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/validator.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Refine Regex Validator Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review validator.py (broken regex) and test_cases.txt (12 test cases)"
echo "  2. Create a test runner script (e.g., test_validator.py)"
echo "  3. Run tests to see which cases fail"
echo "  4. Iteratively modify EMAIL_PATTERN in validator.py"
echo "  5. Re-run tests until all 12 pass"
echo "  6. Add documentation comments to the regex pattern"
echo ""
echo "Workspace: $WORKSPACE_DIR"