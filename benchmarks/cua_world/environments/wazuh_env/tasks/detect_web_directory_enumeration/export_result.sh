#!/bin/bash
echo "=== Exporting Detect Web Directory Enumeration Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
RESULT_FILE="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- 1. Check if Nginx is installed ---
echo "Checking Nginx installation..."
if docker exec "${CONTAINER}" dpkg -s nginx >/dev/null 2>&1; then
    NGINX_INSTALLED="true"
else
    NGINX_INSTALLED="false"
fi

# --- 2. Check ossec.conf configuration ---
echo "Checking ossec.conf..."
OSSEC_CONF_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/ossec.conf 2>/dev/null)
if echo "$OSSEC_CONF_CONTENT" | grep -q "/var/log/nginx/access.log"; then
    LOG_CONFIGURED="true"
else
    LOG_CONFIGURED="false"
fi

# --- 3. Check local_rules.xml configuration ---
echo "Checking local_rules.xml..."
RULES_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null)

# Check specific attributes using grep (simple XML parsing)
HAS_RULE_ID=$(echo "$RULES_CONTENT" | grep -q 'id="100500"' && echo "true" || echo "false")
HAS_LEVEL=$(echo "$RULES_CONTENT" | grep -q 'level="10"' && echo "true" || echo "false")
HAS_PARENT=$(echo "$RULES_CONTENT" | grep -q 'if_sid="31101"' && echo "true" || echo "false")
HAS_FREQ=$(echo "$RULES_CONTENT" | grep -q 'frequency="15"' && echo "true" || echo "false")
HAS_TIMEFRAME=$(echo "$RULES_CONTENT" | grep -q 'timeframe="60"' && echo "true" || echo "false")
HAS_SAME_IP=$(echo "$RULES_CONTENT" | grep -q '<same_source_ip' && echo "true" || echo "false")

# --- 4. Functional Verification: Simulate Attack ---
ATTACK_DETECTED="false"

if [ "$NGINX_INSTALLED" = "true" ] && [ "$LOG_CONFIGURED" = "true" ] && [ "$HAS_RULE_ID" = "true" ]; then
    echo "Prerequisites met. Launching simulated attack..."
    
    # Ensure nginx is actually running
    docker exec "${CONTAINER}" service nginx start 2>/dev/null || true
    sleep 2
    
    # Generate 404s
    # We use a loop inside the container to avoid network complexity
    # Generating 20 requests (threshold is 15)
    echo "Generating 404 traffic..."
    docker exec "${CONTAINER}" bash -c "for i in {1..20}; do curl -s -o /dev/null http://localhost/scan_test_\$i; done"
    
    echo "Waiting for Wazuh to process logs (15s)..."
    sleep 15
    
    # Check alerts.json for the specific rule firing AFTER our traffic generation
    # We simply check if the alert exists in the file for now, assuming clean state or timestamp check
    # For robustness, we grep the last 50 lines
    RECENT_ALERTS=$(docker exec "${CONTAINER}" tail -n 50 /var/ossec/logs/alerts/alerts.json)
    
    if echo "$RECENT_ALERTS" | grep -q '"rule":{"level":10,"description":"High frequency of 404 errors - Possible Directory Enumeration","id":"100500"'; then
        ATTACK_DETECTED="true"
        echo "Alert 100500 found in recent alerts!"
    else
        echo "Alert 100500 NOT found in recent alerts."
        # Debug: print recent alerts to log
        echo "Recent alerts debug:"
        echo "$RECENT_ALERTS" | grep "\"id\":\"100500\"" || echo "No ID 100500 found"
    fi
else
    echo "Skipping attack simulation due to missing configuration."
fi

# --- 5. Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- 6. Generate JSON Result ---
cat > "${RESULT_FILE}" << EOF
{
    "nginx_installed": ${NGINX_INSTALLED},
    "log_configured": ${LOG_CONFIGURED},
    "rule_exists": ${HAS_RULE_ID},
    "rule_level_correct": ${HAS_LEVEL},
    "rule_parent_correct": ${HAS_PARENT},
    "rule_frequency_correct": ${HAS_FREQ},
    "rule_timeframe_correct": ${HAS_TIMEFRAME},
    "rule_same_ip_correct": ${HAS_SAME_IP},
    "attack_detected": ${ATTACK_DETECTED},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 "${RESULT_FILE}"
echo "Export complete. Result:"
cat "${RESULT_FILE}"