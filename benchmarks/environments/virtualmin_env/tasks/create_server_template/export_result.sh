#!/bin/bash
echo "=== Exporting create_server_template results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Search for the template file created by the agent
TEMPLATE_DIR="/etc/webmin/virtual-server/templates"
FOUND_TEMPLATE_FILE=""
TEMPLATE_NAME_FOUND="false"

# Grep for the exact name in the templates directory
# Virtualmin saves templates as simple key-value text files
if [ -d "$TEMPLATE_DIR" ]; then
    # Find file containing exactly "name=FastWeb Static"
    FOUND_TEMPLATE_FILE=$(grep -l "^name=FastWeb Static$" "$TEMPLATE_DIR"/* 2>/dev/null | head -n 1)
fi

# 2. Extract Data if found
TEMPLATE_EXISTS="false"
TEMPLATE_CONTENT=""
TEMPLATE_PATH=""

if [ -n "$FOUND_TEMPLATE_FILE" ] && [ -f "$FOUND_TEMPLATE_FILE" ]; then
    echo "Found template at: $FOUND_TEMPLATE_FILE"
    TEMPLATE_EXISTS="true"
    TEMPLATE_PATH="$FOUND_TEMPLATE_FILE"
    
    # Copy the content to a temp file for the verifier to read
    cp "$FOUND_TEMPLATE_FILE" /tmp/agent_template.txt
    chmod 666 /tmp/agent_template.txt
else
    echo "Template 'FastWeb Static' not found."
fi

# 3. Create JSON result
# We don't try to parse the complex config here; we let Python do it.
# We just pass the path and existence status.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "template_exists": $TEMPLATE_EXISTS,
    "template_path": "$TEMPLATE_PATH",
    "template_content_file": "/tmp/agent_template.txt",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"