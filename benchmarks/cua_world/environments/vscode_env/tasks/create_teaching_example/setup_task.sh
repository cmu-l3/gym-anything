#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Teaching Example Task ==="

USER="ga"
WORKSPACE="/home/ga/workspace"
MATERIAL_DIR="$WORKSPACE/teaching-materials"
PRODUCTION_DIR="$WORKSPACE/production-code"

# Create teaching materials directory
sudo -u $USER mkdir -p "$MATERIAL_DIR"
sudo -u $USER mkdir -p "$PRODUCTION_DIR"

# Create a README with context
cat > "$MATERIAL_DIR/README.md" << 'EOF'
# Teaching Materials

This folder contains examples for coding bootcamp sessions.

## Upcoming Sessions

### Tomorrow: Understanding Async/Await in JavaScript
- **Audience**: Students who just learned basic Promises
- **Duration**: 30 minutes
- **Goal**: Show evolution from callbacks → Promises → async/await
- **Requirements**: 
  - Single file, self-contained
  - Realistic scenario (API fetching)
  - Runnable with Node.js
  - Heavy commenting for beginners
  - Shows execution flow with console output

## To-Do
- [ ] Create async/await demonstration file
- [ ] Ensure no external dependencies
- [ ] Add detailed comments explaining "why"
- [ ] Test that it runs successfully

## Notes
- Students get confused by too many concepts at once
- Keep examples realistic but simple
- Always explain the "why" behind patterns
- Show output so students can see what happens
EOF

sudo chown -R ga:ga "$MATERIAL_DIR"

# Create scattered production code (to simulate existing codebase)
cat > "$PRODUCTION_DIR/api-client.js" << 'EOF'
// Production API client - TOO COMPLEX for teaching
const https = require('https');
const auth = require('./auth');
const logger = require('./logger');
const retry = require('./retry');

class APIClient {
  constructor(config) {
    this.baseUrl = config.baseUrl;
    this.timeout = config.timeout || 5000;
    this.retries = config.retries || 3;
  }
  
  async fetchUser(id) {
    // Complex production code with auth, retries, logging
    const token = await auth.getToken();
    const result = await retry.withBackoff(async () => {
      return await this._makeRequest(`/users/${id}`, token);
    }, this.retries);
    
    logger.info('User fetched', { userId: id });
    return result;
  }
  
  async _makeRequest(path, token) {
    // Implementation with auth headers, error handling, etc.
    // ... lots more complexity ...
  }
}

module.exports = APIClient;
EOF

cat > "$PRODUCTION_DIR/callback-example.js" << 'EOF'
// Old production code using callbacks
const https = require('https');

function fetchData(url, callback) {
  https.get(url, (res) => {
    let data = '';
    res.on('data', (chunk) => { data += chunk; });
    res.on('end', () => { callback(null, data); });
  }).on('error', (err) => { callback(err); });
}

// This is buried in production code - not suitable for teaching
EOF

sudo chown -R ga:ga "$PRODUCTION_DIR"

# Create a simple placeholder to show "work in progress"
cat > "$MATERIAL_DIR/.gitkeep" << 'EOF'
# Placeholder - create your teaching example here
EOF

sudo chown -R ga:ga "$MATERIAL_DIR"

# Open VSCode in the teaching-materials directory
echo "Opening VSCode in teaching-materials directory..."
su - ga -c "DISPLAY=:1 code '$MATERIAL_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the README to provide context
sleep 1
su - ga -c "DISPLAY=:1 code '$MATERIAL_DIR/README.md'" || true
sleep 2

echo "=== Create Teaching Example Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read the README.md for context about tomorrow's bootcamp session"
echo "  2. Create a new file: async-await-demo.js"
echo "  3. Write a self-contained teaching example showing:"
echo "     - Callback-based approach (callback hell)"
echo "     - Promise-based approach (.then())"
echo "     - Async/await approach (modern)"
echo "  4. Add educational comments explaining WHY, not just WHAT"
echo "  5. Include console.log statements to show execution flow"
echo "  6. Use only Node.js built-ins (https module)"
echo "  7. Fetch user data from: https://jsonplaceholder.typicode.com/users/1"
echo "  8. Save the file (Ctrl+S)"
echo ""
echo "📁 Context files:"
echo "  - README.md: Session requirements and context"
echo "  - ../production-code/: Examples of existing code (too complex for teaching)"