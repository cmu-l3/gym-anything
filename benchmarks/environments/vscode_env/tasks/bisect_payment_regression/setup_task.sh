#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Git Bisect Payment Regression Task ==="

WORKSPACE_DIR="/home/ga/workspace"
REPO_DIR="$WORKSPACE_DIR/payment-service"

# Clean up any existing workspace
sudo -u ga rm -rf "$REPO_DIR"
sudo -u ga mkdir -p "$REPO_DIR"

cd "$REPO_DIR"

# Initialize Git repo as ga user
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

echo "Creating initial payment validator..."

# Create initial working payment validator
cat > "$REPO_DIR/payment_validator.py" << 'EOF'
import re

def validate_card(card_number):
    """Validate credit card number"""
    # Remove spaces and dashes
    card = card_number.replace(' ', '').replace('-', '')
    
    # Check if it's digits only
    if not card.isdigit():
        return False
    
    # Visa: starts with 4, length 13 or 16
    if card[0] == '4' and len(card) in [13, 16]:
        return luhn_check(card)
    
    # Mastercard: starts with 51-55 or 2221-2720, length 16
    if (card[:2] in ['51','52','53','54','55'] or 
        (2221 <= int(card[:4]) <= 2720)) and len(card) == 16:
        return luhn_check(card)
    
    return False

def luhn_check(card_number):
    """Implement Luhn algorithm"""
    def digits_of(n):
        return [int(d) for d in str(n)]
    
    digits = digits_of(card_number)
    odd_digits = digits[-1::-2]
    even_digits = digits[-2::-2]
    checksum = sum(odd_digits)
    for d in even_digits:
        checksum += sum(digits_of(d*2))
    return checksum % 10 == 0

if __name__ == "__main__":
    # Test cases
    print("Testing Visa:", validate_card("4532015112830366"))
    print("Testing Mastercard:", validate_card("5425233430109903"))
EOF

# Create test script
cat > "$REPO_DIR/test_validator.py" << 'EOF'
import payment_validator

def test_visa_validation():
    """Test that valid Visa cards are accepted"""
    valid_visa = "4532015112830366"  # Known valid Visa test card
    result = payment_validator.validate_card(valid_visa)
    assert result == True, f"Valid Visa card was rejected: {valid_visa}"
    print("✓ Visa validation passed")

if __name__ == "__main__":
    test_visa_validation()
EOF

chmod +x "$REPO_DIR/test_validator.py"

# Create run script for bisect
cat > "$REPO_DIR/run_test.sh" << 'EOF'
#!/bin/bash
python3 test_validator.py > /dev/null 2>&1
exit $?
EOF

chmod +x "$REPO_DIR/run_test.sh"

# Create README
cat > "$REPO_DIR/README.md" << 'EOF'
# Payment Validator Service

Credit card validation module for payment processing.

## Testing
Run `./run_test.sh` to validate the implementation.
EOF

sudo chown -R ga:ga "$REPO_DIR"

# Commit 1: Initial implementation
cd "$REPO_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial payment validator implementation"

# Commit 2: Tag as v2.3.0-release (known good)
sudo -u ga git tag v2.3.0-release
sudo -u ga git commit --allow-empty -m "Release v2.3.0"

echo "Creating commits 3-16 (innocent changes)..."

# Commits 3-16: Various innocent changes
for i in {3..16}; do
    echo "# Update $i" >> "$REPO_DIR/README.md"
    sudo -u ga git add README.md
    sudo -u ga git commit -m "Update documentation - iteration $i"
done

echo "Creating commit 17 (THE BUG)..."

# Commit 17: THE BUG - break Visa validation with bad regex
cat > "$REPO_DIR/payment_validator.py" << 'EOF'
import re

def validate_card(card_number):
    """Validate credit card number"""
    # Remove spaces and dashes
    card = card_number.replace(' ', '').replace('-', '')
    
    # Check if it's digits only
    if not card.isdigit():
        return False
    
    # BUG: Changed regex pattern incorrectly restricts Visa
    # Only accepts Visa starting with 4539, not all 4xxx
    if re.match(r'^4539', card) and len(card) in [13, 16]:
        return luhn_check(card)
    
    # Mastercard: starts with 51-55 or 2221-2720, length 16
    if (card[:2] in ['51','52','53','54','55'] or 
        (2221 <= int(card[:4]) <= 2720)) and len(card) == 16:
        return luhn_check(card)
    
    return False

def luhn_check(card_number):
    """Implement Luhn algorithm"""
    def digits_of(n):
        return [int(d) for d in str(n)]
    
    digits = digits_of(card_number)
    odd_digits = digits[-1::-2]
    even_digits = digits[-2::-2]
    checksum = sum(odd_digits)
    for d in even_digits:
        checksum += sum(digits_of(d*2))
    return checksum % 10 == 0

if __name__ == "__main__":
    # Test cases
    print("Testing Visa:", validate_card("4532015112830366"))
    print("Testing Mastercard:", validate_card("5425233430109903"))
EOF

sudo -u ga git add payment_validator.py
sudo -u ga git commit -m "Refactor Visa validation pattern - use regex for consistency"

echo "Creating commits 18-25 (more innocent changes)..."

# Commits 18-25: More innocent changes
for i in {18..25}; do
    echo "# Update $i" >> "$REPO_DIR/README.md"
    sudo -u ga git add README.md
    sudo -u ga git commit -m "Minor updates and improvements - iteration $i"
done

# Commit 25: Tag as current
sudo -u ga git tag v2.4.0-current

echo "Git repository created successfully:"
echo "  - Total commits: $(cd "$REPO_DIR" && sudo -u ga git rev-list --count HEAD)"
echo "  - Good tag: v2.3.0-release"
echo "  - Bad tag: v2.4.0-current"
echo "  - Bug introduced in commit: 'Refactor Visa validation pattern'"

# Verify the bug exists
cd "$REPO_DIR"
echo ""
echo "Verifying bug exists in current version:"
sudo -u ga ./run_test.sh && echo "✓ Test passes (unexpected!)" || echo "✗ Test fails (expected - bug present)"

# Verify old version worked
sudo -u ga git checkout v2.3.0-release > /dev/null 2>&1
echo "Verifying old version worked:"
sudo -u ga ./run_test.sh && echo "✓ Test passes (expected - no bug)" || echo "✗ Test fails (unexpected!)"

# Return to latest
sudo -u ga git checkout main > /dev/null 2>&1 || sudo -u ga git checkout master > /dev/null 2>&1

# Open VSCode with the repository
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$REPO_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Git Bisect Payment Regression Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open integrated terminal (Ctrl+\` or Terminal → New Terminal)"
echo "  2. Navigate to: /home/ga/workspace/payment-service/"
echo "  3. Start bisect: git bisect start"
echo "  4. Mark bad: git bisect bad v2.4.0-current"
echo "  5. Mark good: git bisect good v2.3.0-release"
echo "  6. For each commit, run: ./run_test.sh"
echo "  7. Mark result: git bisect good OR git bisect bad"
echo "  8. Repeat until Git finds the culprit"
echo "  9. Save log: git bisect log > /home/ga/workspace/bisect_result.txt"
echo "  10. End bisect: git bisect reset"