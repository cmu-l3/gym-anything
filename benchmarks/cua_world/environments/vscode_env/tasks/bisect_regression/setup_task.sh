#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bisect Regression Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment-service"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Initialize Git repository
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create package.json for Node.js project
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "payment-service",
  "version": "2.3.0",
  "description": "Payment processing service with idempotency",
  "scripts": {
    "test": "node test.js"
  },
  "author": "Payment Team",
  "license": "MIT"
}
EOF

# Create initial GOOD version of payment.js
cat > "$WORKSPACE_DIR/payment.js" << 'EOF'
// Payment processing with idempotency
const processedPayments = new Set();

function processPayment(paymentId, amount) {
  if (processedPayments.has(paymentId)) {
    return { status: 'duplicate', message: 'Already processed' };
  }
  
  processedPayments.add(paymentId);
  return { status: 'success', amount: amount };
}

function clearProcessedPayments() {
  processedPayments.clear();
}

module.exports = { processPayment, clearProcessedPayments, processedPayments };
EOF

# Create test file
cat > "$WORKSPACE_DIR/test.js" << 'EOF'
const { processPayment, clearProcessedPayments } = require('./payment.js');

function test_payment_processing_idempotency() {
  // Clear state before test
  clearProcessedPayments();
  
  const paymentId = 'PAY-12345';
  const amount = 100;
  
  // First call should succeed
  const result1 = processPayment(paymentId, amount);
  if (result1.status !== 'success') {
    console.error('❌ test_payment_processing_idempotency FAILED');
    console.error(`   Expected status='success', got status='${result1.status}'`);
    process.exit(1);
  }
  
  // Second call with same ID should be detected as duplicate
  const result2 = processPayment(paymentId, amount);
  if (result2.status !== 'duplicate') {
    console.error('❌ test_payment_processing_idempotency FAILED');
    console.error(`   Expected status='duplicate', got status='${result2.status}'`);
    console.error('   Idempotency check failed - payment was processed twice!');
    process.exit(1);
  }
  
  console.log('✓ test_payment_processing_idempotency PASSED');
  process.exit(0);
}

// Run test
test_payment_processing_idempotency();
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Payment Service

A simple payment processing service with idempotency checks.

## Testing

Run tests with: `npm test`
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create initial commit (known-good state)
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit: payment service with idempotency test"
sudo -u ga git tag v2.3.0-pre-vacation

# Store the bad commit SHA for later verification
BAD_COMMIT_NUMBER=23

# Create 47 commits (simulate team activity during vacation)
for i in {1..47}; do
  if [ $i -eq $BAD_COMMIT_NUMBER ]; then
    # THIS IS THE BAD COMMIT - introduces the bug
    cat > "$WORKSPACE_DIR/payment.js" << 'EOF'
// Payment processing with idempotency
const processedPayments = new Set();

function processPayment(paymentId, amount) {
  // BUG: Someone accidentally added this line during refactoring
  // This clears the Set before checking, breaking idempotency!
  processedPayments.clear();
  
  if (processedPayments.has(paymentId)) {
    return { status: 'duplicate', message: 'Already processed' };
  }
  
  processedPayments.add(paymentId);
  return { status: 'success', amount: amount };
}

function clearProcessedPayments() {
  processedPayments.clear();
}

module.exports = { processPayment, clearProcessedPayments, processedPayments };
EOF
    sudo -u ga git add payment.js
    sudo -u ga git commit -m "refactor: clean up payment processing logic"
    
    # Store the bad commit SHA in a file for verifier
    sudo -u ga git rev-parse HEAD > /tmp/bad_commit_sha.txt
    
  elif [ $i -eq 15 ]; then
    # Add some realistic commits
    echo "" >> "$WORKSPACE_DIR/README.md"
    echo "## Features" >> "$WORKSPACE_DIR/README.md"
    echo "- Idempotent payment processing" >> "$WORKSPACE_DIR/README.md"
    sudo -u ga git add README.md
    sudo -u ga git commit -m "docs: add features section to README"
    
  elif [ $i -eq 30 ]; then
    echo "- Duplicate detection" >> "$WORKSPACE_DIR/README.md"
    sudo -u ga git add README.md
    sudo -u ga git commit -m "docs: document duplicate detection feature"
    
  elif [ $i -eq 40 ]; then
    cat >> "$WORKSPACE_DIR/package.json" << 'EOF'

EOF
    sudo -u ga git add package.json
    sudo -u ga git commit -m "chore: update package.json formatting"
    
  else
    # Innocuous commits that don't break anything
    echo "// Team activity commit $i" >> "$WORKSPACE_DIR/README.md"
    sudo -u ga git add README.md
    sudo -u ga git commit -m "docs: update README (commit $i)"
  fi
done

# Create staging branch pointing to HEAD
sudo -u ga git checkout -b staging

# Verify Node.js is available
if ! command -v node &> /dev/null; then
    echo "⚠️ Warning: Node.js not found, attempting to use existing installation"
fi

# Test that the bad state actually fails
echo "Verifying that current state fails the test..."
cd "$WORKSPACE_DIR"
if sudo -u ga npm test 2>&1; then
    echo "⚠️ Warning: Test passed when it should fail (bug might not be present)"
else
    echo "✓ Confirmed: Test fails on current HEAD (as expected)"
fi

# Ensure VSCode is ready
if ! pgrep -f "code" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code --new-window" &
    wait_for_vscode 20
fi

# Open VSCode with the workspace
echo "Opening VSCode with payment-service workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open integrated terminal in VSCode
sleep 2
su - ga -c "DISPLAY=:1 xdotool key ctrl+grave" || true
sleep 1

echo "=== Bisect Regression Task Setup Complete ==="
echo "📍 Repository: $WORKSPACE_DIR"
echo "📊 Commits: 48 total (1 initial + 47 during vacation)"
echo "🐛 Bug location: Commit $BAD_COMMIT_NUMBER introduces the regression"
echo "🏷️  Known-good tag: v2.3.0-pre-vacation"
echo ""
echo "📝 Instructions:"
echo "  1. Use the integrated terminal in VSCode (Ctrl+`)"
echo "  2. Navigate to: cd /home/ga/workspace/payment-service"
echo "  3. Start bisect: git bisect start"
echo "  4. Mark current as bad: git bisect bad HEAD"
echo "  5. Mark last good: git bisect good v2.3.0-pre-vacation"
echo "  6. At each step: npm test"
echo "  7. Mark result: git bisect good (if test passes) OR git bisect bad (if fails)"
echo "  8. Continue until git identifies the bad commit"
echo "  9. Document findings in BISECT_RESULTS.md"
echo "  10. Clean up: git bisect reset"