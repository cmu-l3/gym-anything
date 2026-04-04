#!/bin/bash
set -e

echo "=== Setting up configure_strict_capture_filter task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create capture directory
mkdir -p /home/ga/Documents/captures/

# Remove previous output file if it exists
rm -f /home/ga/Documents/captures/icmp_strict.pcapng 2>/dev/null || true

# Start background noise generator (HTTP traffic)
# We use a python simple HTTP server on localhost and curl it to generate TCP traffic
# This ensures we have noise on the loopback or eth0 interface depending on routing
# To be safe for eth0 capture tests, we'll also curl an external site
echo "Starting background network noise..."

# 1. Start a local noise sink (just to be sure we have local traffic)
nohup python3 -m http.server 8888 > /dev/null 2>&1 &
HTTP_PID=$!
echo "$HTTP_PID" > /tmp/noise_http_server.pid

# 2. Start a traffic generator loop
# It alternates between local and external to ensure traffic appears on likely interfaces
cat > /tmp/noise_generator.sh << 'EOF'
#!/bin/bash
while true; do
    # Generate TCP traffic (noise)
    curl -s --max-time 1 http://127.0.0.1:8888 >/dev/null 2>&1
    curl -s --max-time 1 http://Example.com >/dev/null 2>&1
    # Sleep short enough to ensure constant noise, long enough to not freeze CPU
    sleep 0.2
done
EOF

chmod +x /tmp/noise_generator.sh
nohup /tmp/noise_generator.sh > /dev/null 2>&1 &
GEN_PID=$!
echo "$GEN_PID" > /tmp/noise_generator.pid

echo "Background noise generator running (PID: $GEN_PID)"

# Launch Wireshark
echo "Launching Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
            echo "Wireshark window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize Wireshark
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open a terminal for the user to run ping (convenience)
echo "Opening terminal for user..."
su - ga -c "DISPLAY=:1 gnome-terminal --geometry=80x24+200+200 &"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="