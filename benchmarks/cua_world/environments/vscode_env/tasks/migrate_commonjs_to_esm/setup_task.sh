#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Migrate CommonJS to ESM Task ==="

WORKSPACE_DIR="/home/ga/workspace/auth-service"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/test"

# Create package.json (CommonJS - no "type": "module")
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "auth-service",
  "version": "1.0.0",
  "description": "Authentication service utilities",
  "main": "src/auth.js",
  "scripts": {
    "test": "node test/auth.test.js"
  },
  "keywords": ["auth", "jwt"],
  "author": "Engineering Team",
  "license": "MIT"
}
EOF

# Create config.json
cat > "$WORKSPACE_DIR/config.json" << 'EOF'
{
  "jwtSecret": "super-secret-key-change-in-production",
  "tokenExpiry": 3600,
  "hashIterations": 100000
}
EOF

# Create src/auth.js (CommonJS)
cat > "$WORKSPACE_DIR/src/auth.js" << 'EOF'
const crypto = require('crypto');
const { hashPassword, verifyPassword } = require('./utils/hash.js');
const config = require('./config.js');

class AuthService {
  constructor() {
    this.secret = config.jwtSecret;
    this.tokenExpiry = config.tokenExpiry;
  }

  async authenticate(username, password) {
    const hash = await hashPassword(password);
    // Simplified auth logic for demonstration
    const token = crypto.randomBytes(32).toString('hex');
    return { 
      success: true, 
      token: token,
      expiresIn: this.tokenExpiry 
    };
  }

  verifyToken(token) {
    // Simplified verification - just check format
    return token && token.length === 64;
  }

  async changePassword(username, oldPassword, newPassword) {
    const oldHash = await hashPassword(oldPassword);
    const newHash = await hashPassword(newPassword);
    return { success: true, message: 'Password changed' };
  }
}

module.exports = AuthService;
EOF

# Create src/utils/hash.js (CommonJS)
cat > "$WORKSPACE_DIR/src/utils/hash.js" << 'EOF'
const crypto = require('crypto');

function hashPassword(password) {
  return new Promise((resolve, reject) => {
    crypto.pbkdf2(password, 'salt', 100000, 64, 'sha512', (err, derivedKey) => {
      if (err) reject(err);
      resolve(derivedKey.toString('hex'));
    });
  });
}

function verifyPassword(password, hash) {
  return hashPassword(password).then(computed => computed === hash);
}

function generateSalt() {
  return crypto.randomBytes(16).toString('hex');
}

module.exports = { hashPassword, verifyPassword, generateSalt };
EOF

# Create src/config.js (CommonJS with JSON import)
cat > "$WORKSPACE_DIR/src/config.js" << 'EOF'
const fs = require('fs');
const path = require('path');

const configPath = path.join(__dirname, '..', 'config.json');
const configData = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(configData);

module.exports = config;
EOF

# Create test/auth.test.js (CommonJS)
cat > "$WORKSPACE_DIR/test/auth.test.js" << 'EOF'
const AuthService = require('../src/auth.js');
const assert = require('assert');

async function testAuthentication() {
  const auth = new AuthService();
  const result = await auth.authenticate('testuser', 'password123');
  
  assert.strictEqual(result.success, true, 'Authentication should succeed');
  assert.ok(result.token, 'Token should be generated');
  assert.strictEqual(auth.verifyToken(result.token), true, 'Token should be valid');
  
  console.log('✅ Authentication test passed');
}

async function testPasswordChange() {
  const auth = new AuthService();
  const result = await auth.changePassword('testuser', 'oldpass', 'newpass');
  
  assert.strictEqual(result.success, true, 'Password change should succeed');
  
  console.log('✅ Password change test passed');
}

async function runAllTests() {
  try {
    await testAuthentication();
    await testPasswordChange();
    console.log('\n🎉 All tests passed!');
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

runAllTests();
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create a README for context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Auth Service - CommonJS to ESM Migration

## Task
Migrate this Node.js authentication library from CommonJS to ES Modules.

## Files to migrate:
- src/auth.js
- src/utils/hash.js
- src/config.js
- test/auth.test.js
- package.json (add "type": "module")

## Steps:
1. Update package.json with "type": "module"
2. Convert all require() to import
3. Convert all module.exports to export
4. Handle JSON imports properly
5. Save all files

Good luck!
EOF

sudo chown ga:ga "$WORKSPACE_DIR/README.md"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Migrate CommonJS to ESM Task Setup Complete ==="
echo "📁 Workspace: $WORKSPACE_DIR"
echo ""
echo "📝 Task Instructions:"
echo "  1. Open package.json and add '\"type\": \"module\"'"
echo "  2. Convert all require() to import in:"
echo "     - src/auth.js"
echo "     - src/utils/hash.js"
echo "     - src/config.js"
echo "     - test/auth.test.js"
echo "  3. Convert all module.exports to export statements"
echo "  4. Handle JSON import in config.js properly"
echo "  5. Use 'node:' prefix for built-in modules"
echo "  6. Save all files (Ctrl+S)"
echo ""
echo "💡 Tip: Use Find and Replace (Ctrl+H) across files for efficiency"