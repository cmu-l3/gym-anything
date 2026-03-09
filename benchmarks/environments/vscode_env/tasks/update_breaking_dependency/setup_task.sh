#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Update Breaking Dependency Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-project"
sudo -u ga mkdir -p "$WORKSPACE_DIR/lib"
sudo -u ga mkdir -p "$WORKSPACE_DIR/middleware"

# Create package.json with old axios version
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "payment-api",
  "version": "1.0.0",
  "description": "Payment API service",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "0.27.2",
    "dotenv": "^16.0.3"
  },
  "scripts": {
    "test": "node test.js",
    "start": "node server.js"
  }
}
EOF

# Create payment-client.js with old axios error handling
cat > "$WORKSPACE_DIR/lib/payment-client.js" << 'EOF'
const axios = require('axios');

class PaymentClient {
  async processPayment(amount, token) {
    try {
      const response = await axios.post('https://api.payments.example/charge', {
        amount,
        token
      });
      return response.data;
    } catch (error) {
      // Old axios 0.x API: error.response is undefined for network errors
      if (error.response) {
        console.error('Payment failed:', error.response.data);
        throw new Error(`Payment error: ${error.response.status}`);
      } else if (error.request) {
        console.error('Network error:', error.request);
        throw new Error('Network error');
      } else {
        throw error;
      }
    }
  }

  async refundPayment(transactionId) {
    try {
      const response = await axios.post('https://api.payments.example/refund', {
        transaction_id: transactionId
      });
      return response.data;
    } catch (err) {
      // Inconsistent error handling pattern
      if (err.response && err.response.data) {
        throw new Error(err.response.data.message);
      }
      throw err;
    }
  }
}

module.exports = PaymentClient;
EOF

# Create api-client.js with old axios error handling
cat > "$WORKSPACE_DIR/middleware/api-client.js" << 'EOF'
const axios = require('axios');

async function fetchUserProfile(userId) {
  try {
    const response = await axios.get(`https://api.users.example/profile/${userId}`);
    return response.data;
  } catch (error) {
    // Old pattern: checking error.response
    if (error.response) {
      if (error.response.status === 404) {
        return null;
      }
      throw new Error(`API error: ${error.response.status}`);
    }
    throw new Error('Network failure');
  }
}

module.exports = { fetchUserProfile };
EOF

# Create migration guide
cat > "$WORKSPACE_DIR/MIGRATION_GUIDE.md" << 'EOF'
# Axios 1.x Migration Guide

## Breaking Changes

### Error Handling
In axios 1.x, the error structure has changed:

**Old (0.x)**: