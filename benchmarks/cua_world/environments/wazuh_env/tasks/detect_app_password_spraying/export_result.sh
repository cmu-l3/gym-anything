#!/bin/bash
echo "=== Exporting Password Spraying Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
RESULT_JSON="/tmp/task_result.json"
ALERTS_JSON="/var/ossec/logs/alerts/alerts.json"

# 1. Capture Final State Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Configuration Files (Static Analysis)
# This gives partial credit even if the alert doesn't fire
echo "Analyzing configuration files..."

# Check ossec.conf for log ingestion
OSSEC_CONF_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/ossec.conf 2>/dev/null)
HAS_LOG_CONFIG="false"
if echo "$OSSEC_CONF_CONTENT" | grep -q "/var/log/megacorp.log"; then
    HAS_LOG_CONFIG="true"
fi

# Check decoder for srcip and dstuser extraction
DECODER_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null)
HAS_DECODER_SRCIP="false"
HAS_DECODER_USER="false"
if echo "$DECODER_CONTENT" | grep -qi "srcip"; then HAS_DECODER_SRCIP="true"; fi
if echo "$DECODER_CONTENT" | grep -qi "dstuser"; then HAS_DECODER_USER="true"; fi

# Check rules for logic
RULES_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null)
HAS_BASE_RULE="false"
HAS_SPRAY_RULE="false"
HAS_FREQUENCY="false"
HAS_SAME_IP="false"
HAS_DIFF_USER="false"

if echo "$RULES_CONTENT" | grep -q "100501"; then HAS_BASE_RULE="true"; fi
if echo "$RULES_CONTENT" | grep -q "100502"; then HAS_SPRAY_RULE="true"; fi
if echo "$RULES_CONTENT" | grep -q 'frequency="5"'; then HAS_FREQUENCY="true"; fi
if echo "$RULES_CONTENT" | grep -q 'same_source_ip'; then HAS_SAME_IP="true"; fi
# Accept either different_dstuser or different_target_user (synonyms in some contexts, though dstuser is correct for decoder field)
if echo "$RULES_CONTENT" | grep -qE 'different_dstuser|different_target_user'; then HAS_DIFF_USER="true"; fi

# 3. Dynamic Verification: Run Simulation and Check for Alerts
echo "Running attack simulation..."
# Count existing alerts for rule 100502
INITIAL_ALERT_COUNT=$(docker exec "${CONTAINER}" grep '"rule":{"id":"100502"' "$ALERTS_JSON" 2>/dev/null | wc -l)

# Run the generation script
/home/ga/generate_logs.sh

# Wait for processing (Wazuh analysisd buffer)
sleep 15

# Count alerts again
FINAL_ALERT_COUNT=$(docker exec "${CONTAINER}" grep '"rule":{"id":"100502"' "$ALERTS_JSON" 2>/dev/null | wc -l)

ALERT_FIRED="false"
if [ "$FINAL_ALERT_COUNT" -gt "$INITIAL_ALERT_COUNT" ]; then
    ALERT_FIRED="true"
fi

# 4. Check if manager is running
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" ps ax | grep -q "wazuh-analysisd"; then
    MANAGER_RUNNING="true"
fi

# 5. Compile Result JSON
# Use Python to generate safe JSON
python3 -c "
import json
result = {
    'config': {
        'log_ingestion': $HAS_LOG_CONFIG,
        'decoder_srcip': $HAS_DECODER_SRCIP,
        'decoder_user': $HAS_DECODER_USER,
        'base_rule': $HAS_BASE_RULE,
        'spray_rule': $HAS_SPRAY_RULE,
        'logic_frequency': $HAS_FREQUENCY,
        'logic_same_ip': $HAS_SAME_IP,
        'logic_diff_user': $HAS_DIFF_USER
    },
    'runtime': {
        'manager_running': $MANAGER_RUNNING,
        'alert_fired': $ALERT_FIRED,
        'initial_alerts': $INITIAL_ALERT_COUNT,
        'final_alerts': $FINAL_ALERT_COUNT
    },
    'timestamp': '$(date +%s)'
}
print(json.dumps(result, indent=2))
" > "$RESULT_JSON"

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"