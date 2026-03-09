#!/bin/bash
# setup_task.sh for mastodon_c4_model

echo "=== Setting up Mastodon C4 Model Task ==="

# 1. Clean up previous run artifacts
rm -f /home/ga/Desktop/mastodon_c4.drawio 2>/dev/null
rm -f /home/ga/Desktop/mastodon_c4.png 2>/dev/null
rm -f /home/ga/Desktop/mastodon_architecture_spec.txt 2>/dev/null

# 2. Create the Architecture Specification File
cat > /home/ga/Desktop/mastodon_architecture_spec.txt << 'EOF'
MASTODON ARCHITECTURE SPECIFICATION (C4 MODEL)
==============================================

This document describes the architecture of the Mastodon social network platform for documentation purposes.
Please create a C4 Model diagram in draw.io with 3 pages corresponding to the levels below.

LEVEL 1: SYSTEM CONTEXT DIAGRAM
-------------------------------
Scope: The entire Mastodon platform.
Goal: Show how Mastodon fits into the world.

Central System:
- "Mastodon" (The software system being documented)

External Actors & Systems:
- "End User": A person using the web interface.
- "Mobile App Client": iOS/Android apps interacting via API.
- "Remote Fediverse Instance": Other servers (PeerTube, PixelFed, other Mastodon nodes) communicating via ActivityPub.
- "Email Provider": External SMTP service (e.g., SendGrid, AWS SES) for notifications.
- "Object Storage": External storage (AWS S3, Wasabi) for user-uploaded media.

Relationships:
- User -> Uses -> Mastodon
- Mobile App -> Makes API calls to -> Mastodon
- Mastodon -> Federates with -> Remote Fediverse Instance
- Mastodon -> Sends emails via -> Email Provider
- Mastodon -> Stores/Retrieves media -> Object Storage

LEVEL 2: CONTAINER DIAGRAM
--------------------------
Scope: Inside the "Mastodon" System boundary.
Goal: Show the high-level technical building blocks.

Containers:
1. "Nginx": Reverse proxy / Load balancer. Handles SSL and static assets.
2. "Web Application": Ruby on Rails (Puma). Core logic, renders UI, handles API.
3. "Streaming API": Node.js. Handles persistent WebSocket connections for real-time updates.
4. "Sidekiq Workers": Ruby background jobs. Handles federation, email sending, media processing.
5. "PostgreSQL": Primary relational database. Stores user data, statuses, follows.
6. "Redis": In-memory data store. Used for Sidekiq job queues, home feed cache.
7. "Elasticsearch" (Optional): Full-text search engine.

Key Interactions:
- Nginx -> Forwards requests -> Web Application & Streaming API
- Web Application -> Reads/Writes -> PostgreSQL
- Web Application -> Enqueues jobs -> Redis
- Sidekiq Workers -> Consumes jobs -> Redis
- Sidekiq Workers -> Reads/Writes -> PostgreSQL
- Web Application -> Search queries -> Elasticsearch

LEVEL 3: COMPONENT DIAGRAM
--------------------------
Scope: Inside the "Web Application" Container.
Goal: Show the major logical components of the Rails monolith.

Components:
1. "Authentication": Devise/OAuth2 logic.
2. "REST API Controller": Handles JSON requests from clients.
3. "ActivityPub Controller": Handles incoming federation payloads.
4. "Account Manager": User profile logic, settings.
5. "Status Manager": Logic for creating, deleting, and editing toots.
6. "Timeline Aggregator": Builds home/local/federated timelines.
7. "Notification Service": Generates alerts for mentions/follows.
8. "Media Handler": Validates and uploads file attachments.

Interactions:
- REST API Controller -> Uses -> Status Manager
- ActivityPub Controller -> Uses -> Status Manager
- Status Manager -> Uses -> Notification Service
- Media Handler -> Uploads to -> Object Storage (External)
EOF

chown ga:ga /home/ga/Desktop/mastodon_architecture_spec.txt

# 3. Record Timestamp for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io
echo "Launching draw.io..."
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio"; 
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"; 
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

# Launch with no sandbox and disabled updates
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window found."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss startup dialog (Esc creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="