#!/bin/bash
echo "=== Setting up upload_seb_certificate task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/initial_cert_count.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Generate real X.509 certificate for the agent to upload
echo "Generating X.509 certificate..."
mkdir -p /home/ga/Documents
openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/seb_exam_key.pem \
    -out /home/ga/Documents/seb_exam_cert.pem \
    -days 365 -nodes \
    -subj "/C=US/ST=Massachusetts/L=Boston/O=State University/OU=IT Security/CN=UniversityExamCert2025" 2>/dev/null

chown ga:ga /home/ga/Documents/seb_exam_cert.pem
chmod 644 /home/ga/Documents/seb_exam_cert.pem

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline certificate count
CERT_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM certificate" 2>/dev/null || echo "0")
echo "$CERT_COUNT" > /tmp/initial_cert_count.txt
echo "Baseline certificate count: $CERT_COUNT"

# Launch Firefox and navigate to SEB Server
launch_firefox "http://localhost:8080"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should upload '~/Documents/seb_exam_cert.pem' with alias 'UniversityExamCert2025'"