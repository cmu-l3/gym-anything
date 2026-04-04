#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Local Storage Manipulation Task Setup ==="
echo "Task: Use DevTools Application panel to modify localStorage"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true
pip3 install -q websocket-client requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page with localStorage
echo "Creating test page with localStorage..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/localstorage_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LocalStorage Test Application</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 700px;
            margin: 50px auto;
            padding: 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
        }
        .container {
            background: rgba(255, 255, 255, 0.95);
            color: #333;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
        }
        h1 {
            color: #667eea;
            margin-top: 0;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }
        .storage-item {
            margin: 15px 0;
            padding: 15px;
            background: #f7fafc;
            border-left: 4px solid #667eea;
            border-radius: 4px;
        }
        .storage-item strong {
            color: #667eea;
            font-size: 1.1em;
        }
        .storage-item .value {
            color: #2d3748;
            font-weight: 500;
            margin-left: 10px;
        }
        .instructions {
            background: #fff3cd;
            border: 2px solid #ffc107;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
            color: #856404;
        }
        .instructions h3 {
            margin-top: 0;
            color: #856404;
        }
        .instructions ol {
            margin: 10px 0;
            padding-left: 20px;
        }
        .instructions li {
            margin: 8px 0;
            line-height: 1.5;
        }
        code {
            background: #f1f5f9;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            color: #c7254e;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 LocalStorage Test Application</h1>
        
        <div class="instructions">
            <h3>📋 Your Task:</h3>
            <ol>
                <li>Press <strong>F12</strong> to open Chrome DevTools</li>
                <li>Click on the <strong>Application</strong> tab at the top</li>
                <li>In the left sidebar, expand <strong>Storage → Local Storage</strong></li>
                <li>Click on the domain (file:// or localhost)</li>
                <li><strong>Add</strong> a new entry: Key=<code>theme</code>, Value=<code>dark</code></li>
                <li><strong>Modify</strong> existing <code>language</code>: Change <code>en</code> to <code>es</code></li>
            </ol>
            <p style="margin-bottom: 0;"><strong>💡 Tip:</strong> Double-click cells to edit values</p>
        </div>

        <div class="info-section">
            <h2>📊 Current Storage State:</h2>
            
            <div class="storage-item">
                <strong>Theme:</strong>
                <span class="value" id="theme">Not set (using light theme)</span>
            </div>
            
            <div class="storage-item">
                <strong>Language:</strong>
                <span class="value" id="language">Not set</span>
            </div>
            
            <div class="storage-item">
                <strong>Initialized:</strong>
                <span class="value" id="initialized">false</span>
            </div>
        </div>

        <p style="margin-top: 30px; color: #718096; font-size: 0.9em; text-align: center;">
            🔄 This page auto-refreshes every second to show localStorage changes
        </p>
    </div>
    
    <script>
        // Pre-seed localStorage with initial data
        function initializeStorage() {
            if (!localStorage.getItem('language')) {
                localStorage.setItem('language', 'en');
                console.log('✓ Initialized language to: en');
            }
            if (!localStorage.getItem('initialized')) {
                localStorage.setItem('initialized', 'true');
                console.log('✓ Initialized flag set to: true');
            }
        }
        
        // Display current localStorage values
        function updateDisplay() {
            const theme = localStorage.getItem('theme');
            const language = localStorage.getItem('language');
            const initialized = localStorage.getItem('initialized');
            
            document.getElementById('theme').textContent = 
                theme || 'Not set (using light theme)';
            document.getElementById('language').textContent = 
                language || 'Not set';
            document.getElementById('initialized').textContent = 
                initialized || 'false';
            
            // Apply dark theme visually if set
            if (theme === 'dark') {
                document.body.style.background = 'linear-gradient(135deg, #2d3748 0%, #1a202c 100%)';
                const container = document.querySelector('.container');
                container.style.background = 'rgba(45, 55, 72, 0.95)';
                container.style.color = '#e2e8f0';
                document.querySelector('h1').style.color = '#90cdf4';
                document.querySelector('h1').style.borderBottomColor = '#90cdf4';
                
                document.querySelectorAll('.storage-item').forEach(item => {
                    item.style.background = '#4a5568';
                    item.style.borderLeftColor = '#90cdf4';
                });
                document.querySelectorAll('.storage-item strong').forEach(el => {
                    el.style.color = '#90cdf4';
                });
                document.querySelectorAll('.storage-item .value').forEach(el => {
                    el.style.color = '#e2e8f0';
                });
            }
            
            console.log('Current storage:', {theme, language, initialized});
        }
        
        // Initialize on page load
        initializeStorage();
        updateDisplay();
        
        // Listen for storage changes
        window.addEventListener('storage', function(e) {
            console.log('Storage changed:', e.key, '=', e.newValue);
            updateDisplay();
        });
        
        // Poll for changes (catches DevTools manual edits)
        setInterval(updateDisplay, 1000);
        
        console.log('%c LocalStorage Test App Ready ', 'background: #667eea; color: white; font-size: 14px; padding: 5px;');
        console.log('Open DevTools > Application > Local Storage to modify storage');
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/localstorage_test.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/localstorage_test.html"

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

# Navigate to the test page
TEST_PAGE_URL="file:///home/ga/Documents/localstorage_test.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/localstorage_test.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    TARGETS=$(curl -s http://localhost:9222/json)
    PAGE_COUNT=$(echo "$TARGETS" | jq '[.[] | select(.type == "page")] | length')
    echo "✓ Active page count: $PAGE_COUNT"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the LocalStorage test page"
echo ""
echo "Agent should:"
echo "  1. Press F12 to open DevTools"
echo "  2. Navigate to Application tab"
echo "  3. Expand Local Storage in left sidebar"
echo "  4. Select the test page's origin"
echo "  5. Add new key: theme = dark"
echo "  6. Modify existing: language = es (was 'en')"