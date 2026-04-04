#!/bin/bash
# Setup script for HTTP Session Reconstruction task
echo "=== Setting up HTTP Session Reconstruction ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

rm -f /tmp/task_result.json /tmp/ground_truth_* /tmp/initial_* /tmp/task_start_*

PCAP="/home/ga/Documents/captures/http.cap"

if [ ! -f "$PCAP" ]; then
    echo "ERROR: $PCAP not found!"
    exit 1
fi

rm -f /home/ga/Documents/captures/http_analysis_report.txt

# --- Compute ground truth using tshark ---

# HTTP request URIs
GT_URIS=$(tshark -r "$PCAP" -Y "http.request" -T fields -e http.request.uri 2>/dev/null | sort -u)
echo "$GT_URIS" > /tmp/ground_truth_http_uris

# HTTP request methods + URIs for richer matching
GT_REQUESTS=$(tshark -r "$PCAP" -Y "http.request" -T fields -e http.request.method -e http.request.uri -e http.host 2>/dev/null)
echo "$GT_REQUESTS" > /tmp/ground_truth_http_requests

# Web server IP (destination IP of HTTP requests)
GT_SERVER_IP=$(tshark -r "$PCAP" -Y "http.request" -T fields -e ip.dst 2>/dev/null | sort -u | head -1)
echo "$GT_SERVER_IP" > /tmp/ground_truth_http_server_ip

# HTTP response status codes
GT_STATUS_CODES=$(tshark -r "$PCAP" -Y "http.response" -T fields -e http.response.code 2>/dev/null | sort -u)
echo "$GT_STATUS_CODES" > /tmp/ground_truth_http_status_codes

# User-Agent string
GT_USER_AGENT=$(tshark -r "$PCAP" -Y "http.user_agent" -T fields -e http.user_agent 2>/dev/null | sort -u | head -1)
echo "$GT_USER_AGENT" > /tmp/ground_truth_http_user_agent

# Total HTTP request packets
GT_REQUEST_COUNT=$(tshark -r "$PCAP" -Y "http.request" 2>/dev/null | wc -l)
echo "$GT_REQUEST_COUNT" > /tmp/ground_truth_http_request_count

# Host header
GT_HOST=$(tshark -r "$PCAP" -Y "http.host" -T fields -e http.host 2>/dev/null | sort -u | head -1)
echo "$GT_HOST" > /tmp/ground_truth_http_host

date +%s > /tmp/task_start_timestamp

echo "Ground truth computed:"
echo "  URIs: $(echo "$GT_URIS" | wc -l) unique"
echo "  Server IP: $GT_SERVER_IP"
echo "  Status codes: $GT_STATUS_CODES"
echo "  User-Agent: $(echo "$GT_USER_AGENT" | head -c 50)..."
echo "  HTTP requests: $GT_REQUEST_COUNT"
echo "  Host: $GT_HOST"

# Launch Wireshark
pkill -f wireshark 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 wireshark '$PCAP' > /tmp/wireshark_task.log 2>&1 &"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
