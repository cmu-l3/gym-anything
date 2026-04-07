#!/bin/bash
set -e
echo "=== Setting up Secure Scratch Build Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for wait_for_docker
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

wait_for_docker

# Record task start time
date +%s > /tmp/task_start_timestamp

# Create project directory
PROJECT_DIR="/home/ga/projects/payment-validator"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# 1. Create the Go application source code
cat > "$PROJECT_DIR/main.go" << 'GOEOF'
package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	fmt.Println("Starting Payment Validator Service v1.0...")
	
	// Wait a moment for network stack
	time.Sleep(1 * time.Second)

	fmt.Println("Performing self-check: HTTPS connectivity...")
	// This will fail if CA certs are missing
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://www.google.com")
	if err != nil {
		fmt.Printf("FATAL: HTTPS check failed: %v\n", err)
		fmt.Println("Hint: Did you copy /etc/ssl/certs/ca-certificates.crt to the scratch image?")
		os.Exit(1)
	}
	defer resp.Body.Close()
	
	fmt.Printf("HTTPS check passed. Status: %s\n", resp.Status)
	fmt.Println("Certificates are valid.")

	// Simulate a service
	fmt.Println("Listening on :8080")
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Payment Validator Ready")
	})
	
	// ListenAndServe blocks forever
	if err := http.ListenAndServe(":8080", nil); err != nil {
		fmt.Printf("Server failed: %v\n", err)
		os.Exit(1)
	}
}
GOEOF

# 2. Create go.mod
cat > "$PROJECT_DIR/go.mod" << 'MODEOF'
module payment-validator

go 1.21
MODEOF

# 3. Create the "BAD" Dockerfile (The starting point for the agent)
# Intentionally bad: Ubuntu base, apt-get, root user, dynamic build
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE'
# TODO: Refactor this to use a multi-stage build and FROM scratch
FROM ubuntu:22.04

# Install Go (very inefficient way)
RUN apt-get update && apt-get install -y golang-go ca-certificates

WORKDIR /app

# Copy source
COPY . .

# Build dynamically (default)
RUN go build -o main .

# Run as root (default)
EXPOSE 8080
CMD ["./main"]
DOCKERFILE

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Prepare terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/payment-validator && echo \"Secure Scratch Build Task\"; echo \"Current Dockerfile is insecure and bloated.\"; echo \"Goal: Refactor to use FROM scratch, < 20MB, non-root user, static binary.\"; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="