#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bypass Formatting Commits Task ==="

WORKSPACE="/home/ga/workspace/ecommerce-site"
sudo -u ga mkdir -p "$WORKSPACE/src/utils"
sudo -u ga mkdir -p "$WORKSPACE/src/components"

cd "$WORKSPACE"

# Initialize git repo
sudo -u ga git init
sudo -u ga git config user.name "Test User"
sudo -u ga git config user.email "test@example.com"

# Commit 1: Initial commit with working pricing logic
cat > "$WORKSPACE/src/utils/pricing.js" << 'EOF'
export function calculateDiscount(price, customerTier) {
  if (customerTier === 'premium') {
    return price * 0.20;
  }
  return price * 0.10;
}

export function calculateTotal(items) {
  return items.reduce((sum, item) => sum + item.price, 0);
}
EOF

cat > "$WORKSPACE/src/utils/validation.js" << 'EOF'
export function validateEmail(email) {
    return email.includes('@');
}
EOF

cat > "$WORKSPACE/README.md" << 'EOF'
# E-Commerce Site
A simple e-commerce platform.
EOF

sudo chown -R ga:ga "$WORKSPACE"

cd "$WORKSPACE"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit with pricing logic" \
  --date="2024-01-15T10:00:00" --author="Test User <test@example.com>"

# Commit 2: Alice makes a business logic change (introduces the bug)
sudo -u ga git config user.name "Alice Chen"
sudo -u ga git config user.email "alice@company.com"

cat > "$WORKSPACE/src/utils/pricing.js" << 'EOF'
export function calculateDiscount(price, customerTier) {
  if (customerTier === 'premium') {
    return price * 0.15;  // Changed from 0.20 to 0.15 - bug!
  }
  return price * 0.10;
}

export function calculateTotal(items) {
  return items.reduce((sum, item) => sum + item.price, 0);
}
EOF

sudo chown -R ga:ga "$WORKSPACE"

cd "$WORKSPACE"
sudo -u ga git add src/utils/pricing.js
sudo -u ga git commit -m "Update discount rates for premium tier" \
  --date="2024-01-22T14:30:00" --author="Alice Chen <alice@company.com>"

# Store Alice's commit for later verification
ALICE_COMMIT=$(cd "$WORKSPACE" && sudo -u ga git rev-parse HEAD)
echo "$ALICE_COMMIT" | sudo tee /tmp/alice_commit.txt > /dev/null
echo "Alice's commit: $ALICE_COMMIT"

# Commit 3: Bob does ESLint auto-fix (mass formatting commit #1)
sudo -u ga git config user.name "Bob Martinez"
sudo -u ga git config user.email "bob@company.com"

# Add semicolons, fix spacing (no logic change)
cat > "$WORKSPACE/src/utils/pricing.js" << 'EOF'
export function calculateDiscount(price, customerTier) {
    if (customerTier === 'premium') {
        return price * 0.15;
    }
    return price * 0.10;
}

export function calculateTotal(items) {
    return items.reduce((sum, item) => sum + item.price, 0);
}
EOF

cat > "$WORKSPACE/src/utils/validation.js" << 'EOF'
export function validateEmail(email) {
    return email.includes('@');
}

export function isPhoneValid(phone) {
    return phone.length === 10;
}
EOF

cat > "$WORKSPACE/README.md" << 'EOF'
# E-Commerce Site

A simple e-commerce platform.

## Features
- Shopping cart
- Discounts
EOF

sudo chown -R ga:ga "$WORKSPACE"

cd "$WORKSPACE"
sudo -u ga git add .
sudo -u ga git commit -m "ESLint auto-fix: formatting and semicolons" \
  --date="2024-02-01T09:00:00" --author="Bob Martinez <bob@company.com>"

ESLINT_COMMIT=$(cd "$WORKSPACE" && sudo -u ga git rev-parse HEAD)
echo "$ESLINT_COMMIT" | sudo tee /tmp/eslint_commit.txt > /dev/null
echo "ESLint commit: $ESLINT_COMMIT"

# Commit 4: Intern does Prettier formatting (mass formatting commit #2)
sudo -u ga git config user.name "Intern Sam"
sudo -u ga git config user.email "intern@company.com"

# Prettier changes indentation, quotes
cat > "$WORKSPACE/src/utils/pricing.js" << 'EOF'
export function calculateDiscount(price, customerTier) {
  if (customerTier === "premium") {
    return price * 0.15;
  }
  return price * 0.10;
}

export function calculateTotal(items) {
  return items.reduce((sum, item) => sum + item.price, 0);
}
EOF

cat > "$WORKSPACE/src/utils/validation.js" << 'EOF'
export function validateEmail(email) {
  return email.includes("@");
}

export function isPhoneValid(phone) {
  return phone.length === 10;
}
EOF

cat > "$WORKSPACE/README.md" << 'EOF'
# E-Commerce Site

A simple e-commerce platform.

## Features

- Shopping cart
- Discounts
EOF

sudo chown -R ga:ga "$WORKSPACE"

cd "$WORKSPACE"
sudo -u ga git add .
sudo -u ga git commit -m "Ran Prettier on entire codebase" \
  --date="2024-02-10T16:00:00" --author="Intern Sam <intern@company.com>"

PRETTIER_COMMIT=$(cd "$WORKSPACE" && sudo -u ga git rev-parse HEAD)
echo "$PRETTIER_COMMIT" | sudo tee /tmp/prettier_commit.txt > /dev/null
echo "Prettier commit: $PRETTIER_COMMIT"

# Add a Prettier config
cat > "$WORKSPACE/.prettierrc.json" << 'EOF'
{
  "semi": true,
  "singleQuote": false,
  "tabWidth": 2
}
EOF

sudo chown -R ga:ga "$WORKSPACE"

cd "$WORKSPACE"
sudo -u ga git add .prettierrc.json
sudo -u ga git commit -m "Add Prettier config" \
  --date="2024-02-10T16:05:00" --author="Intern Sam <intern@company.com>"

# Create hint file for the user
cat > "$WORKSPACE/TASK_CONTEXT.md" << 'EOF'
# Bug Investigation Task

## Problem
Customers are complaining that premium tier discounts are wrong (15% instead of expected 20%).

## Your Goal
Find out WHO changed the discount calculation logic in `src/utils/pricing.js` and WHEN.

## Challenge
Git blame is showing "Intern Sam - Ran Prettier on entire codebase" for every line.
The actual logic change is hidden behind formatting commits.

## Hint
Git has a feature to ignore specific commits when running blame.
Look into: `.git-blame-ignore-revs` file

## Steps to Solve
1. Run `git blame src/utils/pricing.js` to see the problem
2. Run `git log --oneline` to find formatting commits
3. Create `.git-blame-ignore-revs` file in project root
4. Add the commit hashes of formatting commits to this file
5. Optionally: `git config blame.ignoreRevsFile .git-blame-ignore-revs`
6. Run `git blame src/utils/pricing.js` again
7. Document your findings in a report file

## What to Report
- Who made the actual business logic change?
- What was their commit hash?
- When did they make the change?
- How did you bypass the formatting commits?
EOF

sudo chown -R ga:ga "$WORKSPACE"

# Open VSCode to the workspace with terminal
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE' '$WORKSPACE/TASK_CONTEXT.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open integrated terminal (Ctrl+`)
sleep 1
su - ga -c "DISPLAY=:1 xdotool key ctrl+grave" || true
sleep 1

echo "=== Bypass Formatting Commits Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read TASK_CONTEXT.md for background"
echo "  2. Run 'git blame src/utils/pricing.js' to see the problem"
echo "  3. Run 'git log --oneline' to find formatting commits"
echo "  4. Create .git-blame-ignore-revs file with commit hashes"
echo "  5. Run git blame again to find the real author"
echo "  6. Document findings in INVESTIGATION_REPORT.txt"
echo ""
echo "Workspace: $WORKSPACE"
echo "Formatting commits to ignore:"
echo "  ESLint: $ESLINT_COMMIT"
echo "  Prettier: $PRETTIER_COMMIT"
echo "Actual logic change by Alice: $ALICE_COMMIT"