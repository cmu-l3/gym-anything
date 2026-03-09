#!/bin/bash
# Do NOT use set -e

echo "=== Setting up GitLab C4 Diagram Task ==="

# 1. Create the architecture specification file
cat > /home/ga/Desktop/gitlab_architecture_spec.txt << 'EOF'
GitLab Architecture Specification (C4 Model)
============================================

TASK: Create a C4 Container Diagram (Level 2) for the GitLab self-managed architecture.

1. ACTORS (External)
   - Developer: Uses the web interface and git CLI
   - CI/CD Runner: Polling for jobs and uploading artifacts

2. EXTERNAL SYSTEMS
   - Email Server (SMTP): For notifications
   - Identity Provider (LDAP/SAML): For user authentication

3. GITLAB CONTAINER COMPONENTS (Inside "GitLab Platform" Boundary)
   
   A. GitLab Workhorse [Go]
      - Smart reverse proxy
      - Handles file uploads/downloads and git push/pull
      - Routes API/Web requests to Puma via Unix Socket
   
   B. GitLab Puma [Ruby]
      - The core web application server
      - Handles API and Web UI requests
      - Reads/Writes to PostgreSQL
   
   C. GitLab Sidekiq [Ruby]
      - Background job processor
      - Processes queues from Redis
   
   D. Gitaly [Go]
      - Git RPC service
      - Handles all git interactions (file access)
      - Accessed via gRPC
   
   E. GitLab Shell [Go]
      - Handles SSH git operations
      - Talks to Gitaly via gRPC
   
   F. PostgreSQL
      - Primary relational database
      - Stores user data, issues, merge requests metadata
   
   G. Redis
      - Key-value store
      - Used for caching, session storage, and background job queues
   
   H. Object Storage [S3-compatible]
      - Stores artifacts, LFS objects, and uploads
   
   I. Container Registry [Go]
      - Stores Docker images pushed by users/CI
   
   J. Prometheus
      - Monitoring and metrics collection

4. KEY RELATIONSHIPS & PROTOCOLS
   - Developer -> Workhorse (HTTPS)
   - Developer -> GitLab Shell (SSH)
   - Workhorse -> Puma (Unix Socket/HTTP)
   - Puma -> Gitaly (gRPC)
   - Puma -> PostgreSQL (TCP)
   - Puma -> Redis (TCP)
   - Sidekiq -> Redis (TCP)
   - GitLab Shell -> Gitaly (gRPC)
   - Puma -> Email Server (SMTP)
   - Puma -> Identity Provider (LDAP)

INSTRUCTIONS:
- Page 1: System Context (Actors + GitLab System + External Systems)
- Page 2: Container Diagram (Zoom into GitLab System showing the 10 components above)
EOF

chown ga:ga /home/ga/Desktop/gitlab_architecture_spec.txt
chmod 644 /home/ga/Desktop/gitlab_architecture_spec.txt

# 2. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
ls -la /home/ga/Desktop/*.drawio 2>/dev/null > /tmp/initial_drawio_files.txt

# 3. Launch draw.io
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio"; 
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"; 
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# 4. Wait for window and maximize
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

sleep 3
# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="