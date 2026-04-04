#!/bin/bash
echo "=== Exporting Configure Reverse Proxy results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence)
take_screenshot /tmp/task_final.png

# 2. Gather Configuration State
# Check enabled modules
MOD_PROXY=$(apache2ctl -M 2>/dev/null | grep -c "proxy_module" || echo "0")
MOD_PROXY_HTTP=$(apache2ctl -M 2>/dev/null | grep -c "proxy_http_module" || echo "0")

# Check config files for directives (regex search)
# Looking for: ProxyPass /app http://localhost:3001/ (or 127.0.0.1)
CONFIG_PROXYPASS=$(grep -rE "ProxyPass\s+/app\s+http://(localhost|127\.0\.0\.1):3001" /etc/apache2/sites-enabled/ 2>/dev/null | wc -l)
CONFIG_PROXYPASS_REVERSE=$(grep -rE "ProxyPassReverse\s+/app\s+http://(localhost|127\.0\.0\.1):3001" /etc/apache2/sites-enabled/ 2>/dev/null | wc -l)

# 3. Perform End-to-End Test
# Ensure backend is still running (it might have crashed or been killed)
if ! curl -s http://localhost:3001/ | grep -q "BACKEND_RESPONSE_OK"; then
    echo "Backend server died, restarting for verification..."
    nohup python3 /tmp/backend_server.py > /dev/null 2>&1 &
    sleep 2
fi

# Test 1: Curl with Host header
RESPONSE_HOST=$(curl -s -L --max-time 5 -H "Host: acmecorp.test" http://localhost/app 2>/dev/null || echo "failed")

# Test 2: Curl via domain (if resolved)
RESPONSE_DOMAIN=$(curl -s -L --max-time 5 http://acmecorp.test/app 2>/dev/null || echo "failed")

# Check matches
E2E_SUCCESS="false"
if echo "$RESPONSE_HOST" | grep -q "BACKEND_RESPONSE_OK"; then
    E2E_SUCCESS="true"
elif echo "$RESPONSE_DOMAIN" | grep -q "BACKEND_RESPONSE_OK"; then
    E2E_SUCCESS="true"
fi

# 4. Anti-Gaming Timestamp Check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_MODIFIED="false"

# Find the file containing the config
CONFIG_FILE=$(grep -rlE "ProxyPass\s+/app" /etc/apache2/sites-enabled/ 2>/dev/null | head -1)
if [ -f "$CONFIG_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
fi

# 5. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mod_proxy_enabled": $([ "$MOD_PROXY" -gt 0 ] && echo "true" || echo "false"),
    "mod_proxy_http_enabled": $([ "$MOD_PROXY_HTTP" -gt 0 ] && echo "true" || echo "false"),
    "config_proxypass_found": $([ "$CONFIG_PROXYPASS" -gt 0 ] && echo "true" || echo "false"),
    "config_proxypass_reverse_found": $([ "$CONFIG_PROXYPASS_REVERSE" -gt 0 ] && echo "true" || echo "false"),
    "e2e_test_passed": $E2E_SUCCESS,
    "config_modified_during_task": $CONFIG_MODIFIED,
    "initial_proxy_count": $(cat /tmp/initial_proxy_count.txt 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="