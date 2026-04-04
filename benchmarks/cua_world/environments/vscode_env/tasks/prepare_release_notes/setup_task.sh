#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Release Notes Task ==="

WORKSPACE_DIR="/home/ga/workspace/webapp"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Initialize Git repository
sudo -u ga git init
sudo -u ga git config user.name "Developer"
sudo -u ga git config user.email "dev@example.com"

echo "Creating initial project structure..."

# Create initial project files
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "webapp",
  "version": "1.5.0",
  "description": "Sample web application"
}
EOF

sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

cat > "$WORKSPACE_DIR/src/auth.js" << 'EOF'
// Authentication module
function login(username, password) {
  return { token: "mock-token" };
}
EOF

cat > "$WORKSPACE_DIR/src/api.js" << 'EOF'
// API client
function fetchData(endpoint) {
  return fetch(endpoint);
}
EOF

cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# WebApp
A sample web application.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initial commit and tag v1.5.0
cd "$WORKSPACE_DIR"
sudo -u ga git add -A
sudo -u ga git commit -m "Initial commit: v1.5.0 release"
sudo -u ga git tag v1.5.0

echo "Simulating development commits since v1.5.0..."

# Feature 1: Dark mode
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"
cat > "$WORKSPACE_DIR/src/components/theme.js" << 'EOF'
export function enableDarkMode() {
  document.body.classList.add('dark-mode');
}
EOF
sudo chown -R ga:ga "$WORKSPACE_DIR/src/components"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/components/theme.js
sudo -u ga git commit -m "feat: Add dark mode support for UI"

# Internal refactor (should be filtered out)
sed -i 's/mock-token/generated-token/g' "$WORKSPACE_DIR/src/auth.js"
cd "$WORKSPACE_DIR"
sudo -u ga git add src/auth.js
sudo -u ga git commit -m "refactor: Improve token generation logic"

# Bug fix
cat >> "$WORKSPACE_DIR/src/auth.js" << 'EOF'

// Fix: Handle null username
function validateUser(username) {
  if (!username) throw new Error("Username required");
}
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add src/auth.js
sudo -u ga git commit -m "fix: Prevent crash when username is null"

# Feature 2: Export functionality
cat > "$WORKSPACE_DIR/src/export.js" << 'EOF'
export function exportToCSV(data) {
  return data.map(row => row.join(',')).join('\n');
}
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add src/export.js
sudo -u ga git commit -m "Add CSV export feature"

# Test update (should be filtered out)
cat > "$WORKSPACE_DIR/tests/auth.test.js" << 'EOF'
// Test suite for auth
test('login works', () => {
  expect(login('user', 'pass')).toBeDefined();
});
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add tests/auth.test.js
sudo -u ga git commit -m "test: Add auth module tests"

# Breaking change: API signature change
sed -i 's/fetchData(endpoint)/fetchData(endpoint, options = {})/g' "$WORKSPACE_DIR/src/api.js"
cat >> "$WORKSPACE_DIR/src/api.js" << 'EOF'

// Now requires options parameter
function get(url, options) {
  return fetchData(url, options);
}
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add src/api.js
sudo -u ga git commit -m "BREAKING: Change API.fetchData signature to require options parameter"

# Feature 3: Batch operations
cat > "$WORKSPACE_DIR/src/batch.js" << 'EOF'
export function batchProcess(items, processor) {
  return items.map(processor);
}
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add src/batch.js
sudo -u ga git commit -m "feat: Implement batch processing for bulk operations"

# Bug fix: Memory leak
cat > "$WORKSPACE_DIR/src/utils.js" << 'EOF'
// Fix memory leak by clearing cache
let cache = {};
export function clearCache() {
  cache = {};
}
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add src/utils.js
sudo -u ga git commit -m "Fix memory leak in cache management"

# Dependency bump (should be filtered out)
sed -i 's/"version": "1.5.0"/"version": "2.0.0-beta"/g' "$WORKSPACE_DIR/package.json"
cd "$WORKSPACE_DIR"
sudo -u ga git add package.json
sudo -u ga git commit -m "chore: Bump version to 2.0.0-beta"

# Feature 4: Keyboard shortcuts
cat > "$WORKSPACE_DIR/src/shortcuts.js" << 'EOF'
export function registerShortcut(key, callback) {
  document.addEventListener('keydown', (e) => {
    if (e.key === key) callback();
  });
}
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add src/shortcuts.js
sudo -u ga git commit -m "Add keyboard shortcuts support"

# Bug fix: Edge case
cat >> "$WORKSPACE_DIR/src/export.js" << 'EOF'

// Handle empty data
export function safeExport(data) {
  return data.length > 0 ? exportToCSV(data) : '';
}
EOF
cd "$WORKSPACE_DIR"
sudo -u ga git add src/export.js
sudo -u ga git commit -m "fix: Handle empty data in CSV export"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode to workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Prepare Release Notes Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Source Control panel (Ctrl+Shift+G) or use Git History"
echo "  2. Review commits since tag v1.5.0 (about 12 commits)"
echo "  3. Identify user-facing changes (features, bug fixes, breaking changes)"
echo "  4. Filter out internal changes (refactors, tests, dependency bumps)"
echo "  5. Create CHANGELOG.md at /home/ga/workspace/webapp/CHANGELOG.md"
echo "  6. Organize into sections: Features, Bug Fixes, Breaking Changes"
echo "  7. Save the file"
echo ""
echo "Repository: $WORKSPACE_DIR"
echo "Current tag: v1.5.0"
echo "Target version: 2.0.0"