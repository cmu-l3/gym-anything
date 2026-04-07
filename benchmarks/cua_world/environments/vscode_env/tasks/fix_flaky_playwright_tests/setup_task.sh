#!/bin/bash
set -e
echo "=== Setting up Fix Flaky Playwright Tests Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/e2e_testing"
mkdir -p "$WORKSPACE_DIR/tests"
mkdir -p "$WORKSPACE_DIR/server"

# 1. Create package.json and Playwright config
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "e2e_testing",
  "version": "1.0.0",
  "scripts": {
    "test": "playwright test",
    "start": "node server/app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "@playwright/test": "^1.40.0"
  }
}
EOF

cat > "$WORKSPACE_DIR/playwright.config.js" << 'EOF'
const { defineConfig } = require('@playwright/test');
module.exports = defineConfig({
  testDir: './tests',
  timeout: 15000,
  expect: { timeout: 8000 },
  use: {
    browserName: 'chromium',
    headless: true,
  },
});
EOF

# 2. Create the Backend Server (injects latency and logs events for anti-gaming verification)
cat > "$WORKSPACE_DIR/server/app.js" << 'EOF'
const express = require('express');
const fs = require('fs');
const app = express();

app.use(express.json());

const MAX_LATENCY = parseInt(process.env.MAX_LATENCY || 2000);

const logActivity = (evt) => {
    fs.appendFileSync('/tmp/server_activity.log', evt + '\n');
};

const randomDelay = () => new Promise(r => setTimeout(r, Math.random() * MAX_LATENCY));
const fixedDelay = () => new Promise(r => setTimeout(r, MAX_LATENCY));

// Auth (Missing Await trap)
app.get('/login', (req, res) => res.send(`
    <button id="login-btn" onclick="fetch('/api/login', {method:'POST'}).then(() => document.body.innerHTML += '<div class=\\'success-msg\\'>Success</div>')">Login</button>
`));
app.post('/api/login', async (req, res) => {
    await randomDelay();
    logActivity('LOGIN_SUCCESS');
    res.json({ok: true});
});

// Checkout (Hardcoded timeout trap)
app.get('/checkout', (req, res) => res.send(`
    <button id="pay-btn" onclick="fetch('/api/checkout', {method:'POST'}).then(() => document.body.innerHTML += '<div class=\\'payment-success\\'>Paid</div>')">Pay</button>
`));
app.post('/api/checkout', async (req, res) => {
    await fixedDelay(); 
    logActivity('PAYMENT_PROCESSED');
    res.json({ok: true});
});

// Search (Race condition trap)
app.get('/search', (req, res) => res.send(`
    <input id="search-box" oninput="fetch('/api/search', {method:'POST'}).then(() => document.body.innerHTML += '<div class=\\'movie-card\\'>Movie</div>')" />
`));
app.post('/api/search', async (req, res) => {
    await randomDelay();
    logActivity('SEARCH_EXECUTED');
    res.json({ok: true});
});

// Video (Iframe trap)
app.get('/video', (req, res) => res.send(`
    <iframe id="player-frame" src="/video-inner"></iframe>
`));
app.get('/video-inner', (req, res) => res.send(`
    <button class="play-btn" onclick="fetch('/api/video', {method:'POST'})">Play</button>
`));
app.post('/api/video', async (req, res) => {
    await randomDelay();
    logActivity('VIDEO_PLAYED');
    res.json({ok: true});
});

// Profile (Strict mode violation trap)
app.get('/profile', (req, res) => res.send(`
    <div class="address"><button class="delete-address-btn" onclick="fetch('/api/profile', {method:'DELETE'})">Delete</button></div>
    <button id="add-address" onclick="document.body.innerHTML += '<div class=\\'address\\'><button class=\\'delete-address-btn\\' onclick=\\'fetch(\\'/api/profile\\', {method:\\'DELETE\\'})\\'>Delete</button></div>'">Add</button>
`));
app.delete('/api/profile', async (req, res) => {
    await randomDelay();
    logActivity('ADDRESS_DELETED');
    res.json({ok: true});
});

app.listen(3000, () => console.log('Mock Server running on port 3000'));
EOF

# 3. Create the 5 Flaky Tests
cat > "$WORKSPACE_DIR/tests/auth.spec.js" << 'EOF'
const { test, expect } = require('@playwright/test');

test('User can login successfully', async ({ page }) => {
    await page.goto('http://localhost:3000/login');
    
    // BUG: Missing await on click. Causes race condition evaluating isVisible immediately
    page.locator('#login-btn').click(); 
    
    const isVisible = await page.locator('.success-msg').isVisible();
    expect(isVisible).toBeTruthy();
});
EOF

cat > "$WORKSPACE_DIR/tests/checkout.spec.js" << 'EOF'
const { test, expect } = require('@playwright/test');

test('User can process payment', async ({ page }) => {
    await page.goto('http://localhost:3000/checkout');
    await page.locator('#pay-btn').click();
    
    // BUG: Hardcoded timeout will fail on slower networks
    await page.waitForTimeout(1500); 
    
    const isVisible = await page.locator('.payment-success').isVisible();
    expect(isVisible).toBeTruthy();
});
EOF

cat > "$WORKSPACE_DIR/tests/search.spec.js" << 'EOF'
const { test, expect } = require('@playwright/test');

test('Search returns valid results', async ({ page }) => {
    await page.goto('http://localhost:3000/search');
    await page.fill('#search-box', 'Batman');
    
    // BUG: Race condition. Doesn't wait for API response or DOM to update
    const count = await page.locator('.movie-card').count();
    expect(count).toBeGreaterThan(0);
});
EOF

cat > "$WORKSPACE_DIR/tests/video_player.spec.js" << 'EOF'
const { test, expect } = require('@playwright/test');

test('User can play video', async ({ page }) => {
    await page.goto('http://localhost:3000/video');
    
    // BUG: The play button is inside an iframe. Direct locator will fail.
    await page.locator('.play-btn').click();
});
EOF

cat > "$WORKSPACE_DIR/tests/profile.spec.js" << 'EOF'
const { test, expect } = require('@playwright/test');

test('User can delete a newly added address', async ({ page }) => {
    await page.goto('http://localhost:3000/profile');
    
    // Add a second address to the profile
    await page.locator('#add-address').click();
    
    // BUG: Strict mode violation. Two '.delete-address-btn' elements now exist
    await page.locator('.delete-address-btn').click();
});
EOF

# 4. Install dependencies
echo "Installing Node.js packages and Playwright browsers..."
cd "$WORKSPACE_DIR"
npm install
npx playwright install-deps chromium
sudo -u ga npx playwright install chromium

chown -R ga:ga "$WORKSPACE_DIR"

# 5. Start the backend server with standard latency
rm -f /tmp/server_activity.log
sudo -u ga MAX_LATENCY=2000 node server/app.js > /tmp/server.log 2>&1 &
echo $! > /tmp/server.pid
sleep 3

# 6. Launch VS Code
if ! pgrep -f "code.*--ms-enable-electron" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="