#!/bin/bash
echo "=== Setting up PowerShell Obfuscation Rule Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data Directory
DATA_DIR="/home/ga/data"
mkdir -p "$DATA_DIR"
chown ga:ga "$DATA_DIR"

# 2. Create Sample Log File (Real Windows Event Log format)
# Contains one malicious sample (Base64) and one benign sample
cat > "$DATA_DIR/powershell_samples.json" << 'EOF'
{"win":{"system":{"providerName":"Microsoft-Windows-Security-Auditing","eventID":"4688","level":"0","task":"13312","keywords":"0x8020000000000000","systemTime":"2023-10-25T14:22:12.123456700Z","eventRecordID":"12345","channel":"Security","computer":"WIN-ENDPOINT-01","severityValue":"AUDIT_SUCCESS","message":"A new process has been created."},"eventdata":{"subjectUserSid":"S-1-5-21-123456789-1001","subjectUserName":"Admin","newProcessName":"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe","processId":"0x4d2","commandLine":"powershell.exe -NoP -NonI -W Hidden -enc JABzAD0ATgBlAHcALQBPAGIAagBlAGMAdAAgAEkATwAuAE0AZQBtAG8AcgB5AFMAdAByAGUAYQBtACgAWwBDAG8AbgB2AGUAcgB0AF0AOgA6AEYAcgBvAG0AQgBhAHMAZQA2ADQAUwB0AHIAaQBuAGcAKAAiAEgANABzAEkAQQBB...","parentProcessName":"C:\\Windows\\explorer.exe"}}}
{"win":{"system":{"providerName":"Microsoft-Windows-Security-Auditing","eventID":"4688","level":"0","task":"13312","keywords":"0x8020000000000000","systemTime":"2023-10-25T14:25:00.000000000Z","eventRecordID":"12346","channel":"Security","computer":"WIN-ENDPOINT-01","severityValue":"AUDIT_SUCCESS","message":"A new process has been created."},"eventdata":{"subjectUserSid":"S-1-5-21-123456789-1001","subjectUserName":"Admin","newProcessName":"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe","processId":"0x4d3","commandLine":"powershell.exe -ExecutionPolicy Bypass -File C:\\Scripts\\DailyBackup.ps1","parentProcessName":"C:\\Windows\\System32\\cmd.exe"}}}
EOF
chown ga:ga "$DATA_DIR/powershell_samples.json"

# 3. Ensure Wazuh Manager is running
echo "Checking Wazuh Manager..."
docker start "${WAZUH_MANAGER_CONTAINER}" 2>/dev/null || true
wait_for_service "Wazuh Manager" "docker exec ${WAZUH_MANAGER_CONTAINER} /var/ossec/bin/wazuh-control status | grep -q running" 60

# 4. Clean up any previous attempt at rule 100300
echo "Cleaning previous rules..."
docker exec "${WAZUH_MANAGER_CONTAINER}" sed -i '/id="100300"/d' /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true

# 5. Open Terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$DATA_DIR &"
fi

# 6. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
# Record initial hash of local_rules.xml to detect changes
docker exec "${WAZUH_MANAGER_CONTAINER}" md5sum /var/ossec/etc/rules/local_rules.xml > /tmp/initial_rules_hash.txt

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="