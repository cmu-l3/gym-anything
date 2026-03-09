#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network HAR Export Task Setup ==="
echo "Task: Capture network traffic with DevTools and export as HAR file"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create demo website with multiple resources
echo "Creating demo website with multiple resources..."
DEMO_DIR="/tmp/har_demo_site"
mkdir -p "$DEMO_DIR"

# Create main HTML file
cat > "$DEMO_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Traffic Demo - HAR Export Practice</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>Network Traffic Demonstration Page</h1>
        <p>This page loads multiple resources to generate network traffic for HAR export practice.</p>
        
        <div class="content">
            <h2>What is HAR?</h2>
            <p>HTTP Archive (HAR) format is a JSON-formatted archive file format for logging web browser's interaction with a site.</p>
            
            <h2>Resources Loaded</h2>
            <ul>
                <li>HTML document (this page)</li>
                <li>CSS stylesheet</li>
                <li>JavaScript file</li>
                <li>External image (placeholder)</li>
                <li>JSON data file</li>
            </ul>
            
            <div class="image-section">
                <h3>Sample Image</h3>
                <img src="https://via.placeholder.com/300x200/3498db/ffffff?text=Demo+Image" alt="Demo image" />
            </div>
        </div>
        
        <div class="data-section" id="data-section">
            <h3>Loaded Data</h3>
            <p>JavaScript will load and display data here...</p>
        </div>
    </div>
    
    <script src="script.js"></script>
</body>
</html>
EOF

# Create CSS file
cat > "$DEMO_DIR/styles.css" << 'EOF'
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    line-height: 1.6;
    margin: 0;
    padding: 0;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
}

.container {
    max-width: 900px;
    margin: 0 auto;
    padding: 40px 20px;
    background: white;
    min-height: 100vh;
}

h1 {
    color: #2c3e50;
    border-bottom: 3px solid #3498db;
    padding-bottom: 10px;
    margin-bottom: 20px;
}

h2 {
    color: #34495e;
    margin-top: 30px;
}

h3 {
    color: #7f8c8d;
}

.content {
    background: #ecf0f1;
    padding: 20px;
    border-radius: 8px;
    margin: 20px 0;
}

ul {
    list-style-type: none;
    padding-left: 0;
}

ul li {
    padding: 8px 0;
    border-bottom: 1px solid #bdc3c7;
}

ul li:before {
    content: "✓ ";
    color: #27ae60;
    font-weight: bold;
    margin-right: 10px;
}

.image-section {
    margin: 30px 0;
    text-align: center;
}

.image-section img {
    max-width: 100%;
    border-radius: 8px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

.data-section {
    background: #fff3cd;
    padding: 20px;
    border-left: 4px solid #ffc107;
    margin: 20px 0;
}

#loaded-data {
    font-family: monospace;
    background: #f8f9fa;
    padding: 10px;
    border-radius: 4px;
    margin-top: 10px;
}
EOF

# Create JavaScript file
cat > "$DEMO_DIR/script.js" << 'EOF'
// Load data from JSON file
console.log('Network Traffic Demo - Script loaded');

// Fetch JSON data to generate additional network request
fetch('data.json')
    .then(response => response.json())
    .then(data => {
        console.log('Data loaded:', data);
        const dataSection = document.getElementById('data-section');
        dataSection.innerHTML = `
            <h3>Loaded Data</h3>
            <div id="loaded-data">
                <strong>Message:</strong> ${data.message}<br>
                <strong>Status:</strong> ${data.status}<br>
                <strong>Items:</strong> ${data.items.join(', ')}
            </div>
        `;
    })
    .catch(error => {
        console.error('Error loading data:', error);
    });

// Log page load event
window.addEventListener('load', function() {
    console.log('Page fully loaded with all resources');
});
EOF

# Create JSON data file
cat > "$DEMO_DIR/data.json" << 'EOF'
{
    "message": "This is sample JSON data loaded via fetch API",
    "status": "success",
    "items": ["Item 1", "Item 2", "Item 3"],
    "timestamp": "2024-01-15T10:30:00Z"
}
EOF

chown -R ga:ga "$DEMO_DIR"
echo "✓ Demo website created at: $DEMO_DIR"

# Start HTTP server in background
echo "Starting HTTP server on port 8080..."
cd "$DEMO_DIR"
python3 -m http.server 8080 > /tmp/har_demo_server.log 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > /tmp/har_demo_server.pid

# Give server time to start
sleep 2

# Verify server is running
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "✓ HTTP server running on port 8080 (PID: $SERVER_PID)"
else
    echo "⚠ Warning: HTTP server may not have started correctly"
fi

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to a neutral starting page
echo "Navigating to: about:blank"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'about:blank'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Demo website available at: http://localhost:8080"
echo ""
echo "Agent should now:"
echo "  1. Press F12 (or Ctrl+Shift+I) to open DevTools"
echo "  2. Click on 'Network' tab in DevTools"
echo "  3. Navigate to: http://localhost:8080"
echo "  4. Wait for page and all resources to load"
echo "  5. Right-click in Network panel and select 'Save all as HAR with content'"
echo "  6. Save as: network_export.har in Downloads folder"