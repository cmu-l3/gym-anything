#!/bin/bash
set -e
echo "=== Setting up TLS Handshake Audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

CAPTURE_FILE="/home/ga/Documents/captures/tls_traffic.pcap"
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Clean up previous run
rm -f /home/ga/Documents/tls_audit_report.txt 2>/dev/null || true
rm -f "$CAPTURE_FILE" 2>/dev/null || true

# --- Generate Real TLS Traffic ---
echo "Generating real TLS traffic capture..."
# Start capture in background
tcpdump -i any -w "$CAPTURE_FILE" port 443 &
TCPDUMP_PID=$!
sleep 2

# Make HTTPS requests to diverse public endpoints to generate realistic noise/signals
# We use curl with max-time to avoid hanging
TARGETS=(
    "https://www.google.com"
    "https://www.example.com"
    "https://www.wikipedia.org"
    "https://www.cloudflare.com"
    "https://api.github.com"
)

echo "Generating HTTPS requests..."
for url in "${TARGETS[@]}"; do
    curl -s -o /dev/null -m 5 "$url" 2>/dev/null || true
    sleep 0.5
done

# Wait for buffers to flush
sleep 3
kill "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true
sleep 1

# Verify we caught something
PACKET_COUNT=$(tshark -r "$CAPTURE_FILE" 2>/dev/null | wc -l)
if [ "$PACKET_COUNT" -lt 10 ]; then
    echo "WARNING: Capture file is too small ($PACKET_COUNT packets). Using backup sample."
    # Fallback to the pre-installed http.cap if generation fails (unlikely but safe)
    cp /home/ga/Documents/captures/http.cap "$CAPTURE_FILE"
fi

# Set permissions
chown ga:ga "$CAPTURE_FILE"
chmod 644 "$CAPTURE_FILE"

# --- Compute Ground Truth (Hidden) ---
echo "Computing ground truth..."

# 1. Count Client Hellos (type 1)
GT_CLIENT_HELLOS=$(tshark -r "$CAPTURE_FILE" -Y "tls.handshake.type == 1" 2>/dev/null | wc -l)
echo "$GT_CLIENT_HELLOS" > "$GROUND_TRUTH_DIR/client_hello_count.txt"

# 2. Count Server Hellos (type 2) - representing completed handshakes
GT_SERVER_HELLOS=$(tshark -r "$CAPTURE_FILE" -Y "tls.handshake.type == 2" 2>/dev/null | wc -l)
echo "$GT_SERVER_HELLOS" > "$GROUND_TRUTH_DIR/server_hello_count.txt"

# 3. Extract SNI hostnames
tshark -r "$CAPTURE_FILE" -Y "tls.handshake.type == 1" \
    -T fields -e tls.handshake.extensions_server_name 2>/dev/null | \
    tr ',' '\n' | sort -u | sed '/^$/d' > "$GROUND_TRUTH_DIR/sni_list.txt"

# 4. Extract Client Hello Record Layer Versions
tshark -r "$CAPTURE_FILE" -Y "tls.handshake.type == 1" \
    -T fields -e tls.record.version 2>/dev/null | \
    tr ',' '\n' | sort -u | sed '/^$/d' > "$GROUND_TRUTH_DIR/tls_versions.txt"

# 5. Extract Server Selected Cipher Suites
tshark -r "$CAPTURE_FILE" -Y "tls.handshake.type == 2" \
    -T fields -e tls.handshake.ciphersuite 2>/dev/null | \
    tr ',' '\n' | sort -u | sed '/^$/d' > "$GROUND_TRUTH_DIR/cipher_suites.txt"

# 6. Check for Weak TLS (1.0=0x0301, 1.1=0x0302)
if grep -qE "0x0301|0x0302" "$GROUND_TRUTH_DIR/tls_versions.txt"; then
    echo "Yes" > "$GROUND_TRUTH_DIR/weak_tls.txt"
else
    echo "No" > "$GROUND_TRUTH_DIR/weak_tls.txt"
fi

echo "Ground truth computed. Client Hellos: $GT_CLIENT_HELLOS"

# --- Launch Wireshark ---
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$CAPTURE_FILE' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="