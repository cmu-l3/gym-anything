#!/bin/bash
echo "=== Setting up Firefox Responsive Design Capture Task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

mkdir -p /home/ga/Documents/landing_page
mkdir -p /home/ga/Documents/QA_Screenshots

# Download a real responsive template (StartBootstrap Freelancer)
echo "Downloading responsive template..."
curl -L -s "https://github.com/StartBootstrap/startbootstrap-freelancer/archive/refs/tags/v7.0.7.zip" -o /tmp/template.zip || true

if [ -f /tmp/template.zip ] && unzip -t /tmp/template.zip >/dev/null 2>&1; then
    unzip -q /tmp/template.zip -d /tmp/
    cp -r /tmp/startbootstrap-freelancer-7.0.7/* /home/ga/Documents/landing_page/
    rm -rf /tmp/template.zip /tmp/startbootstrap-freelancer-7.0.7
else
    # Fallback if download fails
    echo "Using fallback template..."
    cat > /home/ga/Documents/landing_page/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Start Bootstrap - Freelancer</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; }
        header { background: #1abc9c; color: white; text-align: center; padding: 100px 20px; }
        h1 { font-size: 3em; text-transform: uppercase; }
        .container { max-width: 1200px; margin: auto; padding: 50px 20px; }
        @media (max-width: 768px) {
            header { padding: 50px 10px; }
            h1 { font-size: 2em; }
        }
    </style>
</head>
<body>
    <header>
        <h1>Freelancer Portfolio</h1>
        <p>Web Developer - Graphic Artist - User Experience Designer</p>
    </header>
    <div class="container">
        <h2>Portfolio</h2>
        <p>Responsive design testing page.</p>
    </div>
</body>
</html>
EOF
fi

# Fix ownership
chown -R ga:ga /home/ga/Documents

# Start Firefox
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox file:///home/ga/Documents/landing_page/index.html &"

    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla"; then
            echo "Firefox window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Give time for the page to render
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="