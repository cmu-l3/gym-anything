#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Notification Permission Control Task Setup ==="
echo "Task: Grant and revoke notification permissions"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create the notification test page
echo "Creating notification test page..."
NOTIFICATION_DIR="/tmp/notification_test"
mkdir -p "$NOTIFICATION_DIR"

cat > "$NOTIFICATION_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Notification Permission Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 40px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 {
            margin-top: 0;
            font-size: 2.5em;
            text-align: center;
        }
        .status {
            background: rgba(255, 255, 255, 0.2);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            font-size: 1.2em;
            text-align: center;
            min-height: 60px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        button {
            background: #4CAF50;
            color: white;
            border: none;
            padding: 15px 30px;
            font-size: 1.1em;
            border-radius: 8px;
            cursor: pointer;
            display: block;
            margin: 20px auto;
            transition: background 0.3s;
        }
        button:hover {
            background: #45a049;
        }
        button:disabled {
            background: #cccccc;
            cursor: not-allowed;
        }
        .instructions {
            background: rgba(255, 255, 255, 0.15);
            padding: 20px;
            border-radius: 10px;
            margin-top: 30px;
        }
        .instructions h2 {
            margin-top: 0;
        }
        .instructions ol {
            padding-left: 20px;
        }
        .instructions li {
            margin: 10px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔔 Notification Permission Test</h1>
        
        <div class="status" id="status">
            Ready to request notification permission...
        </div>
        
        <button id="requestBtn" onclick="requestNotificationPermission()">
            Request Notification Permission
        </button>
        
        <div class="instructions">
            <h2>Instructions:</h2>
            <ol>
                <li><strong>Grant Permission:</strong> Click "Allow" when Chrome prompts for notification permission</li>
                <li><strong>Navigate to Settings:</strong> Go to <code>chrome://settings/content/notifications</code></li>
                <li><strong>Revoke Permission:</strong> Find this site (localhost:8000) in the allowed list and remove it</li>
            </ol>
        </div>
    </div>
    
    <script>
        function updateStatus(message, color = '#4CAF50') {
            const statusDiv = document.getElementById('status');
            statusDiv.textContent = message;
            statusDiv.style.background = `rgba(255, 255, 255, 0.2)`;
        }
        
        function requestNotificationPermission() {
            if (!('Notification' in window)) {
                updateStatus('❌ This browser does not support notifications', '#f44336');
                return;
            }
            
            const currentPermission = Notification.permission;
            updateStatus(`Current permission: ${currentPermission}`, '#2196F3');
            
            if (currentPermission === 'granted') {
                updateStatus('✅ Permission already granted! Now revoke it via Settings.', '#4CAF50');
                document.getElementById('requestBtn').disabled = true;
                return;
            }
            
            if (currentPermission === 'denied') {
                updateStatus('⛔ Permission denied. Please reset in Settings.', '#f44336');
                return;
            }
            
            // Request permission
            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    updateStatus('✅ Permission granted! Now revoke it via Settings.', '#4CAF50');
                    document.getElementById('requestBtn').disabled = true;
                    
                    // Send a test notification
                    try {
                        new Notification('Success!', {
                            body: 'Notification permission has been granted.',
                            icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text y="75" font-size="75">🔔</text></svg>'
                        });
                    } catch (e) {
                        console.log('Could not send test notification:', e);
                    }
                } else if (permission === 'denied') {
                    updateStatus('❌ Permission denied', '#f44336');
                } else {
                    updateStatus('⚠️ Permission request dismissed', '#ff9800');
                }
            }).catch(err => {
                updateStatus(`❌ Error: ${err.message}`, '#f44336');
            });
        }
        
        // Auto-request permission after page load (with delay)
        window.addEventListener('load', () => {
            setTimeout(() => {
                const currentPermission = Notification.permission;
                if (currentPermission === 'default') {
                    updateStatus('🔔 Auto-requesting permission in 2 seconds...', '#2196F3');
                    setTimeout(requestNotificationPermission, 2000);
                } else if (currentPermission === 'granted') {
                    updateStatus('✅ Permission already granted!', '#4CAF50');
                    document.getElementById('requestBtn').disabled = true;
                } else {
                    updateStatus(`Current permission: ${currentPermission}`, '#ff9800');
                }
            }, 500);
        });
        
        // Update status periodically
        setInterval(() => {
            if (Notification.permission === 'granted' && !document.getElementById('requestBtn').disabled) {
                updateStatus('✅ Permission granted! Now revoke it via Settings.', '#4CAF50');
                document.getElementById('requestBtn').disabled = true;
            }
        }, 1000);
    </script>
</body>
</html>
EOF

chown ga:ga "$NOTIFICATION_DIR/index.html"
echo "✓ Notification test page created at: $NOTIFICATION_DIR/index.html"

# Start HTTP server on port 8000
echo "Starting HTTP server on port 8000..."
# Kill any existing server on port 8000
lsof -ti:8000 | xargs kill -9 2>/dev/null || true
sleep 1

# Start server in background
cd "$NOTIFICATION_DIR"
su - ga -c "cd $NOTIFICATION_DIR && python3 -m http.server 8000 > /tmp/notification_server.log 2>&1 &"
SERVER_PID=$!
echo $SERVER_PID > /tmp/notification_server.pid
sleep 2

# Verify server is running
if curl -s http://localhost:8000 > /dev/null 2>&1; then
    echo "✓ HTTP server is running on port 8000"
else
    echo "⚠ Warning: HTTP server may not be accessible"
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

# Navigate to the notification test page
TEST_URL="http://localhost:8000"
echo "Navigating to: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://localhost:8000'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the notification test page at http://localhost:8000"
echo ""
echo "Agent should now:"
echo "  1. Grant notification permission when prompted (click 'Allow')"
echo "  2. Navigate to chrome://settings/content/notifications"
echo "  3. Find localhost:8000 in the 'Allowed to send notifications' list"
echo "  4. Remove the permission (click trash icon or 'Remove' button)"
echo ""
echo "The page will auto-request permission in 2 seconds..."