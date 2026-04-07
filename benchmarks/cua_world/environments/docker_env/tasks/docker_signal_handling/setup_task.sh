#!/bin/bash
set -e
echo "=== Setting up Docker Signal Handling Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_docker

# ── Prepare Project Directory ────────────────────────────────────────────────
PROJECT_DIR="/home/ga/projects/signal-fix"
mkdir -p "$PROJECT_DIR/webserver"
mkdir -p "$PROJECT_DIR/scheduler"
mkdir -p "$PROJECT_DIR/processor"

# ── 1. Webserver: Shell-form CMD issue ───────────────────────────────────────
# The app handles signals, but /bin/sh (PID 1) won't forward them
cat > "$PROJECT_DIR/webserver/server.py" <<'EOF'
import http.server
import socketserver
import signal
import sys
import time

def handle_sigterm(signum, frame):
    print("Received SIGTERM, shutting down gracefully...", flush=True)
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)

PORT = 8080
Handler = http.server.SimpleHTTPRequestHandler

print(f"Serving on port {PORT}", flush=True)
# Busy wait loop to simulate work and allow signal handling
# (http.server serve_forever can be tricky with signals in some python versions)
try:
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        while True:
            httpd.handle_request()
except Exception:
    pass
EOF

cat > "$PROJECT_DIR/webserver/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY server.py .
# BUG: Shell form CMD runs as /bin/sh -c "python3 ...", swallowing signals
CMD python3 /app/server.py
EOF

# ── 2. Scheduler: Missing exec in entrypoint ─────────────────────────────────
cat > "$PROJECT_DIR/scheduler/scheduler.py" <<'EOF'
import time
import signal
import sys

def handle_sigterm(signum, frame):
    print("Scheduler received SIGTERM. Saving state and exiting...", flush=True)
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)

print("Scheduler started.", flush=True)
while True:
    print("Running scheduled task...", flush=True)
    time.sleep(5)
EOF

cat > "$PROJECT_DIR/scheduler/entrypoint.sh" <<'EOF'
#!/bin/bash
echo "Initializing environment..."
export ENV=production
# BUG: Missing 'exec', so bash remains PID 1 and python is a child
python3 /app/scheduler.py
EOF
chmod +x "$PROJECT_DIR/scheduler/entrypoint.sh"

cat > "$PROJECT_DIR/scheduler/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY scheduler.py .
COPY entrypoint.sh .
ENTRYPOINT ["/app/entrypoint.sh"]
EOF

# ── 3. Processor: Missing Init System (Zombies) ──────────────────────────────
cat > "$PROJECT_DIR/processor/processor.py" <<'EOF'
import time
import signal
import sys
import subprocess
import os

children = []

def handle_sigterm(signum, frame):
    print("Processor received SIGTERM. Terminating children...", flush=True)
    for p in children:
        p.terminate()
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)

print("Processor parent started.", flush=True)
# Spawn a child process to simulate work
p = subprocess.Popen(["sleep", "3600"])
children.append(p)

while True:
    time.sleep(1)
    # Without an init system, if this parent dies or if children finish, 
    # they might become zombies if not reaped.
    # In this task, the main issue is that even if this script handles SIGTERM,
    # without Tini/init, signal handling in complex process trees (especially with
    # shell wrappers or intermediate scripts) is fragile.
    # But strictly for this task: The bug is usually that the container runs
    # as PID 1 without init, and sometimes signals don't behave as expected
    # or zombies accumulate.
    pass
EOF

cat > "$PROJECT_DIR/processor/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY processor.py .
# Using exec form is good, but without init, zombie reaping is an issue
CMD ["python3", "/app/processor.py"]
EOF

chown -R ga:ga "$PROJECT_DIR"

# ── Build and Run Broken Containers ──────────────────────────────────────────
echo "Building initial images..."
docker build -t acme-webserver:current "$PROJECT_DIR/webserver" >/dev/null
docker build -t acme-scheduler:current "$PROJECT_DIR/scheduler" >/dev/null
docker build -t acme-processor:current "$PROJECT_DIR/processor" >/dev/null

echo "Starting broken containers..."
docker run -d --name acme-webserver acme-webserver:current
docker run -d --name acme-scheduler acme-scheduler:current
docker run -d --name acme-processor acme-processor:current

# ── Setup User Environment ───────────────────────────────────────────────────
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
date +%s > /tmp/task_start_time

# Launch terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/signal-fix && echo \"Signal Handling Debug Task\"; echo \"Current status:\"; docker ps; echo; echo \"Try stopping a container to see the issue:\"; echo \"time docker stop acme-webserver\"; echo; exec bash'" > /tmp/terminal.log 2>&1 &

sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="