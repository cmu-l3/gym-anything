#!/bin/bash
# setup_task.sh - Setup for Accessibility Compliance Audit
# Creates the staging HTML file with deliberate errors and prepares Edge.

set -e

echo "=== Setting up Accessibility Compliance Audit ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Desktop/audit_remediation.txt
rm -f /home/ga/Documents/city_portal_staging.html

# 3. Create the HTML file with specific accessibility errors
# Errors:
# - #hero-banner: Missing alt text
# - #newsletter-input: Missing label
# - #footer-disclaimer: Low contrast (#cccccc on #ffffff)

mkdir -p /home/ga/Documents
cat > /home/ga/Documents/city_portal_staging.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>City Services Portal - Staging</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 20px; line-height: 1.6; }
        .header { background: #003366; color: white; padding: 20px; border-radius: 5px; }
        .content { margin: 20px 0; }
        .card { border: 1px solid #ddd; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        
        /* ERROR 1: Low Contrast (Gray on White) */
        #footer-disclaimer { 
            color: #cccccc; 
            background-color: #ffffff; 
            font-size: 12px; 
            margin-top: 50px; 
            padding: 10px;
            border-top: 1px solid #eee;
        }
        
        button { background: #0056b3; color: white; border: none; padding: 10px 15px; cursor: pointer; }
    </style>
</head>
<body>
    <div class="header">
        <h1>City Services Portal</h1>
    </div>
    
    <div class="content">
        <div class="card">
            <h2>Welcome Residents</h2>
            <!-- ERROR 2: Image missing alt attribute -->
            <img id="hero-banner" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" width="100%" height="150" style="background-color: #ddd; object-fit: cover;">
            <p>Access city services, pay bills, and find community events.</p>
        </div>

        <div class="card">
            <h3>Newsletter Subscription</h3>
            <p>Stay updated with city news.</p>
            <form action="#">
                <!-- ERROR 3: Input missing label -->
                <input type="email" id="newsletter-input" placeholder="Enter email address">
                <button type="submit">Subscribe</button>
            </form>
        </div>
    </div>

    <div id="footer-disclaimer">
        &copy; 2024 City Government. Staging Environment. All rights reserved.
    </div>
</body>
</html>
EOF

# Ensure ga user owns the file
chown ga:ga /home/ga/Documents/city_portal_staging.html
chmod 644 /home/ga/Documents/city_portal_staging.html

echo "Created staging file at /home/ga/Documents/city_portal_staging.html"

# 4. Ensure Edge is ready (kill old instances)
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 1

# 5. Launch Edge to a blank page to start the session
# The agent will need to navigate to the local file themselves
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /dev/null 2>&1 &"

# Wait for Edge window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="