#!/bin/bash
# setup_task.sh for configure_canvas_extraction_exception
# Prepares the local HTML tool and resets any Tor Browser canvas permissions

set -e
echo "=== Setting up Canvas Extraction Exception Task ==="

TASK_NAME="configure_canvas_extraction_exception"

# 1. Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# 2. Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Found Tor Browser profile at: $PROFILE_DIR"
        break
    fi
done

# 3. Clear any existing canvas permissions to ensure a clean slate
if [ -n "$PROFILE_DIR" ]; then
    PERMS_DB="$PROFILE_DIR/permissions.sqlite"
    if [ -f "$PERMS_DB" ]; then
        echo "Clearing existing canvas permissions from database..."
        sqlite3 "$PERMS_DB" "DELETE FROM moz_perms WHERE type='canvas/extractData';" 2>/dev/null || true
    fi
    # Also clear history to prevent false positive history checks
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    if [ -f "$PLACES_DB" ]; then
        sqlite3 "$PLACES_DB" "DELETE FROM moz_historyvisits;" 2>/dev/null || true
    fi
fi

# 4. Create the target directory and the local HTML tool
WORK_DIR="/home/ga/Documents/OfflineTools"
sudo -u ga mkdir -p "$WORK_DIR"
rm -f "$WORK_DIR/exported_chart.txt" 2>/dev/null || true

HTML_PATH="$WORK_DIR/chart_tool.html"
cat > "$HTML_PATH" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Offline Investigation Chart Tool</title>
    <style>
        body { font-family: sans-serif; padding: 20px; background: #f0f0f0; }
        .container { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        canvas { border: 1px solid #ccc; margin-top: 10px; background: #fff; }
        button { padding: 10px 15px; background: #0052cc; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; margin: 15px 0; }
        button:hover { background: #003d99; }
        textarea { width: 100%; font-family: monospace; padding: 10px; box-sizing: border-box; }
        .warning { color: #d93025; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Link Analysis Chart Generator</h2>
        <p>Render complex relationship matrices for offline viewing.</p>
        <canvas id="analysisCanvas" width="800" height="400"></canvas>
        <br>
        <button id="exportBtn">Export Chart as Base64</button>
        <p class="warning" id="statusMsg"></p>
        <h3>Base64 Output:</h3>
        <textarea id="outputArea" rows="12" placeholder="Base64 image string will appear here..."></textarea>
    </div>

    <script>
        const canvas = document.getElementById('analysisCanvas');
        const ctx = canvas.getContext('2d');
        const outputArea = document.getElementById('outputArea');
        const statusMsg = document.getElementById('statusMsg');

        // Draw a complex, non-trivial canvas to ensure the resulting base64 string is large
        // A blank or simple canvas compresses too well and might falsely trip verifiers.
        ctx.fillStyle = '#2c3e50';
        ctx.fillRect(0, 0, 800, 400);
        
        ctx.fillStyle = '#ecf0f1';
        ctx.font = '24px Arial';
        ctx.fillText('CONFIDENTIAL INVESTIGATION MATRIX', 20, 40);
        
        // Draw nodes and links
        const nodes = [];
        for(let i = 0; i < 50; i++) {
            nodes.push({ x: 50 + Math.random() * 700, y: 80 + Math.random() * 300 });
        }
        
        ctx.strokeStyle = 'rgba(52, 152, 219, 0.5)';
        ctx.lineWidth = 1;
        for(let i = 0; i < nodes.length; i++) {
            for(let j = i+1; j < nodes.length; j++) {
                if(Math.random() > 0.9) {
                    ctx.beginPath();
                    ctx.moveTo(nodes[i].x, nodes[i].y);
                    ctx.lineTo(nodes[j].x, nodes[j].y);
                    ctx.stroke();
                }
            }
        }
        
        ctx.fillStyle = '#e74c3c';
        for(let node of nodes) {
            ctx.beginPath();
            ctx.arc(node.x, node.y, 6, 0, Math.PI * 2);
            ctx.fill();
        }

        document.getElementById('exportBtn').addEventListener('click', () => {
            try {
                // Tor Browser will intercept this if canvas extraction is not explicitly allowed
                const dataURL = canvas.toDataURL('image/png');
                outputArea.value = dataURL;
                
                // Tor's blanked canvas is usually very short
                if(dataURL.length < 500) {
                    statusMsg.textContent = "Warning: Extracted data is unusually small. Did Tor Browser block the canvas extraction?";
                } else {
                    statusMsg.textContent = "Success: Extracted " + dataURL.length + " bytes of base64 data.";
                    statusMsg.style.color = "green";
                }
            } catch(e) {
                statusMsg.textContent = "Error extracting canvas data: " + e.message;
            }
        });
    </script>
</body>
</html>
EOF

chown -R ga:ga "$WORK_DIR"
echo "Created HTML chart tool at: $HTML_PATH"

# 5. Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# 6. Find and launch Tor Browser
TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        break
    fi
done

echo "Launching Tor Browser..."
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for process to start
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        echo "Tor Browser process started."
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection so it's ready for the user
echo "Waiting for Tor network connection..."
ELAPSED=0
TIMEOUT=300
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting"; then
        echo "Tor Browser is connected/ready."
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Initial Screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup Complete ==="