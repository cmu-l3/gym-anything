#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Salvage Interrupted Work Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-server"
USER="ga"

# Clean up any existing workspace
sudo rm -rf "$WORKSPACE_DIR"

# Create project structure
sudo -u $USER mkdir -p "$WORKSPACE_DIR"/{src/{routes,middleware,utils},tests}
cd "$WORKSPACE_DIR"

# Initialize git repository
sudo -u $USER git init
sudo -u $USER git config user.name "Sarah Developer"
sudo -u $USER git config user.email "sarah@example.com"

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "api-server",
  "version": "1.0.0",
  "description": "Express API Server",
  "main": "src/app.js",
  "scripts": {
    "start": "node src/app.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.0",
    "jsonwebtoken": "^9.0.0"
  }
}
EOF

# Create initial file versions (CLEAN state - with bugs)
cat > "$WORKSPACE_DIR/src/routes/users.js" << 'EOF'
const express = require('express');
const router = express.Router();

router.get('/:id', async (req, res) => {
  const user = await db.getUser(req.params.id);
  // BUG: No null check on user.email
  const email = user.email.toLowerCase();
  res.json({ user, email });
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/routes/products.js" << 'EOF'
const express = require('express');
const router = express.Router();

router.get('/:id', async (req, res) => {
  const product = await db.getProduct(req.params.id);
  // BUG: No null check on product.price
  const discount = product.price * 0.1;
  res.json({ product, discount });
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/utils/logger.js" << 'EOF'
const winston = require('winston');

function logError(error) {
  // BUG: No null check on error.message
  console.error(`[ERROR] ${error.message}`);
}

module.exports = { logError };
EOF

cat > "$WORKSPACE_DIR/src/routes/auth.js" << 'EOF'
const express = require('express');
const router = express.Router();

// Placeholder - no implementation yet
module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/middleware/auth.js" << 'EOF'
// Placeholder - no implementation yet
module.exports = {};
EOF

cat > "$WORKSPACE_DIR/src/middleware/validation.js" << 'EOF'
function validateRequest(schema) {
  return (req, res, next) => {
    // Validation logic here
    next();
  };
}

module.exports = { validateRequest };
EOF

cat > "$WORKSPACE_DIR/src/app.js" << 'EOF'
const express = require('express');
const app = express();

app.use(express.json());

// Routes will be added here

module.exports = app;
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# API Server

A simple Express-based API server.
EOF

# Set ownership and commit initial state
sudo chown -R $USER:$USER "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u $USER git add .
sudo -u $USER git commit -m "Initial API server structure"

echo "Initial commit created"

# Now apply the MIXED changes (bug fixes + incomplete auth)

# Bug fix changes
cat > "$WORKSPACE_DIR/src/routes/users.js" << 'EOF'
const express = require('express');
const router = express.Router();

router.get('/:id', async (req, res) => {
  const user = await db.getUser(req.params.id);
  // FIXED: Added null check
  const email = user?.email?.toLowerCase() || 'no-email';
  res.json({ user, email });
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/routes/products.js" << 'EOF'
const express = require('express');
const router = express.Router();

router.get('/:id', async (req, res) => {
  const product = await db.getProduct(req.params.id);
  // FIXED: Added null check
  const discount = (product?.price || 0) * 0.1;
  res.json({ product, discount });
});

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/utils/logger.js" << 'EOF'
const winston = require('winston');

function logError(error) {
  // FIXED: Added null check
  const message = error?.message || 'Unknown error';
  console.error(`[ERROR] ${message}`);
}

module.exports = { logError };
EOF

# Incomplete authentication feature changes
cat > "$WORKSPACE_DIR/src/routes/auth.js" << 'EOF'
const express = require('express');
const router = express.Router();
const jwt = require('../utils/jwt');

router.post('/login', async (req, res) => {
  const { username, password } = req.body;
  // TODO: Implement actual authentication logic
  // This is incomplete - needs database check
  const token = jwt.generateToken({ username });
  res.json({ token });
});

// TODO: Add logout, refresh token endpoints

module.exports = router;
EOF

cat > "$WORKSPACE_DIR/src/middleware/auth.js" << 'EOF'
const jwt = require('../utils/jwt');

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  
  // TODO: Complete implementation
  // This is incomplete - needs proper verification
  
  next();
}

module.exports = { authenticateToken };
EOF

cat > "$WORKSPACE_DIR/src/utils/jwt.js" << 'EOF'
const jwt = require('jsonwebtoken');

const SECRET_KEY = 'temporary-secret-key'; // TODO: Move to environment variable

function generateToken(payload) {
  // TODO: Add expiration, proper secret management
  return jwt.sign(payload, SECRET_KEY);
}

function verifyToken(token) {
  // TODO: Implement verification
  return null;
}

module.exports = { generateToken, verifyToken };
EOF

cat > "$WORKSPACE_DIR/tests/auth.test.js" << 'EOF'
const request = require('supertest');
const app = require('../src/app');

describe('Authentication', () => {
  test('POST /auth/login should return token', async () => {
    // TODO: Implement actual test
    expect(true).toBe(true);
  });
  
  // TODO: Add more tests
});
EOF

# Set final ownership
sudo chown -R $USER:$USER "$WORKSPACE_DIR"

echo "Mixed changes applied (all uncommitted)"

# Open VSCode
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 35

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Salvage Interrupted Work Task Setup Complete ==="
echo "📝 Workspace: $WORKSPACE_DIR"
echo "📝 Current branch: main"
echo "📝 Uncommitted changes:"
echo "   - Bug fixes: users.js, products.js, logger.js (COMPLETED)"
echo "   - Auth feature: auth.js, middleware/auth.js, jwt.js, auth.test.js (INCOMPLETE)"
echo ""
echo "🎯 Task: Separate and organize these changes properly"