#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Missing Search Results Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment-service"
VSCODE_SETTINGS_DIR="$WORKSPACE_DIR/.vscode"

# Create project structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/config"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/node_modules/stripe"
sudo -u ga mkdir -p "$VSCODE_SETTINGS_DIR"

# Create files that SHOULD appear in search
cat > "$WORKSPACE_DIR/src/billing.js" << 'EOF'
// Main billing module
const STRIPE_KEY = process.env.STRIPE_KEY;
const LEGACY_STRIPE_KEY = process.env.LEGACY_STRIPE_KEY; // TODO: Remove after migration

function initializeBilling() {
  console.log("Initializing billing with legacy key");
  return { key: LEGACY_STRIPE_KEY };
}

module.exports = { STRIPE_KEY, LEGACY_STRIPE_KEY, initializeBilling };
EOF

cat > "$WORKSPACE_DIR/src/checkout.js" << 'EOF'
const { LEGACY_STRIPE_KEY } = require('./billing');

// Using legacy key for backward compatibility
function processOldCheckout(amount) {
  console.log("Processing checkout with legacy integration");
  return initStripe(LEGACY_STRIPE_KEY, amount);
}

function initStripe(key, amount) {
  return { key, amount, status: 'pending' };
}

module.exports = { processOldCheckout };
EOF

cat > "$WORKSPACE_DIR/.env" << 'EOF'
# Environment variables for payment service
STRIPE_KEY=sk_live_newkey123abc
LEGACY_STRIPE_KEY=sk_live_oldkey456def
DATABASE_URL=postgresql://localhost/payments
NODE_ENV=production
EOF

# Create the "missing from search" file - the problematic JSON file
cat > "$WORKSPACE_DIR/config/payment-providers.json" << 'EOF'
{
  "version": "2.1.0",
  "providers": {
    "stripe": {
      "apiKey": "LEGACY_STRIPE_KEY",
      "webhookSecret": "whsec_oldwebhook789",
      "apiVersion": "2019-12-03",
      "description": "Legacy Stripe integration - scheduled for deprecation Q2 2024"
    },
    "stripe_v2": {
      "apiKey": "STRIPE_KEY",
      "webhookSecret": "whsec_newwebhook123",
      "apiVersion": "2023-10-16",
      "description": "New Stripe integration"
    },
    "paypal": {
      "clientId": "AYSq3RDGsmBl...",
      "sandbox": true
    }
  },
  "fallback": {
    "provider": "stripe",
    "useKey": "LEGACY_STRIPE_KEY",
    "note": "Fallback still uses old key for compatibility"
  },
  "deprecation_timeline": {
    "announcement": "2024-01-15",
    "migration_deadline": "2024-06-30",
    "shutdown": "2024-09-01"
  }
}
EOF

# Create a node_modules file with the same string (should stay excluded)
cat > "$WORKSPACE_DIR/node_modules/stripe/config.json" << 'EOF'
{
  "test_key": "LEGACY_STRIPE_KEY",
  "note": "This file should remain excluded from search"
}
EOF

# Configure workspace settings to EXCLUDE all JSON files from search
cat > "$VSCODE_SETTINGS_DIR/settings.json" << 'EOF'
{
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/*.json": true
  },
  "files.watcherExclude": {
    "**/node_modules/**": true
  },
  "editor.formatOnSave": true
}
EOF

# Create gitignore (realistic but not the culprit)
cat > "$WORKSPACE_DIR/.gitignore" << 'EOF'
node_modules/
dist/
.env
*.log
.DS_Store
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "payment-service",
  "version": "2.3.1",
  "description": "Payment processing microservice",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "test": "jest"
  },
  "dependencies": {
    "stripe": "^12.0.0",
    "express": "^4.18.0"
  }
}
EOF

# Create README for context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Payment Service

Microservice for handling payment processing.

## Security Notice

We are migrating from LEGACY_STRIPE_KEY to the new STRIPE_KEY.
All references to the legacy key must be identified and updated by Q2 2024.
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with this workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Diagnose Missing Search Results Task Setup Complete ==="
echo "📁 Workspace: $WORKSPACE_DIR"
echo "📝 Problematic file: config/payment-providers.json"
echo "⚙️  Issue: Workspace settings exclude all JSON files from search"
echo ""
echo "🎯 Instructions:"
echo "  1. Try searching for 'LEGACY_STRIPE_KEY' (Ctrl+Shift+F)"
echo "  2. Notice config/payment-providers.json is missing from results"
echo "  3. Open .vscode/settings.json to investigate"
echo "  4. Identify and fix the search.exclude configuration"
echo "  5. Save settings and verify the file is now searchable"