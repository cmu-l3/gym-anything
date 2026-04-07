#!/bin/bash
echo "=== Exporting PM2 ecosystem task result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Export actual PM2 process list as JSON
echo "Exporting PM2 jlist..."
sudo -u ga pm2 jlist > /tmp/pm2_jlist.json 2>/dev/null || echo "[]" > /tmp/pm2_jlist.json

# 2. Parse the JavaScript ecosystem file safely using Node.js
# This avoids tricky regex parsing in bash/python for JS files
echo "Parsing ecosystem.config.js..."
if [ -f "/home/ga/ecosystem.config.js" ]; then
    ECO_MTIME=$(stat -c %Y /home/ga/ecosystem.config.js 2>/dev/null || echo "0")
    ECO_SIZE=$(stat -c %s /home/ga/ecosystem.config.js 2>/dev/null || echo "0")
    ECO_EXISTS="true"
    
    sudo -u ga node -e "
    try {
        const eco = require('/home/ga/ecosystem.config.js');
        console.log(JSON.stringify({success: true, data: eco}));
    } catch(e) {
        console.log(JSON.stringify({success: false, error: e.message}));
    }
    " > /tmp/parsed_ecosystem.json 2>/dev/null || echo '{"success": false, "error": "Node execution failed"}' > /tmp/parsed_ecosystem.json
else
    ECO_MTIME="0"
    ECO_SIZE="0"
    ECO_EXISTS="false"
    echo '{"success": false, "error": "File not found"}' > /tmp/parsed_ecosystem.json
fi

# 3. Check the plain text status report
if [ -f "/home/ga/pm2_status.txt" ]; then
    STATUS_SIZE=$(stat -c %s /home/ga/pm2_status.txt 2>/dev/null || echo "0")
    STATUS_EXISTS="true"
else
    STATUS_SIZE="0"
    STATUS_EXISTS="false"
fi

# 4. Consolidate metadata into a single result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eco_exists": $ECO_EXISTS,
    "eco_mtime": $ECO_MTIME,
    "eco_size": $ECO_SIZE,
    "status_exists": $STATUS_EXISTS,
    "status_size": $STATUS_SIZE
}
EOF

# Ensure the files are readable by the verifier script
chmod 666 /tmp/task_result.json /tmp/parsed_ecosystem.json /tmp/pm2_jlist.json /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="