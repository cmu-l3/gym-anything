#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Rotate Exposed Credentials Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment_service"
TASK_ASSETS="/workspace/tasks/rotate_exposed_credentials/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/config"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create production files with EXPOSED key

# 1. src/payment_client.py
cat > "$WORKSPACE_DIR/src/payment_client.py" << 'EOF'
import os
import stripe

# Initialize Stripe with secret key
STRIPE_SECRET_KEY = "sk_live_A7xK9mP2nQ4rL8vB3wE6yT1"
stripe.api_key = STRIPE_SECRET_KEY

def create_charge(amount, currency="usd"):
    """Create a charge using Stripe API"""
    return stripe.Charge.create(
        amount=amount,
        currency=currency,
        source="tok_visa"
    )

def list_customers(limit=10):
    """List customers"""
    return stripe.Customer.list(limit=limit)
EOF

# 2. src/utils/stripe_helper.js
cat > "$WORKSPACE_DIR/src/utils/stripe_helper.js" << 'EOF'
const stripe = require('stripe')('sk_live_A7xK9mP2nQ4rL8vB3wE6yT1');

async function createCustomer(email) {
  return await stripe.customers.create({ email });
}

async function createPaymentIntent(amount, currency = 'usd') {
  return await stripe.paymentIntents.create({
    amount: amount,
    currency: currency,
  });
}

module.exports = { createCustomer, createPaymentIntent };
EOF

# 3. config/production.yaml
cat > "$WORKSPACE_DIR/config/production.yaml" << 'EOF'
payment:
  provider: stripe
  api_version: "2023-10-16"
  secret_key: sk_live_A7xK9mP2nQ4rL8vB3wE6yT1
  publishable_key: pk_live_example123
  webhook_secret: whsec_test123
  
database:
  host: localhost
  port: 5432
  name: payments_prod
EOF

# 4. .env.example
cat > "$WORKSPACE_DIR/.env.example" << 'EOF'
# Stripe Configuration
STRIPE_SECRET_KEY=sk_live_A7xK9mP2nQ4rL8vB3wE6yT1
STRIPE_PUBLISHABLE_KEY=pk_live_example123

# Database
DATABASE_URL=postgresql://localhost/paymentdb
EOF

# 5. .env.local
cat > "$WORKSPACE_DIR/.env.local" << 'EOF'
STRIPE_SECRET_KEY=sk_live_A7xK9mP2nQ4rL8vB3wE6yT1
STRIPE_PUBLISHABLE_KEY=pk_live_example123
DATABASE_URL=postgresql://localhost/paymentdb
DEBUG=true
EOF

# Create TEST files with MOCK keys (should NOT be changed)

# 6. tests/test_payment.py
cat > "$WORKSPACE_DIR/tests/test_payment.py" << 'EOF'
import pytest
from unittest.mock import Mock, patch

MOCK_STRIPE_KEY = "sk_test_mock_12345"  # This is a test mock key

def test_charge_creation():
    """Test charge creation with mock key"""
    mock_client = Mock()
    mock_client.api_key = MOCK_STRIPE_KEY
    assert mock_client.api_key == "sk_test_mock_12345"
    
def test_customer_list():
    """Test customer listing"""
    with patch('stripe.api_key', MOCK_STRIPE_KEY):
        # Test implementation
        assert stripe.api_key == "sk_test_mock_12345"
EOF

# 7. tests/stripe.test.js
cat > "$WORKSPACE_DIR/tests/stripe.test.js" << 'EOF'
const mockStripe = require('stripe')('sk_test_mock_12345');

describe('Stripe Integration', () => {
  test('creates customer with mock key', async () => {
    const key = 'sk_test_mock_12345';
    expect(key).toContain('sk_test');
  });
  
  test('mock key is not production key', () => {
    const mockKey = 'sk_test_mock_12345';
    expect(mockKey).not.toContain('sk_live');
  });
});
EOF

# 8. README.md (with placeholder that should NOT be changed)
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Payment Service

Stripe payment integration service for processing payments.

## Setup

1. Get your Stripe API key from the dashboard
2. Create a `.env.local` file: