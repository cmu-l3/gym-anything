#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Resolve Circular Imports Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-project"
SRC_DIR="$WORKSPACE_DIR/src"

# Create workspace structure
sudo -u ga mkdir -p "$SRC_DIR"

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "api-project",
  "version": "1.0.0",
  "description": "API project with circular dependency issue",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {},
  "devDependencies": {
    "madge": "^6.1.0"
  }
}
EOF

# Create index.js (entry point that tries to load modules)
cat > "$WORKSPACE_DIR/index.js" << 'EOF'
// Entry point for the application
console.log("Loading application modules...");

try {
  const validation = require('./src/validation');
  const formatting = require('./src/formatting');
  const database = require('./src/database');
  
  console.log("✅ All modules loaded successfully!");
  console.log("Validation module:", typeof validation.validateUser);
  console.log("Formatting module:", typeof formatting.formatError);
  console.log("Database module:", typeof database.getDatabaseConfig);
  
  // Test basic functionality
  const user = { email: 'test@example.com' };
  const result = validation.validateUser(user);
  console.log("Test validation:", result);
  
  process.exit(0);
} catch (error) {
  console.error("❌ Failed to load modules:");
  console.error(error.message);
  process.exit(1);
}
EOF

# Create validation.js (imports from formatting.js)
cat > "$SRC_DIR/validation.js" << 'EOF'
const { formatError } = require('./formatting');

function validateUser(user) {
  if (!user) {
    return { valid: false, error: formatError('User object is required') };
  }
  
  if (!user.email) {
    return { valid: false, error: formatError('Email is required') };
  }
  
  if (!user.email.includes('@')) {
    return { valid: false, error: formatError('Email must contain @') };
  }
  
  return { valid: true };
}

function validateConfig(config) {
  if (!config || typeof config !== 'object') {
    return { valid: false, error: formatError('Config must be an object') };
  }
  return { valid: true };
}

module.exports = { validateUser, validateConfig };
EOF

# Create formatting.js (imports from database.js)
cat > "$SRC_DIR/formatting.js" << 'EOF'
const { getDatabaseConfig } = require('./database');

function formatError(message) {
  // This creates circular dependency - getDatabaseConfig needs validation
  const dbConfig = getDatabaseConfig();
  const prefix = dbConfig.errorPrefix || '[ERROR]';
  return `${prefix} ${message}`;
}

function formatSuccess(message) {
  return `[SUCCESS] ${message}`;
}

function formatWarning(message) {
  return `[WARNING] ${message}`;
}

module.exports = { formatError, formatSuccess, formatWarning };
EOF

# Create database.js (imports from validation.js - CREATES CYCLE!)
cat > "$SRC_DIR/database.js" << 'EOF'
const { validateConfig } = require('./validation');

function getDatabaseConfig() {
  // This creates the circular dependency
  const defaultConfig = {
    host: 'localhost',
    port: 5432,
    errorPrefix: '[DB-ERROR]'
  };
  
  // Validate the config (which needs formatting, which needs this function!)
  const validationResult = validateConfig(defaultConfig);
  
  if (!validationResult.valid) {
    console.error('Invalid database config');
  }
  
  return defaultConfig;
}

function connectDatabase() {
  const config = getDatabaseConfig();
  return { connected: true, config };
}

module.exports = { getDatabaseConfig, connectDatabase };
EOF

# Create constants.js (empty - solution target)
cat > "$SRC_DIR/constants.js" << 'EOF'
// Shared constants
// TODO: Extract shared constants here to break circular dependencies

module.exports = {};
EOF

# Create README for context
cat > "$SRC_DIR/README.md" << 'EOF'
# API Project Source

## Issue: Circular Dependency

The current module structure has a circular dependency:
