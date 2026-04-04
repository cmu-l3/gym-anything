#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Code Archaeology Task ==="

WORKSPACE_DIR="/home/ga/workspace/pricing-project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/pricing"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.github/issues"

# Initialize Git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Create initial clean version of discount.js
cat > "$WORKSPACE_DIR/src/pricing/discount.js" << 'EOF'
/**
 * Calculate discounted price for customers
 */
function calculateDiscount(price, discountPercent, customerCreatedAt) {
  // Apply discount
  let discounted = price * (1 - discountPercent / 100);
  return discounted;
}

module.exports = { calculateDiscount };
EOF

# Create initial test file
cat > "$WORKSPACE_DIR/tests/discount.test.js" << 'EOF'
const { calculateDiscount } = require('../src/pricing/discount');

test('applies 10% discount correctly', () => {
  expect(calculateDiscount(100, 10, '2019-05-15')).toBe(90);
});
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Pricing Module

E-commerce pricing and discount calculation system.

## Structure
- `src/pricing/` - Core pricing logic
- `tests/` - Unit tests
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initial commit (clean code)
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial pricing module implementation" --date="2020-01-15T10:00:00"

# Add a few unrelated commits to make history more realistic
cat >> "$WORKSPACE_DIR/README.md" << 'EOF'

## Installation
npm install
EOF

sudo -u ga git add README.md
sudo -u ga git commit -m "Add installation instructions" --date="2020-02-10T14:30:00"

cat > "$WORKSPACE_DIR/src/pricing/tax.js" << 'EOF'
function calculateTax(price, taxRate) {
  return price * (taxRate / 100);
}

module.exports = { calculateTax };
EOF

sudo -u ga git add src/pricing/tax.js
sudo -u ga git commit -m "Add tax calculation module" --date="2020-11-05T09:15:00"

# Now create the confusing code with the specific commit we want them to find
cat > "$WORKSPACE_DIR/src/pricing/discount.js" << 'EOF'
/**
 * Calculate discounted price for customers
 */
function calculateDiscount(price, discountPercent, customerCreatedAt) {
  // Apply discount
  let discounted = price * (1 - discountPercent / 100);
  
  // TODO: See issue #247 for context on this calculation
  // FIXME: This looks wrong but DO NOT CHANGE without reading issue #247
  // There's a subtle bug in how we stored prices during 2020-2021
  // See commit a3f82b4 for explanation
  if (isLeapYearCustomer(customerCreatedAt)) {
    discounted = discounted / 0.95;  // Undo old discount
    discounted = discounted * 0.95;  // Reapply correctly
  }
  
  return discounted;
}

function isLeapYearCustomer(createdAt) {
  const year = new Date(createdAt).getFullYear();
  return year === 2020; // Leap year when pricing bug occurred
}

module.exports = { calculateDiscount };
EOF

# Update test file to include edge case
cat > "$WORKSPACE_DIR/tests/discount.test.js" << 'EOF'
const { calculateDiscount } = require('../src/pricing/discount');

test('applies 10% discount correctly', () => {
  expect(calculateDiscount(100, 10, '2019-05-15')).toBe(90);
});

test('handles 2020 leap year customer pricing bug workaround', () => {
  // This test verifies the workaround for issue #247
  // 2020 customers had double-discount bug, we compensate in code
  expect(calculateDiscount(100, 10, '2020-03-15')).toBe(90);
});

test('normal discount for 2021 customers', () => {
  expect(calculateDiscount(100, 10, '2021-06-20')).toBe(90);
});
EOF

sudo -u ga git add .
# Use specific author for this commit
GIT_AUTHOR_NAME="Sarah Chen" GIT_AUTHOR_EMAIL="sarah@company.com" \
GIT_COMMITTER_NAME="Sarah Chen" GIT_COMMITTER_EMAIL="sarah@company.com" \
sudo -u ga git commit -m "Fix leap year pricing bug for 2020 customers

We had a bug in Q1 2020 where discounts were applied twice
due to timezone calculation error. Customers created during
2020 have incorrect base prices in database. This compensates
by undoing the double-discount and reapplying correctly.

Fixes #247
DO NOT remove this workaround until we run the data migration
planned for 2025 (see issue #312)" --date="2021-03-15T14:23:18"

# Add more commits after to make it less obvious
cat >> "$WORKSPACE_DIR/README.md" << 'EOF'

## Testing
npm test
EOF

sudo -u ga git add README.md
sudo -u ga git commit -m "Add testing instructions" --date="2021-06-20T11:00:00"

# Create GitHub issue files for context
cat > "$WORKSPACE_DIR/.github/issues/247.txt" << 'EOF'
Issue #247: Leap year customers have wrong base prices
Status: WORKAROUND IMPLEMENTED
Created: 2021-03-10
Author: Sarah Chen

DESCRIPTION:
During 2020, we had a timezone bug that caused discounts to be
applied twice for customers created on leap day and during DST
transitions. We can't easily fix the stored prices in the database,
so we need to compensate in the calculation logic.

IMPACT:
- Affects approximately 5,000 customers created in 2020
- They see incorrect prices if we use normal discount calculation
- Compensation needed until data migration

WORKAROUND:
Undo the double-discount for affected customers in discount calculation.
See src/pricing/discount.js - isLeapYearCustomer() check.

LONG-TERM FIX:
Data migration scheduled for 2025 (see issue #312).
Once migration runs, this workaround can be removed.
EOF

cat > "$WORKSPACE_DIR/.github/issues/312.txt" << 'EOF'
Issue #312: Database migration to fix 2020 pricing data
Status: PLANNED
Created: 2021-04-01
Scheduled: Q2 2025

DESCRIPTION:
Migrate database to fix incorrect base prices for customers
created during 2020 leap year timezone bug period.

DEPENDENCIES:
- Issue #247 workaround currently in place
- Once this migration completes, remove workaround from discount.js

TIMELINE:
Scheduled for Q2 2025 during planned database upgrade.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the project
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/src/pricing/discount.js'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Give time for Git extension to load
sleep 3

echo "=== Code Archaeology Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Examine the confusing code in src/pricing/discount.js (lines with 0.95)"
echo "  2. Use Git Blame: right-click file → 'Git: View File History'"
echo "  3. Find commit that added this code"
echo "  4. Read commit message for context"
echo "  5. Check .github/issues/ for related issues"
echo "  6. Create INVESTIGATION.md documenting your findings"
echo ""
echo "Workspace: $WORKSPACE_DIR"