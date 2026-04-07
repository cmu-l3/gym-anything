#!/bin/bash
set -e
echo "=== Setting up MV3 Migration Task ==="

source /workspace/scripts/task_utils.sh || true

WORKSPACE_DIR="/home/ga/workspace/price_tracker_ext"
SERVER_DIR="/home/ga/workspace/server"

sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$SERVER_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─────────────────────────────────────────────────────────────
# 1. Create the Mock API Server
# ─────────────────────────────────────────────────────────────
cat > "$SERVER_DIR/server.js" << 'EOF'
const http = require('http');

const server = http.createServer((req, res) => {
    // CORS headers for the extension
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');

    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }

    if (req.url === '/api/deal' && req.method === 'GET') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            success: true,
            discount: '25%', 
            price: '$59.99',
            originalPrice: '$79.99',
            expires: new Date(Date.now() + 86400000).toISOString()
        }));
    } else {
        res.writeHead(404);
        res.end(JSON.stringify({ error: 'Not Found' }));
    }
});

server.listen(3000, () => {
    console.log('Mock Deal API running on http://localhost:3000');
});
EOF

chown -R ga:ga "$SERVER_DIR"

# Start the mock server in the background
sudo -u ga node "$SERVER_DIR/server.js" > /tmp/mock_api.log 2>&1 &

# ─────────────────────────────────────────────────────────────
# 2. Create the Buggy Extension Code (MV2 -> MV3 transitional)
# ─────────────────────────────────────────────────────────────

# BUG 1 & BUG 2: Invalid background scripts array and invalid permissions array for MV3
cat > "$WORKSPACE_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "Price Tracker & Deal Finder",
  "version": "1.0",
  "description": "Finds the best deals automatically.",
  "background": {
    "scripts": ["background.js"]
  },
  "permissions": [
    "storage",
    "activeTab",
    "http://localhost:3000/*"
  ],
  "action": {
    "default_popup": "popup.html"
  }
}
EOF

# BUG 3, 4, 5: XHR, Missing return true, Ephemeral global state
cat > "$WORKSPACE_DIR/background.js" << 'EOF'
// Price Tracker Background Script

// BUG 5: Global state is ephemeral in MV3 service workers. 
// When the browser puts the service worker to sleep, this resets to false.
let isTrackingActive = false;

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("Received message:", request.action);

    if (request.action === "toggleTracking") {
        isTrackingActive = !isTrackingActive;
        sendResponse({ active: isTrackingActive });
    }

    if (request.action === "getDeal") {
        if (!isTrackingActive) {
            sendResponse({ error: "Tracking is currently disabled" });
            return; // BUG 4: Missing 'return true;' here and at the end of this block prevents async sendResponse
        }

        // BUG 3: XMLHttpRequest is undefined in Manifest V3 Service Workers. 
        // Must be refactored to use the modern fetch() API.
        try {
            let xhr = new XMLHttpRequest();
            xhr.open("GET", "http://localhost:3000/api/deal", true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                    if (xhr.status === 200) {
                        let data = JSON.parse(xhr.responseText);
                        sendResponse({ deal: data });
                    } else {
                        sendResponse({ error: "API request failed with status " + xhr.status });
                    }
                }
            };
            xhr.send();
        } catch (e) {
            console.error("XHR Error:", e);
            sendResponse({ error: e.toString() });
        }
        
        // In Manifest V3, you MUST return true from the onMessage listener 
        // to indicate that you will send a response asynchronously.
    }
});
EOF

cat > "$WORKSPACE_DIR/popup.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Price Tracker</title>
    <style>
        body { width: 250px; font-family: Arial, sans-serif; padding: 10px; }
        button { width: 100%; padding: 10px; margin-top: 10px; cursor: pointer; }
        #dealInfo { margin-top: 15px; font-size: 14px; color: green; }
    </style>
</head>
<body>
    <h3>Price Tracker</h3>
    <div id="status">Tracking: <b id="trackStatus">Disabled</b></div>
    <button id="toggleBtn">Toggle Tracking</button>
    <button id="fetchBtn">Check for Deals</button>
    <div id="dealInfo"></div>
    <script src="popup.js"></script>
</body>
</html>
EOF

cat > "$WORKSPACE_DIR/popup.js" << 'EOF'
document.getElementById('toggleBtn').addEventListener('click', () => {
    chrome.runtime.sendMessage({ action: "toggleTracking" }, (response) => {
        document.getElementById('trackStatus').innerText = response.active ? "Enabled" : "Disabled";
    });
});

document.getElementById('fetchBtn').addEventListener('click', () => {
    document.getElementById('dealInfo').innerText = "Loading...";
    chrome.runtime.sendMessage({ action: "getDeal" }, (response) => {
        if (chrome.runtime.lastError) {
            document.getElementById('dealInfo').innerText = "Error: " + chrome.runtime.lastError.message;
            return;
        }
        if (response.error) {
            document.getElementById('dealInfo').innerText = response.error;
            document.getElementById('dealInfo').style.color = 'red';
        } else if (response.deal) {
            document.getElementById('dealInfo').innerText = 
                `Discount: ${response.deal.discount}\nPrice: ${response.deal.price}`;
            document.getElementById('dealInfo').style.color = 'green';
        }
    });
});
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 3. Setup VS Code
# ─────────────────────────────────────────────────────────────
# Ensure VSCode is running
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Open the critical files in the editor
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/manifest.json $WORKSPACE_DIR/background.js" 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="