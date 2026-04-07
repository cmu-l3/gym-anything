#!/bin/bash
echo "=== Setting up Secure HMAC Webhook Receiver Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up output directory
echo "Cleaning output directory..."
rm -rf /home/ga/appointments
mkdir -p /home/ga/appointments
chown -R ga:ga /home/ga/appointments

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Open a terminal with helper info
# We provide the Java imports hints to make the task solvable without external docs lookup
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " Secure Webhook Implementation Task"
echo "======================================================="
echo ""
echo "GOAL: Create channel 'CloudBook_Webhook' on Port 6675"
echo "      Validate X-Signature header (HMAC-SHA256)"
echo "      Secret: HealthSecure2025"
echo ""
echo "Java Helper Snippet for Mirth JavaScript:"
echo "-------------------------------------------------------"
echo "importPackage(javax.crypto);"
echo "importPackage(javax.crypto.spec);"
echo "importPackage(org.apache.commons.codec.binary);"
echo ""
echo "// function calculateHMAC(data, secret) {"
echo "//     var algorithm = 'HmacSHA256';"
echo "//     var mac = Mac.getInstance(algorithm);"
echo "//     var key = new SecretKeySpec(secret.getBytes(), algorithm);"
echo "//     mac.init(key);"
echo "//     var digest = mac.doFinal(data.getBytes());"
echo "//     return Hex.encodeHexString(digest);"
echo "// }"
echo "-------------------------------------------------------"
echo ""
echo "Test your channel using curl:"
echo "curl -v -H \"X-Signature: <hash>\" -d @payload.json http://localhost:6675"
echo ""
echo "Useful paths:"
echo "  Output: /home/ga/appointments/"
echo "  Logs: /opt/connect/logs/mirth.log"
echo ""
exec bash
' 2>/dev/null &

# 4. Wait for NextGen Connect API to be ready
echo "Waiting for API..."
wait_for_api 60

echo "=== Setup Complete ==="