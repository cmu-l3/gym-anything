#!/bin/bash
set -e
echo "=== Setting up scrub_image_secret_squash task ==="

source /workspace/scripts/task_utils.sh

# Ensure Docker is ready
wait_for_docker_daemon 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any existing images to ensure clean state
docker rmi legacy-app:unsafe legacy-app:safe 2>/dev/null || true

# Create build context
BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

# 1. Create the application
cat > app.py << 'EOF'
import os
import http.server
import socketserver
import sys

# Flush output immediately for logs
sys.stdout.reconfigure(line_buffering=True)

PORT = int(os.environ.get("PORT", 8080))
COLOR = os.environ.get("APP_COLOR", "unknown")

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        response = f"Status: OK\nColor: {COLOR}\n"
        self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        # Silence default logging to keep container logs clean
        pass

print(f"Starting server on port {PORT} with color {COLOR}")
http.server.HTTPServer(("", PORT), Handler).serve_forever()
EOF

# 2. Create the secret file
echo "AWS_ACCESS_KEY_ID=AKIA_TEST_SECRET_DO_NOT_USE" > secrets.txt

# 3. Create Dockerfile with the flaw (Add then Delete)
cat > Dockerfile << 'EOF'
FROM python:3.11-alpine
WORKDIR /app

# Install dependencies (none needed for standard lib, but good practice)
# RUN pip install requests

# Layer: Copy app
COPY app.py .

# Layer: Copy secret (The Mistake)
COPY secrets.txt .

# Layer: "Fix" the mistake (Delete file)
RUN rm secrets.txt

# Metadata that must be preserved
ENV PORT=5000
ENV APP_COLOR=blue
EXPOSE 5000
CMD ["python", "app.py"]
EOF

echo "Building unsafe image..."
docker build -t legacy-app:unsafe . > /dev/null

# Clean up source files so agent can't just rebuild from them easily
# (Agent must work from the image artifact)
cd ~
rm -rf "$BUILD_DIR"

# Focus Docker Desktop
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Unsafe image 'legacy-app:unsafe' created."
echo "The secret 'AKIA_TEST_SECRET_DO_NOT_USE' is buried in the history."