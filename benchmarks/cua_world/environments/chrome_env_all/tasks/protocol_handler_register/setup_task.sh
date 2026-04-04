#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Protocol Handler Registration Task Setup ==="
echo "Task: Register a mailto: protocol handler through web API"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page for protocol handler registration
echo "Creating protocol handler test page..."
TASK_DIR="/workspace/tasks/protocol_handler_register"
TEST_DIR="/home/ga/Documents/protocol_handler_test"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/handler_registration.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Protocol Handler Registration - mailto:</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            background: white;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            padding: 50px;
            max-width: 600px;
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 32px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 16px;
        }
        .info-box {
            background: #f0f4ff;
            border-left: 4px solid #667eea;
            padding: 20px;
            margin: 20px 0;
            text-align: left;
        }
        .info-box h3 {
            margin-top: 0;
            color: #667eea;
        }
        .info-box code {
            background: #e0e7ff;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 18px 40px;
            font-size: 18px;
            font-weight: bold;
            border-radius: 8px;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
            margin: 10px 0;
        }
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 20px rgba(102, 126, 234, 0.4);
        }
        button:active {
            transform: translateY(0);
        }
        #status {
            margin-top: 20px;
            font-weight: bold;
            min-height: 30px;
            padding: 10px;
            border-radius: 6px;
        }
        .status-waiting {
            color: #666;
        }
        .status-success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        .status-error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        .icon {
            font-size: 48px;
            margin-bottom: 20px;
        }
        .instructions {
            background: #fff9e6;
            border: 1px solid #ffd700;
            padding: 15px;
            margin: 20px 0;
            border-radius: 6px;
            text-align: left;
        }
        .instructions ol {
            margin: 10px 0;
            padding-left: 20px;
        }
        .instructions li {
            margin: 8px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">📧</div>
        <h1>Email Handler Registration</h1>
        <p class="subtitle">Register this page as your default mailto: link handler</p>
        
        <div class="info-box">
            <h3>What is a Protocol Handler?</h3>
            <p>Protocol handlers allow web applications to handle specific URL schemes. When you click a <code>mailto:</code> link, the registered handler will open instead of a desktop email client.</p>
        </div>

        <div class="instructions">
            <strong>📋 Instructions:</strong>
            <ol>
                <li>Click the button below to register this handler</li>
                <li>Chrome will show a permission prompt in the address bar</li>
                <li>Click <strong>"Allow"</strong> to complete the registration</li>
            </ol>
        </div>
        
        <button id="registerBtn">Register as Email Handler</button>
        
        <div id="status" class="status-waiting">
            Click the button above to start registration
        </div>
    </div>
    
    <script>
        document.getElementById('registerBtn').addEventListener('click', function() {
            const statusDiv = document.getElementById('status');
            
            try {
                // Attempt to register protocol handler
                navigator.registerProtocolHandler(
                    'mailto',
                    location.origin + location.pathname + '?compose=%s',
                    'Test Email Handler'
                );
                
                statusDiv.textContent = '✓ Registration requested! Please ALLOW the permission prompt in the address bar.';
                statusDiv.className = 'status-success';
                
                // Log for debugging
                console.log('Protocol handler registration requested');
                console.log('Handler URL:', location.origin + location.pathname + '?compose=%s');
                
            } catch (e) {
                statusDiv.textContent = '✗ Error: ' + e.message;
                statusDiv.className = 'status-error';
                console.error('Registration error:', e);
            }
        });
        
        // Check if we're handling a mailto: link
        const urlParams = new URLSearchParams(window.location.search);
        const composeEmail = urlParams.get('compose');
        
        if (composeEmail) {
            document.body.innerHTML = `
                <div class="container">
                    <div class="icon">✉️</div>
                    <h1>Email Handler Active!</h1>
                    <p class="subtitle">The protocol handler is working correctly</p>
                    <div class="info-box">
                        <h3>Compose Email To:</h3>
                        <p style="font-size: 20px; word-break: break-all;"><strong>${composeEmail}</strong></p>
                    </div>
                    <p style="color: #666;">This demonstrates that the mailto: handler was successfully registered.</p>
                </div>
            `;
        }
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_DIR/handler_registration.html"
echo "✓ Protocol handler test page created at: $TEST_DIR/handler_registration.html"

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

# Navigate to the protocol handler test page
TEST_PAGE_URL="file://$TEST_DIR/handler_registration.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_PAGE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    # Get active tab URL for verification
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the protocol handler registration page"
echo "Agent should now:"
echo "  1. Click the 'Register as Email Handler' button"
echo "  2. Click 'Allow' in the permission prompt that appears in the address bar"
echo "  3. The handler will be registered in Chrome's Preferences"