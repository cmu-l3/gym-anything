#!/bin/bash
set -e

echo "=== Setting up k8s_cluster_state_viz task ==="

# Define directories
DESKTOP_DIR="/home/ga/Desktop"
DIAGRAMS_DIR="/home/ga/Diagrams"
mkdir -p "$DESKTOP_DIR" "$DIAGRAMS_DIR"

# Clean up previous runs
rm -f "$DESKTOP_DIR/cluster_dump.json"
rm -f "$DIAGRAMS_DIR/cluster_state.drawio"
rm -f "$DIAGRAMS_DIR/cluster_state.png"

# Generate the Kubernetes Cluster Dump JSON
# This script creates a realistic dataset with:
# - 3 Nodes
# - 15 Pods distributed unevenly
# - One pod in CrashLoopBackOff
# - Varied CPU requests
python3 -c '
import json
import random

data = {
    "cluster_name": "production-us-east-1",
    "generated_at": "2023-10-27T14:30:00Z",
    "items": []
}

# Define Nodes
nodes = ["worker-us-east-1a", "worker-us-east-1b", "worker-us-east-1c"]

# Define Pods
# Node A: Light load
pods_a = [
    {"name": "frontend-01", "cpu": "100m", "status": "Running"},
    {"name": "frontend-02", "cpu": "100m", "status": "Running"},
    {"name": "redis-cache", "cpu": "200m", "status": "Running"}
]

# Node B: Critical services, one crash
pods_b = [
    {"name": "payment-service", "cpu": "300m", "status": "Running"},
    {"name": "auth-service",    "cpu": "250m", "status": "Running"},
    {"name": "user-service",    "cpu": "200m", "status": "Running"},
    {"name": "payment-db-master", "cpu": "500m", "status": "CrashLoopBackOff"}
]

# Node C: Heavy batch load (Overloaded)
pods_c = []
for i in range(8):
    pods_c.append({
        "name": f"backend-worker-{i}",
        "cpu": "300m",
        "status": "Running"
    })

all_assignments = [
    (nodes[0], pods_a),
    (nodes[1], pods_b),
    (nodes[2], pods_c)
]

for node_name, pod_list in all_assignments:
    # Add Node entry
    data["items"].append({
        "kind": "Node",
        "metadata": {"name": node_name},
        "status": {"capacity": {"cpu": "4000m", "memory": "16Gi"}}
    })
    
    # Add Pod entries
    for pod in pod_list:
        data["items"].append({
            "kind": "Pod",
            "metadata": {
                "name": pod["name"],
                "namespace": "default"
            },
            "spec": {
                "nodeName": node_name,
                "containers": [{
                    "name": "main",
                    "resources": {
                        "requests": {"cpu": pod["cpu"], "memory": "256Mi"}
                    }
                }]
            },
            "status": {
                "phase": "Running" if pod["status"] != "Pending" else "Pending",
                "containerStatuses": [{
                    "ready": pod["status"] == "Running",
                    "state": {"waiting": {"reason": pod["status"]}} if pod["status"] != "Running" else {"running": {}}
                }]
            }
        })

with open("/home/ga/Desktop/cluster_dump.json", "w") as f:
    json.dump(data, f, indent=2)

print("Created cluster_dump.json with 15 pods across 3 nodes.")
'

# Set permissions
chown ga:ga "$DESKTOP_DIR/cluster_dump.json"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch draw.io (optional convenience)
# We won't open a specific file since the user needs to create a new one,
# but having the app open saves a step.
if ! pgrep -f "drawio" > /dev/null; then
    echo "Launching draw.io..."
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"
fi

# Wait and maximize
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "draw.io" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Dismiss update dialogs aggressively
for i in {1..5}; do
    if DISPLAY=:1 wmctrl -l | grep -i "update"; then
        DISPLAY=:1 xdotool key Escape
    fi
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="