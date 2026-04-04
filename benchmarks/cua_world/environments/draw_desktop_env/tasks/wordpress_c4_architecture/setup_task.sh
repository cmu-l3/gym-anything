#!/bin/bash
# Do NOT use set -e to prevent premature exit on non-critical errors

echo "=== Setting up wordpress_c4_architecture task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up previous runs
rm -f /home/ga/Desktop/wordpress_c4.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/wordpress_c4.png 2>/dev/null || true

# Create the Architecture Specification Document
cat > /home/ga/Desktop/wordpress_c4_spec.txt << 'SPECEOF'
WordPress CMS - C4 Architecture Specification
=============================================
Project: Managed Hosting Platform
Date: 2024-05-15
Notation: C4 Model (https://c4model.com/)

VIEW 1: SYSTEM CONTEXT
----------------------
Scope: The entire WordPress software system.
Goal: Show how users and external systems interact with WordPress.

Actors (Person shapes):
1. Blog Reader: Reads blog posts, leaves comments.
2. Content Author: Creates/edits posts, uploads media.
3. Site Administrator: Manages settings, users, plugins, themes.

Focus System (Software System shape):
4. WordPress CMS: The content management system being documented.

External Systems (Software System shapes, gray/external style):
5. Email Service: SMTP provider for notifications/password resets.
6. CDN Provider: Delivers static assets (images, CSS, JS) to users.
7. Social Media APIs: Used to share posts or embed content.
8. Plugin/Theme Repository (wordpress.org): Source for updates and extensions.

Relationships (Labeled arrows):
- Reader -> WordPress: "Reads content, comments [HTTPS]"
- Author -> WordPress: "Authors content [HTTPS]"
- Administrator -> WordPress: "Manages system [HTTPS]"
- WordPress -> Email Service: "Sends emails [SMTP]"
- WordPress -> CDN Provider: "Offloads static assets [HTTPS]"
- WordPress -> Social Media APIs: "Publishes content [REST]"
- WordPress -> Plugin Repository: "Checks for updates [HTTPS]"


VIEW 2: CONTAINER
-----------------
Scope: Inside the "WordPress CMS" system boundary.
Goal: Show the high-level deployable units (containers).

Boundary:
- Draw a "System Boundary" box labeled "WordPress CMS".
- Place the external actors (Reader, Email Service, etc.) OUTSIDE this boundary.

Containers (Container shapes, inside the boundary):
1. Web Server (Apache/Nginx): Handles HTTP requests, serves static files.
2. PHP Application (wp-includes): The core WordPress application logic.
3. WP-Admin Dashboard: The administrative interface (/wp-admin).
4. REST API (wp-json): Headless interface for external consumers.
5. MySQL Database: Stores content, user data, configuration.
6. Media File Storage (wp-content/uploads): Stores uploaded images/files on disk.
7. WP-Cron Scheduler: Handles scheduled tasks (backups, publishing).

Relationships:
- Web Server -> PHP Application: "Forwards dynamic requests [FastCGI]"
- PHP Application -> MySQL Database: "Reads/Writes data [SQL]"
- PHP Application -> Media File Storage: "Reads/Writes files [Filesystem]"
- WP-Admin -> PHP Application: "Uses core logic"
- REST API -> PHP Application: "Uses core logic"
- WP-Cron -> PHP Application: "Triggers scheduled events"
- (External) Reader -> Web Server: "Visits site [HTTPS]"
- (External) Author -> Web Server: "Uploads content [HTTPS]"
SPECEOF

chown ga:ga /home/ga/Desktop/wordpress_c4_spec.txt
chmod 644 /home/ga/Desktop/wordpress_c4_spec.txt
echo "Spec file created at ~/Desktop/wordpress_c4_spec.txt"

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch draw.io (blank)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_c4.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss startup dialog (creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="