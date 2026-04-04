#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Geolocation Sensors Override Task Setup ==="
echo "Task: Use DevTools Sensors panel to override geolocation to San Francisco"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install required Python packages for CDP (if not already installed)
pip3 install -q websocket-client requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a simple location-aware HTML page
echo "Creating location-aware test page..."
LOCATION_PAGE_DIR="/home/ga/Documents"
mkdir -p "$LOCATION_PAGE_DIR"

cat > "$LOCATION_PAGE_DIR/location_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Geolocation Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #2c3e50; }
        button {
            background: #3498db;
            color: white;
            border: none;
            padding: 12px 24px;
            font-size: 16px;
            border-radius: 5px;
            cursor: pointer;
            margin: 10px 0;
        }
        button:hover { background: #2980b9; }
        .result {
            margin-top: 20px;
            padding: 15px;
            background: #ecf0f1;
            border-radius: 5px;
            font-family: monospace;
        }
        .location { color: #27ae60; font-weight: bold; }
        .error { color: #e74c3c; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📍 Geolocation Test Page</h1>
        <p>This page will request your location when you click the button below.</p>
        <p><strong>Task:</strong> Use Chrome DevTools → Sensors panel to override your location to San Francisco.</p>
        
        <button onclick="getLocation()">🌍 Get My Location</button>
        
        <div id="result" class="result" style="display:none;">
            <h3>Location Information:</h3>
            <div id="coords"></div>
        </div>
    </div>

    <script>
        function getLocation() {
            const resultDiv = document.getElementById('result');
            const coordsDiv = document.getElementById('coords');
            
            resultDiv.style.display = 'block';
            coordsDiv.innerHTML = '<p>🔄 Requesting location...</p>';
            
            if (!navigator.geolocation) {
                coordsDiv.innerHTML = '<p class="error">❌ Geolocation is not supported by this browser.</p>';
                return;
            }
            
            navigator.geolocation.getCurrentPosition(
                function(position) {
                    const lat = position.coords.latitude.toFixed(4);
                    const lon = position.coords.longitude.toFixed(4);
                    const accuracy = position.coords.accuracy.toFixed(2);
                    
                    coordsDiv.innerHTML = `
                        <p class="location">✅ Location Retrieved Successfully!</p>
                        <p><strong>Latitude:</strong> ${lat}°</p>
                        <p><strong>Longitude:</strong> ${lon}°</p>
                        <p><strong>Accuracy:</strong> ${accuracy} meters</p>
                        <p><strong>Timestamp:</strong> ${new Date(position.timestamp).toLocaleString()}</p>
                    `;
                    
                    // Store in window for verification
                    window.lastPosition = position;
                    console.log('Geolocation retrieved:', position.coords);
                },
                function(error) {
                    let errorMsg = '';
                    switch(error.code) {
                        case error.PERMISSION_DENIED:
                            errorMsg = "User denied the request for Geolocation.";
                            break;
                        case error.POSITION_UNAVAILABLE:
                            errorMsg = "Location information is unavailable.";
                            break;
                        case error.TIMEOUT:
                            errorMsg = "The request to get user location timed out.";
                            break;
                        default:
                            errorMsg = "An unknown error occurred.";
                    }
                    coordsDiv.innerHTML = `<p class="error">❌ Error: ${errorMsg}</p>`;
                    console.error('Geolocation error:', error);
                },
                {
                    enableHighAccuracy: true,
                    timeout: 10000,
                    maximumAge: 0
                }
            );
        }
        
        // Auto-request location after 2 seconds for automated testing
        setTimeout(function() {
            console.log("Auto-requesting location for verification...");
            getLocation();
        }, 2000);
    </script>
</body>
</html>
EOF

chown ga:ga "$LOCATION_PAGE_DIR/location_test.html"
echo "✓ Location test page created at: $LOCATION_PAGE_DIR/location_test.html"

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

# Navigate to the location test page
LOCATION_URL="file:///home/ga/Documents/location_test.html"
echo "Navigating to: $LOCATION_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/location_test.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

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
echo "Chrome should be displaying the location test page"
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Click the three-dot menu (⋮) in DevTools"
echo "  3. Select 'More tools' → 'Sensors'"
echo "  4. In Sensors panel, find Geolocation dropdown"
echo "  5. Select 'San Francisco' or enter custom coordinates:"
echo "     Latitude: 37.7749, Longitude: -122.4194"
echo "  6. Page should auto-refresh and show San Francisco coordinates"