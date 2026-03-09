#!/bin/bash
echo "=== Exporting secure_sensitive_files result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DOC_ROOT="/home/acmecorp/public_html"
IP="127.0.0.1"

# 1. Active Probing via CURL
# We use Host header to ensure we target the correct vhost on localhost
echo "Probing security status..."

# Check .env
CODE_ENV=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: acmecorp.test" "http://$IP/.env")
# Check .git/HEAD
CODE_GIT=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: acmecorp.test" "http://$IP/.git/HEAD")
# Check Homepage (Availability)
CODE_HOME=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: acmecorp.test" "http://$IP/index.html")

# 2. Check File Existence (Anti-Gaming)
# The user should NOT delete the files, just block access.
FILES_EXIST="false"
if [ -f "$DOC_ROOT/.env" ] && [ -f "$DOC_ROOT/.git/HEAD" ]; then
    FILES_EXIST="true"
fi

# 3. Check Apache Config Validity
CONFIG_VALID="false"
if apache2ctl -t > /dev/null 2>&1; then
    CONFIG_VALID="true"
fi

# 4. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "http_code_env": $CODE_ENV,
    "http_code_git": $CODE_GIT,
    "http_code_home": $CODE_HOME,
    "files_exist_on_disk": $FILES_EXIST,
    "apache_config_valid": $CONFIG_VALID,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="