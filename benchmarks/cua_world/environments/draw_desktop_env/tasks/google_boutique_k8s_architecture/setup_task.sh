#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up google_boutique_k8s_architecture task ==="

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

# Clean up previous run artifacts
rm -f /home/ga/Desktop/boutique_architecture.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/boutique_architecture.png 2>/dev/null || true

# Create the Service Manifest YAML
# Data sourced from: https://github.com/GoogleCloudPlatform/microservices-demo
cat > /home/ga/Desktop/boutique_services.yaml << 'YAMLEOF'
# Google Online Boutique - Service Manifest
# Source: GoogleCloudPlatform/microservices-demo

services:
  - name: frontend
    language: Go
    port: 8080
    type: Service (LoadBalancer/Ingress)
    dependencies:
      - service: cartservice
        protocol: gRPC
      - service: productcatalogservice
        protocol: gRPC
      - service: currencyservice
        protocol: gRPC
      - service: recommendationservice
        protocol: gRPC
      - service: shippingservice
        protocol: gRPC
      - service: checkoutservice
        protocol: gRPC
      - service: adservice
        protocol: gRPC

  - name: cartservice
    language: C#
    port: 7070
    type: Service
    dependencies:
      - service: redis-cart
        protocol: TCP

  - name: productcatalogservice
    language: Go
    port: 3550
    type: Service
    dependencies: []

  - name: currencyservice
    language: Node.js
    port: 7000
    type: Service
    dependencies: []

  - name: paymentservice
    language: Node.js
    port: 50051
    type: Service
    dependencies: []

  - name: shippingservice
    language: Go
    port: 50051
    type: Service
    dependencies: []

  - name: emailservice
    language: Python
    port: 8080
    type: Service
    dependencies: []

  - name: checkoutservice
    language: Go
    port: 5050
    type: Service
    dependencies:
      - service: cartservice
        protocol: gRPC
      - service: productcatalogservice
        protocol: gRPC
      - service: currencyservice
        protocol: gRPC
      - service: shippingservice
        protocol: gRPC
      - service: paymentservice
        protocol: gRPC
      - service: emailservice
        protocol: gRPC

  - name: recommendationservice
    language: Python
    port: 8080
    type: Service
    dependencies:
      - service: productcatalogservice
        protocol: gRPC

  - name: adservice
    language: Java
    port: 9555
    type: Service
    dependencies: []

  - name: loadgenerator
    language: Python/Locust
    type: Workload
    dependencies:
      - service: frontend
        protocol: HTTP

infrastructure:
  - name: redis-cart
    type: Data Store (Redis)
    port: 6379

  - name: ingress-gateway
    type: Ingress
    protocol: HTTP/HTTPS
YAMLEOF

chown ga:ga /home/ga/Desktop/boutique_services.yaml
echo "Created manifest at /home/ga/Desktop/boutique_services.yaml"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window for consistent layout
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the "Open / Create" dialog to start with a blank canvas (or let agent handle it)
# We'll press Escape to close the dialog, leaving the user with the option to create new
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="