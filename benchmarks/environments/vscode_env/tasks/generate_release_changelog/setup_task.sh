#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Generate Release Changelog Task ==="

WORKSPACE_DIR="/home/ga/workspace/sample-project"

# Clean up any existing directory
if [ -d "$WORKSPACE_DIR" ]; then
    sudo rm -rf "$WORKSPACE_DIR"
fi

sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Initialize Git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "Test User"
sudo -u ga git config user.email "test@example.com"

echo "Creating initial commits (before v2.0.0)..."

# Initial commit
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Sample Project

A sample application for release management.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add README.md
sudo -u ga git commit -m "Initial commit"

# Add basic structure
sudo -u ga mkdir -p src
cat > "$WORKSPACE_DIR/src/app.js" << 'EOF'
// Main application
function hello() {
    console.log('Hello World');
}

module.exports = { hello };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/app.js
sudo -u ga git commit -m "Add basic app structure"

# Tag v2.0.0
sudo -u ga git tag -a v2.0.0 -m "Release v2.0.0"

echo "Creating commits after v2.0.0 (these should appear in changelog)..."

# Feature commits
cat > "$WORKSPACE_DIR/src/auth.js" << 'EOF'
// Authentication module
function authenticate(user, password) {
    // OAuth2 implementation
    return { token: 'abc123', user: user };
}

module.exports = { authenticate };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/auth.js
sudo -u ga git commit -m "feat: Add user authentication with OAuth2 support"

cat > "$WORKSPACE_DIR/src/upload.js" << 'EOF'
// File upload module
function uploadFile(file) {
    // Upload with progress tracking
    console.log('Uploading:', file);
    return { progress: 100, status: 'complete' };
}

module.exports = { uploadFile };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/upload.js
sudo -u ga git commit -m "feature: Implement file upload with progress tracking"

# Bug fix commits
cat > "$WORKSPACE_DIR/src/websocket.js" << 'EOF'
// WebSocket module
let connections = new WeakMap(); // Fixed memory leak

function connect(url) {
    const ws = new WebSocket(url);
    connections.set(ws, { url, active: true });
    return ws;
}

module.exports = { connect };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/websocket.js
sudo -u ga git commit -m "fix: Fix memory leak in WebSocket connections"

cat > "$WORKSPACE_DIR/src/date-utils.js" << 'EOF'
// Date utilities
function parseDate(dateString) {
    // Properly handle timezone
    return new Date(dateString + 'Z');
}

module.exports = { parseDate };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/date-utils.js
sudo -u ga git commit -m "Fix timezone handling for date pickers"

# Noise commits (should be filtered out)
sudo -u ga git commit --allow-empty -m "wip"
sudo -u ga git commit --allow-empty -m "merge branch feature-xyz into main"
sudo -u ga git commit --allow-empty -m "typo in readme"
sudo -u ga git commit --allow-empty -m "fix formatting"

# Chore commits
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "sample-project",
  "version": "2.1.0",
  "dependencies": {
    "express": "^4.18.0",
    "lodash": "^4.17.21"
  }
}
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add package.json
sudo -u ga git commit -m "chore: Update dependencies to latest versions"

cat > "$WORKSPACE_DIR/src/api-client.js" << 'EOF'
// API client (refactored)
class ApiClient {
    constructor(baseUrl) {
        this.baseUrl = baseUrl;
    }
    
    async request(endpoint) {
        try {
            const response = await fetch(this.baseUrl + endpoint);
            return await response.json();
        } catch (error) {
            console.error('API Error:', error);
            throw error;
        }
    }
}

module.exports = ApiClient;
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/api-client.js
sudo -u ga git commit -m "refactor: Refactor API client for better error handling"

# Breaking change commit
cat > "$WORKSPACE_DIR/src/api-schema.js" << 'EOF'
// API v2 schema
const responseSchema = {
    version: 2,
    data: {},
    meta: { timestamp: Date.now() }
};

module.exports = { responseSchema };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/api-schema.js
sudo -u ga git commit -m "BREAKING CHANGE: Change API response format to v2 schema"

# Add one more feature
cat > "$WORKSPACE_DIR/src/notifications.js" << 'EOF'
// Notifications module
function sendNotification(user, message) {
    console.log('Notification sent:', message);
}

module.exports = { sendNotification };
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/notifications.js
sudo -u ga git commit -m "feat: Add push notification system"

echo "Repository setup complete with $(sudo -u ga git rev-list v2.0.0..HEAD --count) commits since v2.0.0"

# Open VSCode with the repository
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Generate Release Changelog Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Navigate git history between v2.0.0 and HEAD"
echo "  2. Extract and categorize commits"
echo "  3. Create CHANGELOG.md in repository root"
echo "  4. Include sections: Features, Bug Fixes, Breaking Changes, Chores"
echo "  5. Filter out noise commits (wip, merge, typo)"
echo "  6. Save the file"
echo ""
echo "Repository location: $WORKSPACE_DIR"
echo "Git tags: $(cd $WORKSPACE_DIR && sudo -u ga git tag -l)"
echo "Commits since v2.0.0: $(cd $WORKSPACE_DIR && sudo -u ga git rev-list v2.0.0..HEAD --count)"