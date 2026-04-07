#!/bin/bash
# setup_task.sh - Setup for DevTools Computed Style Audit
# Starts a local Python HTTP server with a custom HTML/CSS page and launches Edge.

set -e

TASK_DIR="/workspace/tasks/devtools_computed_style_audit"
WEB_ROOT="/tmp/design_system_site"
PORT=8000

echo "=== Setting up devtools_computed_style_audit ==="

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Kill existing Edge and Python server instances
pkill -f microsoft-edge 2>/dev/null || true
pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
sleep 2

# 3. Create Web Content
mkdir -p "$WEB_ROOT"

# Generate index.html with specific computed styles
# - H1: Font stack ensures a specific fallback is used
# - Button: Uses HSL variable that resolves to specific RGB
# - Alert: Uses calc() for border width
# - Footer: Opacity
cat > "$WEB_ROOT/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Design System Staging</title>
    <style>
        :root {
            /* HSL(210, 100%, 50%) = RGB(0, 128, 255) approx azure/dodgerblue */
            --brand-hue: 210;
            --brand-sat: 100%;
            --brand-light: 50%;
            --brand-primary: hsl(var(--brand-hue), var(--brand-sat), var(--brand-light));
            
            --spacing-unit: 8px;
            --border-multiplier: 0.75;
        }

        body {
            font-family: sans-serif;
            background-color: #f4f4f4;
            padding: 2rem;
            line-height: 1.6;
        }

        /* 1. Hero Heading: Font resolution test */
        /* 'NonExistentFont' should be skipped, resolving to 'DejaVu Sans' on standard Linux */
        h1 {
            font-family: 'NonExistentFont', 'DejaVu Sans', 'Liberation Sans', sans-serif;
            color: #333;
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 2rem;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        /* 2. Primary Button: Variable resolution test */
        .btn {
            display: inline-block;
            padding: 10px 20px;
            text-decoration: none;
            border-radius: 4px;
            font-weight: bold;
        }
        
        .btn-primary {
            background-color: var(--brand-primary);
            color: white;
            border: none;
        }

        /* 3. Alert Box: Calc/Computed test */
        .alert {
            margin-top: 20px;
            padding: 15px;
            background-color: #fff3cd;
            border: 1px solid #ffeeba;
            /* 8px * 0.75 = 6px */
            border-left: calc(var(--spacing-unit) * var(--border-multiplier)) solid #ffc107; 
            color: #856404;
        }

        /* 4. Footer: Opacity test */
        footer {
            margin-top: 40px;
            text-align: center;
            font-size: 0.9rem;
            opacity: 0.75;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Design System 2.0 Audit</h1>
        <p>Welcome to the staging environment. Please verify the computed styles for the components below.</p>

        <section>
            <h2>Buttons</h2>
            <a href="#" class="btn btn-primary">Primary Action</a>
            <a href="#" class="btn">Secondary</a>
        </section>

        <section>
            <h2>Alerts</h2>
            <div class="alert">
                <strong>Warning!</strong> This is a system alert component. Check the left border width.
            </div>
        </section>

        <footer>
            &copy; 2024 Acme Corp Design Systems. All rights reserved.
        </footer>
    </div>
</body>
</html>
EOF

# 4. Start Local Server
echo "Starting local server on port $PORT..."
cd "$WEB_ROOT"
nohup python3 -m http.server "$PORT" > /tmp/server.log 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > /tmp/server_pid.txt

# Wait for server to be ready
sleep 2

# 5. Launch Edge
echo "Launching Microsoft Edge..."
# Note: Using flags to suppress first-run experiences and restoration bubbles
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --new-window 'http://localhost:$PORT' \
    > /tmp/edge_launch.log 2>&1 &"

# 6. Wait for Edge window and Maximize
echo "Waiting for Edge..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge found."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="