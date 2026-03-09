#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome PWA Installation Task Setup ==="
echo "Task: Install a Progressive Web App with 'Open as window' option"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Wait for environment to be ready
sleep 2

# Create PWA assets directory
PWA_DIR="/home/ga/test_pwa"
mkdir -p "$PWA_DIR/icons"

echo "Creating PWA assets..."

# Create a simple icon using ImageMagick
convert -size 192x192 xc:#4285F4 -pointsize 80 -fill white -gravity center \
    -annotate +0+0 "PWA" "$PWA_DIR/icons/icon-192.png" 2>/dev/null || {
    # Fallback: create a simple colored square
    convert -size 192x192 xc:#4285F4 "$PWA_DIR/icons/icon-192.png" 2>/dev/null || true
}

convert -size 512x512 xc:#4285F4 -pointsize 180 -fill white -gravity center \
    -annotate +0+0 "PWA" "$PWA_DIR/icons/icon-512.png" 2>/dev/null || {
    convert -size 512x512 xc:#4285F4 "$PWA_DIR/icons/icon-512.png" 2>/dev/null || true
}

# Create manifest.json
cat > "$PWA_DIR/manifest.json" << 'MANIFEST_EOF'
{
  "name": "Test PWA Application",
  "short_name": "TestPWA",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#4285F4",
  "description": "A test Progressive Web App for installation verification",
  "icons": [
    {
      "src": "/icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
MANIFEST_EOF

# Create service worker (required for PWA installability)
cat > "$PWA_DIR/service-worker.js" << 'SW_EOF'
// Simple service worker for PWA installability
const CACHE_NAME = 'test-pwa-v1';
const urlsToCache = [
  '/',
  '/manifest.json'
];

self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(function(cache) {
        return cache.addAll(urlsToCache);
      })
  );
});

self.addEventListener('fetch', function(event) {
  event.respondWith(
    caches.match(event.request)
      .then(function(response) {
        if (response) {
          return response;
        }
        return fetch(event.request);
      }
    )
  );
});
SW_EOF

# Create index.html
cat > "$PWA_DIR/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="theme-color" content="#4285F4">
    <title>Test PWA Application</title>
    <link rel="manifest" href="/manifest.json">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .container {
            text-align: center;
            padding: 40px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 20px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
            max-width: 600px;
        }
        h1 {
            font-size: 3em;
            margin-bottom: 20px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .icon {
            font-size: 6em;
            margin-bottom: 20px;
        }
        p {
            font-size: 1.2em;
            line-height: 1.6;
            margin-bottom: 15px;
        }
        .feature {
            background: rgba(255, 255, 255, 0.2);
            padding: 15px;
            border-radius: 10px;
            margin: 10px 0;
        }
        .install-prompt {
            margin-top: 30px;
            padding: 20px;
            background: rgba(66, 133, 244, 0.3);
            border-radius: 10px;
            border: 2px solid rgba(255, 255, 255, 0.3);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">📱</div>
        <h1>Test PWA Application</h1>
        <p><strong>Progressive Web App</strong></p>
        
        <div class="feature">
            <p>✨ This is a test Progressive Web App designed for installation verification.</p>
        </div>
        
        <div class="feature">
            <p>🚀 Installable as a standalone application</p>
        </div>
        
        <div class="feature">
            <p>💻 Works offline with service worker</p>
        </div>
        
        <div class="install-prompt">
            <p><strong>Ready to Install!</strong></p>
            <p>Click the install button in your browser or use Chrome menu → "Install Test PWA Application"</p>
            <p style="margin-top: 10px; font-size: 0.9em;">Make sure to check "Open as window" for the full app experience!</p>
        </div>
        
        <p style="margin-top: 30px; font-size: 0.9em; opacity: 0.8;">
            Version 1.0 | Test Environment
        </p>
    </div>
    
    <script>
        // Register service worker
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', function() {
                navigator.serviceWorker.register('/service-worker.js')
                    .then(function(registration) {
                        console.log('ServiceWorker registration successful:', registration.scope);
                    })
                    .catch(function(err) {
                        console.log('ServiceWorker registration failed:', err);
                    });
            });
        }
        
        // Listen for beforeinstallprompt event
        let deferredPrompt;
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            console.log('PWA install prompt ready');
        });
    </script>
</body>
</html>
HTML_EOF

chown -R ga:ga "$PWA_DIR"
echo "✓ PWA assets created at: $PWA_DIR"

# Kill any existing Python HTTP servers on port 8080
pkill -f "python3.*8080" || true
sleep 1

# Start HTTP server for PWA
echo "Starting HTTP server on http://localhost:8080..."
su - ga -c "cd $PWA_DIR && nohup python3 -m http.server 8080 > /tmp/pwa_server.log 2>&1 &"
sleep 2

# Verify server is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "✓ HTTP server is running"
else
    echo "⚠ Warning: HTTP server may not be running properly"
fi

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh http://localhost:8080" &
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

# Navigate to the PWA
PWA_URL="http://localhost:8080/"
echo "Navigating to PWA: $PWA_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://localhost:8080/'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Give the PWA time to register service worker
echo "Waiting for service worker registration..."
sleep 3

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
echo "PWA is ready at: http://localhost:8080/"
echo "Agent should now:"
echo "  1. Look for install button in address bar OR"
echo "  2. Click three-dot menu → More tools → Create shortcut"
echo "  3. In the dialog, ensure 'Open as window' is checked"
echo "  4. Click 'Create' or 'Install' to complete installation"