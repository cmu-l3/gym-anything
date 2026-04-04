#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Flaky Test Retry Task ==="

WORKSPACE_DIR="/home/ga/workspace/flaky-test-project"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests" "$WORKSPACE_DIR/src"

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "flaky-test-project",
  "version": "1.0.0",
  "description": "Project with flaky tests that need retry configuration",
  "scripts": {
    "test": "jest"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  }
}
EOF

# Create basic jest.config.js (no retry configuration yet)
cat > "$WORKSPACE_DIR/jest.config.js" << 'EOF'
module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/tests/**/*.test.js'],
  verbose: true,
  collectCoverage: false
};
EOF

# Create source file with API functions
cat > "$WORKSPACE_DIR/src/api.js" << 'EOF'
// API module with functions that are tested
async function fetchUserData(userId) {
  // Simulated API call that sometimes times out
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({ 
        id: userId, 
        name: 'User ' + userId,
        email: 'user' + userId + '@example.com'
      });
    }, 100);
  });
}

async function processWebhook(payload) {
  // Simulated webhook processing that sometimes fails
  return new Promise((resolve, reject) => {
    const random = Math.random();
    setTimeout(() => {
      if (random > 0.1) {  // 90% success rate
        resolve({ status: 'processed', payload: payload });
      } else {
        reject(new Error('Random processing failure'));
      }
    }, 50);
  });
}

function sanitizeInput(input) {
  // Simple synchronous function
  return input.trim().toLowerCase();
}

module.exports = { 
  fetchUserData, 
  processWebhook, 
  sanitizeInput 
};
EOF

# Create test file with flaky tests (no retry configuration yet)
cat > "$WORKSPACE_DIR/tests/api.test.js" << 'EOF'
const { fetchUserData, processWebhook, sanitizeInput } = require('../src/api');

describe('API Tests', () => {
  test('fetchUserData returns user object', async () => {
    const user = await fetchUserData(123);
    expect(user).toHaveProperty('id', 123);
    expect(user).toHaveProperty('name');
    expect(user).toHaveProperty('email');
  }, 5000); // Original 5s timeout - too short for flaky behavior!
  
  test('processWebhook handles payload', async () => {
    const result = await processWebhook({ event: 'user.created', data: { id: 1 } });
    expect(result).toHaveProperty('status', 'processed');
    expect(result.payload).toHaveProperty('event', 'user.created');
  });
  
  test('sanitizeInput trims and lowercases', () => {
    expect(sanitizeInput('  HELLO  ')).toBe('hello');
    expect(sanitizeInput('World')).toBe('world');
  });
  
  test('stable test - always passes', () => {
    expect(1 + 1).toBe(2);
    expect(true).toBe(true);
  });
});
EOF

# Create a README for context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Flaky Test Project

This project has a Jest test suite with some flaky tests that need configuration improvements.

## Known Issues

- `fetchUserData` test occasionally times out
- `processWebhook` test fails randomly due to async timing

## Task

Configure Jest to handle these flaky tests by:
1. Adding retry logic
2. Increasing timeouts
3. Adding better logging
4. Documenting the flaky tests
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the project
echo "Opening VSCode with flaky-test-project..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Configure Flaky Test Retry Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open jest.config.js and add retry configuration (e.g., retries: 2)"
echo "  2. Open tests/api.test.js and modify:"
echo "     - Increase fetchUserData test timeout to 10000ms"
echo "     - Add retry logic to processWebhook test (jest.retryTimes(2))"
echo "     - Add console.log to track retry attempts"
echo "  3. Create FLAKY_TESTS.md to document the changes"
echo "  4. Save all files (Ctrl+S)"