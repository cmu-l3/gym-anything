#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Environment Switcher Configuration Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-service"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{scripts,.vscode}

cd "$WORKSPACE_DIR"

# Create environment configuration files
echo "Creating environment configuration files..."

cat > "$WORKSPACE_DIR/.env.development" << 'EOF'
NODE_ENV=development
DATABASE_URL=postgresql://localhost:5432/dev_db
API_KEY=dev_key_12345
LOG_LEVEL=debug
REDIS_URL=redis://localhost:6379
EOF

cat > "$WORKSPACE_DIR/.env.staging" << 'EOF'
NODE_ENV=staging
DATABASE_URL=postgresql://staging-db.example.com:5432/staging_db
API_KEY=staging_key_67890
LOG_LEVEL=info
REDIS_URL=redis://staging-redis.example.com:6379
EOF

cat > "$WORKSPACE_DIR/.env.production" << 'EOF'
NODE_ENV=production
DATABASE_URL=postgresql://prod-db.example.com:5432/prod_db
API_KEY=prod_key_ABCDEF_SENSITIVE
LOG_LEVEL=error
REDIS_URL=redis://prod-redis.example.com:6379
EOF

# Set default environment to development
cp "$WORKSPACE_DIR/.env.development" "$WORKSPACE_DIR/.env"

# Create package.json for Node.js project
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "api-service",
  "version": "1.0.0",
  "description": "Backend API service with multiple environments",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "dotenv": "^16.0.0",
    "express": "^4.18.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.0"
  }
}
EOF

# Create sample server.js that uses environment variables
cat > "$WORKSPACE_DIR/server.js" << 'EOF'
require('dotenv').config();

const express = require('express');
const app = express();

const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';
const DATABASE_URL = process.env.DATABASE_URL;

console.log(`Starting server in ${NODE_ENV} mode`);
console.log(`Database: ${DATABASE_URL}`);

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    environment: NODE_ENV,
    database: DATABASE_URL
  });
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
EOF

# Create README with environment information
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# API Service

Backend API service for handling customer requests.

## Environments

This service connects to three different environments:

- **Development**: Local testing environment with safe test data
- **Staging**: Pre-production environment for integration testing
- **Production**: ⚠️ **LIVE DATA** - Production database with real customer data

## Configuration

Environment configuration is managed through `.env` files:
- `.env.development` - Development environment settings
- `.env.staging` - Staging environment settings  
- `.env.production` - Production environment settings

The active environment is determined by the `.env` file (symlink or copy).

## ⚠️ Important Safety Notice

**Never run database migrations, seed scripts, or destructive operations against production without explicit verification!**

Last incident: A team member accidentally ran a migration against production on 2024-01-15, causing a 2-hour outage. We need a safer way to switch environments.

## TODO

Set up a safe environment switching system with:
1. Visual indicators showing current environment
2. VSCode tasks for quick switching
3. Confirmation required for production operations
EOF

# Create .gitignore
cat > "$WORKSPACE_DIR/.gitignore" << 'EOF'
.env
.env.local
node_modules/
*.log
.DS_Store
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

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

echo "=== Environment Switcher Configuration Task Setup Complete ==="
echo "📝 Task Instructions:"
echo ""
echo "Your goal is to create a safe environment switching system:"
echo ""
echo "1. Create .vscode/tasks.json with three tasks:"
echo "   - Switch to Development"
echo "   - Switch to Staging"
echo "   - Switch to Production"
echo ""
echo "2. Create switching script (scripts/switch-env.sh or scripts/switch_env.py):"
echo "   - Accept environment argument (dev/staging/prod)"
echo "   - Copy .env.{environment} to .env"
echo "   - Require confirmation for production (e.g., 'CONFIRM PRODUCTION')"
echo "   - Update VSCode settings with status bar color"
echo ""
echo "3. Configure .vscode/settings.json:"
echo "   - Add statusBar.background color"
echo "   - Add window.title with environment name"
echo ""
echo "4. (Optional) Add .vscode/extensions.json with dotenv extension recommendation"
echo ""
echo "Files present in workspace:"
echo "  - .env.development, .env.staging, .env.production"
echo "  - .env (currently set to development)"
echo "  - package.json, server.js, README.md"