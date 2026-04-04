#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Geolocation Emulation Task Setup ==="
echo "Task: Use DevTools Sensors panel to override geolocation for testing"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create the geolocation test page
echo "Creating geolocation test page..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/geolocation_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Geolocation Test Page</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.95);
            color: #333;
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
        }
        h1 {
            color: #667eea;
            margin-top: 0;
            text-align: center;
        }
        .location-display {
            background: #f7f9fc;
            padding: 25px;
            border-radius: 10px;
            margin: 25px 0;
            border-left: 5px solid #667eea;
        }
        .coordinate-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin: 15px 0;
            font-size: 18px;
        }
        .label {
            font-weight: 600;
            color: #555;
            min-width: 120px;
        }
        .value {
            font-family: 'Courier New', monospace;
            font-size: 20px;
            font-weight: bold;
            color: #667eea;
            background: white;
            padding: 8px 15px;
            border-radius: 5px;
            flex-grow: 1;
            margin-left: 15px;
            text-align: center;
        }
        .status {
            text-align: center;
            padding: 15px;
            margin: 20px 0;
            border-radius: 8px;
            font-weight: 500;
        }
        .status.loading {
            background: #fff3cd;
            color: #856404;
        }
        .status.success {
            background: #d4edda;
            color: #155724;
        }
        .status.error {
            background: #f8d7da;
            color: #721c24;
        }
        button {
            width: 100%;
            padding: 15px 30px;
            font-size: 16px;
            font-weight: 600;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s ease;
            margin-top: 15px;
        }
        button:hover {
            background: #5568d3;
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }
        button:active {
            transform: translateY(0);
        }
        .info-box {
            background: #e7f3ff;
            border: 1px solid #b3d9ff;
            padding: 15px;
            border-radius: 8px;
            margin-top: 25px;
            font-size: 14px;
            color: #004085;
        }
        .info-box strong {
            display: block;
            margin-bottom: 8px;
            font-size: 15px;
        }
        .map-placeholder {
            width: 100%;
            height: 200px;
            background: #e9ecef;
            border-radius: 8px;
            margin-top: 20px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #6c757d;
            font-style: italic;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌍 Geolocation Emulation Test</h1>
        
        <div class="status loading" id="status">
            🔄 Waiting for location request...
        </div>
        
        <button onclick="requestLocation()">📍 Get My Location</button>
        
        <div class="location-display">
            <div class="coordinate-row">
                <span class="label">Latitude:</span>
                <span class="value" id="latitude" data-lat="">—</span>
            </div>
            <div class="coordinate-row">
                <span class="label">Longitude:</span>
                <span class="value" id="longitude" data-lon="">—</span>
            </div>
            <div class="coordinate-row">
                <span class="label">Accuracy:</span>
                <span class="value" id="accuracy">—</span>
            </div>
            <div class="coordinate-row">
                <span class="label">Timestamp:</span>
                <span class="value" id="timestamp">—</span>
            </div>
        </div>
        
        <div class="map-placeholder" id="mapPlaceholder">
            Map would be displayed here
        </div>
        
        <div class="info-box">
            <strong>💡 Testing Instructions:</strong>
            Open Chrome DevTools (F12) → Navigate to "Sensors" panel (may be under "More tools") → 
            Set location override to custom coordinates (e.g., Paris: 48.8584, 2.2945) → 
            Click "Get My Location" button above to test.
        </div>
    </div>
    
    <script>
        let locationAttempts = 0;
        
        function updateStatus(message, type) {
            const statusEl = document.getElementById('status');
            statusEl.textContent = message;
            statusEl.className = 'status ' + type;
        }
        
        function requestLocation() {
            locationAttempts++;
            updateStatus('🔄 Requesting location...', 'loading');
            
            if (!navigator.geolocation) {
                updateStatus('❌ Geolocation not supported by browser', 'error');
                return;
            }
            
            const options = {
                enableHighAccuracy: true,
                timeout: 10000,
                maximumAge: 0
            };
            
            navigator.geolocation.getCurrentPosition(
                function(position) {
                    const lat = position.coords.latitude;
                    const lon = position.coords.longitude;
                    const acc = position.coords.accuracy;
                    const time = new Date(position.timestamp);
                    
                    // Update display with data attributes for easy verification
                    const latEl = document.getElementById('latitude');
                    const lonEl = document.getElementById('longitude');
                    
                    latEl.textContent = lat.toFixed(6);
                    latEl.setAttribute('data-lat', lat);
                    
                    lonEl.textContent = lon.toFixed(6);
                    lonEl.setAttribute('data-lon', lon);
                    
                    document.getElementById('accuracy').textContent = acc.toFixed(1) + ' meters';
                    document.getElementById('timestamp').textContent = time.toLocaleTimeString();
                    
                    updateStatus('✅ Location retrieved successfully!', 'success');
                    
                    // Update map placeholder
                    const mapEl = document.getElementById('mapPlaceholder');
                    mapEl.innerHTML = `
                        <div style="text-align: center;">
                            <div style="font-size: 48px; margin-bottom: 10px;">📍</div>
                            <div style="font-size: 16px; font-weight: 600; color: #495057;">
                                ${lat.toFixed(4)}°, ${lon.toFixed(4)}°
                            </div>
                            <div style="font-size: 14px; color: #6c757d; margin-top: 5px;">
                                ${getLocationName(lat, lon)}
                            </div>
                        </div>
                    `;
                },
                function(error) {
                    let errorMsg = '';
                    switch(error.code) {
                        case error.PERMISSION_DENIED:
                            errorMsg = '❌ Location permission denied';
                            break;
                        case error.POSITION_UNAVAILABLE:
                            errorMsg = '❌ Location information unavailable';
                            break;
                        case error.TIMEOUT:
                            errorMsg = '❌ Location request timeout';
                            break;
                        default:
                            errorMsg = '❌ Unknown error occurred';
                    }
                    updateStatus(errorMsg + ': ' + error.message, 'error');
                }
            );
        }
        
        function getLocationName(lat, lon) {
            // Simple heuristic to identify some major cities
            if (Math.abs(lat - 48.8566) < 0.1 && Math.abs(lon - 2.3522) < 0.1) {
                return 'Near Paris, France';
            } else if (Math.abs(lat - 37.7749) < 0.1 && Math.abs(lon + 122.4194) < 0.1) {
                return 'Near San Francisco, USA';
            } else if (Math.abs(lat - 51.5074) < 0.1 && Math.abs(lon + 0.1278) < 0.1) {
                return 'Near London, UK';
            } else if (Math.abs(lat - 35.6762) < 0.1 && Math.abs(lon - 139.6503) < 0.1) {
                return 'Near Tokyo, Japan';
            } else if (Math.abs(lat - 40.7128) < 0.1 && Math.abs(lon + 74.0060) < 0.1) {
                return 'Near New York, USA';
            }
            return 'Unknown location';
        }
        
        // Auto-request location after page load
        window.addEventListener('load', function() {
            updateStatus('🔄 Page loaded. Click button or waiting for auto-request...', 'loading');
            setTimeout(function() {
                console.log('Auto-requesting location...');
                requestLocation();
            }, 2000);
        });
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/geolocation_test.html"
echo "✓ Geolocation test page created at: $TEST_PAGE_DIR/geolocation_test.html"

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

# Navigate to the geolocation test page
TEST_PAGE_URL="file:///home/ga/Documents/geolocation_test.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_PAGE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

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
echo "Chrome is displaying the geolocation test page"
echo "Agent should now:"
echo "  1. Press F12 to open Chrome DevTools"
echo "  2. Navigate to 'Sensors' panel (may be under More tools '⋮')"
echo "  3. In Location section, select 'Other...' or a preset"
echo "  4. Set coordinates to: Latitude: 48.8584, Longitude: 2.2945 (Paris)"
echo "  5. The test page should automatically refresh and show the overridden location"
echo "  6. Or click 'Get My Location' button to trigger location request"