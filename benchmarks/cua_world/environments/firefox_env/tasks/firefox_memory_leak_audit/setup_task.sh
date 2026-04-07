#!/bin/bash
echo "=== Setting up memory leak audit task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/baseline*
rm -f /home/ga/Documents/leaked*

# Create the web app directory
mkdir -p /tmp/leak_app
cat > /tmp/leak_app/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Photo Gallery Bug #402</title>
    <style>
        body { font-family: sans-serif; padding: 20px; }
        button { font-size: 16px; padding: 10px; margin: 5px; cursor: pointer; }
        #galleryContainer { margin-top: 20px; display: flex; flex-wrap: wrap; }
        .gallery-item { width: 50px; height: 50px; background: #eee; margin: 2px; }
    </style>
</head>
<body>
    <h1>Photo Gallery (Bug #402)</h1>
    <button id="loadBtn">Load High-Res Gallery</button>
    <button id="destroyBtn">Destroy Gallery</button>
    <div id="galleryContainer"></div>

    <script>
        window.leakedGalleries = [];

        document.getElementById('loadBtn').addEventListener('click', () => {
            const container = document.getElementById('galleryContainer');
            container.innerHTML = '';
            // Create a lot of elements to ensure a measurable memory footprint (> 1MB)
            for (let i = 0; i < 20000; i++) {
                const el = document.createElement('div');
                el.className = 'gallery-item';
                el.dataset.dummy = new Array(1000).join('x');
                container.appendChild(el);
            }
            document.title = "Gallery Loaded";
        });

        document.getElementById('destroyBtn').addEventListener('click', () => {
            const container = document.getElementById('galleryContainer');
            if (container.children.length > 0) {
                const detached = document.createElement('div');
                while(container.firstChild) {
                    detached.appendChild(container.firstChild);
                }
                window.leakedGalleries.push(detached);
            }
            document.title = "Gallery Destroyed";
        });
    </script>
</body>
</html>
EOF

# Stop any running python http servers on port 8080
pkill -f "python3 -m http.server 8080" || true

# Start web server
cd /tmp/leak_app
nohup python3 -m http.server 8080 > /tmp/http_server.log 2>&1 &
cd -

# Wait for server
for i in {1..10}; do
    if curl -s http://localhost:8080/ > /dev/null; then
        echo "Web server ready"
        break
    fi
    sleep 1
done

# Start Firefox if not running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080/ &"
    sleep 5
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="