#!/bin/bash
# Setup script for multi_arch_build_pipeline
# Prepares the Go application source code and ensures a clean environment

echo "=== Setting up Multi-Arch Build Pipeline Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

# Wait for Docker daemon
echo "Waiting for Docker daemon..."
wait_for_docker_daemon 60

# Clean up any previous state
echo "Cleaning up previous state..."
docker rm -f registry 2>/dev/null || true
docker buildx rm agent-builder 2>/dev/null || true
# Remove any existing builder that isn't default
docker buildx rm $(docker buildx ls -q | grep -v default) 2>/dev/null || true

# Prepare application directory
APP_DIR="/home/ga/edge-app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

# Create Go Source Code
cat > "$APP_DIR/main.go" << 'GOEOF'
package main

import (
    "fmt"
    "net/http"
    "runtime"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello! I am running on %s/%s\n", runtime.GOOS, runtime.GOARCH)
    })
    
    fmt.Println("Server starting on :8080...")
    if err := http.ListenAndServe(":8080", nil); err != nil {
        fmt.Printf("Server failed: %s\n", err)
    }
}
GOEOF

# Create Dockerfile
cat > "$APP_DIR/Dockerfile" << 'DOCKERFILE'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
# Build using the automatic TARGETOS and TARGETARCH arguments provided by BuildKit
ARG TARGETOS
ARG TARGETARCH
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o edge-app .

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/edge-app .
EXPOSE 8080
CMD ["./edge-app"]
DOCKERFILE

# Set permissions
chown -R ga:ga "$APP_DIR"

# Focus Docker Desktop window
focus_docker_desktop

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "App created at: $APP_DIR"
echo "Ready for agent."