#!/bin/bash
# Setup script for secure_build_with_buildkit_secrets

set -e
echo "=== Setting up Secure Build Task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate a random authentication token
TOKEN=$(openssl rand -hex 16)
echo "$TOKEN" > /tmp/secret_token.txt
chmod 600 /tmp/secret_token.txt
echo "Token generated."

# 2. Create Project Directory
PROJECT_DIR="/home/ga/secure-build"
mkdir -p "$PROJECT_DIR/app"
chown -R ga:ga "$PROJECT_DIR"

# 3. Create auth_token.txt for the agent
echo "$TOKEN" > "$PROJECT_DIR/auth_token.txt"
chown ga:ga "$PROJECT_DIR/auth_token.txt"

# 4. Create a dummy proprietary artifact
mkdir -p /tmp/server_root
echo "This is the proprietary library content." > /tmp/server_root/proprietary_lib.tar.gz
# Add some binary-like garbage to make it look real
head -c 1024 /dev/urandom >> /tmp/server_root/proprietary_lib.tar.gz

# 5. Create and start the Private Artifact Server (Python script)
SERVER_SCRIPT="/tmp/artifact_server.py"
cat > "$SERVER_SCRIPT" << EOF
import http.server
import socketserver
import os
import sys

PORT = 8090
TOKEN = "$TOKEN"
DIRECTORY = "/tmp/server_root"

class AuthHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        auth_header = self.headers.get('X-Auth-Token')
        if auth_header != TOKEN:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"Forbidden: Invalid or missing X-Auth-Token header")
            return
        super().do_GET()

    def log_message(self, format, *args):
        # Silence logs to keep terminal clean
        pass

with socketserver.TCPServer(("0.0.0.0", PORT), AuthHandler) as httpd:
    print(f"Serving at port {PORT}")
    httpd.serve_forever()
EOF

# Kill any existing server on port 8090
fuser -k 8090/tcp 2>/dev/null || true

# Start server in background
nohup python3 "$SERVER_SCRIPT" > /tmp/server.log 2>&1 &
echo "Artifact server started on port 8090 (PID: $!)"

# 6. Create initial Dockerfile (Naïve/Broken version)
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE'
# syntax=docker/dockerfile:1
FROM python:3.9-slim

WORKDIR /app

# COPY source code
COPY app/ .

# TODO: Download the proprietary library from http://host.docker.internal:8090/proprietary_lib.tar.gz
# You need to use the token in auth_token.txt for authentication.
# Requirements:
# 1. The token must NOT remain in the image history or env vars.
# 2. Use Docker BuildKit secrets.

CMD ["python", "app.py"]
DOCKERFILE
chown ga:ga "$PROJECT_DIR/Dockerfile"

# 7. Create dummy app code
cat > "$PROJECT_DIR/app/app.py" << 'APP'
import os
import sys

def main():
    print("Application starting...")
    if os.path.exists("proprietary_lib.tar.gz"):
        print("Library found!")
    else:
        print("Critical Error: Library missing!")
        sys.exit(1)

if __name__ == "__main__":
    main()
APP
chown -R ga:ga "$PROJECT_DIR/app"

# 8. Clean up previous images if any
docker rmi secure-app:latest 2>/dev/null || true

# 9. Ensure Docker Desktop is running and maximized
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="