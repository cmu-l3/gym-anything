#!/bin/bash
echo "=== Exporting Firefox Accessibility Override Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"

# Take final screenshot before altering state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Firefox to force prefs.js to write to disk
echo "Closing Firefox to save profile state..."
pkill -f firefox 2>/dev/null || true
sleep 3
pkill -9 -f firefox 2>/dev/null || true

# Record prefs.js modification time
PREFS_MTIME=$(stat -c %Y "$PROFILE_DIR/prefs.js" 2>/dev/null || echo "0")
if [ "$PREFS_MTIME" -ge "$TASK_START" ]; then
    PREFS_MODIFIED_DURING_TASK="true"
else
    PREFS_MODIFIED_DURING_TASK="false"
fi

# 1. Create a hostile HTML test page that aggressively specifies bad accessibility styling
cat > /tmp/test_accessibility.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<style>
    /* Aggressive CSS that should be overridden by the browser settings */
    body {
        font-family: "Times New Roman", serif !important;
        font-size: 10px !important;
        color: rgb(255, 255, 255) !important;
        background-color: rgb(0, 0, 139) !important;
    }
</style>
</head>
<body>
    <p id="test-text">This paragraph tests if browser accessibility overrides defeat page CSS.</p>
</body>
</html>
EOF
chmod 644 /tmp/test_accessibility.html

# 2. Extract computed DOM styles using Selenium headless mode
cat > /tmp/extract_styles.py << 'EOF'
import json
import sys
from selenium import webdriver
from selenium.webdriver.firefox.options import Options

options = Options()
options.add_argument('-headless')
options.add_argument('-profile')
options.add_argument('/home/ga/.mozilla/firefox/default.profile')

try:
    driver = webdriver.Firefox(options=options)
    driver.get('file:///tmp/test_accessibility.html')
    
    # Extract computed styles from the body element
    font_family = driver.execute_script('return window.getComputedStyle(document.body).fontFamily;')
    font_size = driver.execute_script('return window.getComputedStyle(document.body).fontSize;')
    color = driver.execute_script('return window.getComputedStyle(document.body).color;')
    bg_color = driver.execute_script('return window.getComputedStyle(document.body).backgroundColor;')
    
    driver.quit()
    
    result = {
        "success": True,
        "computed_styles": {
            "fontFamily": font_family,
            "fontSize": font_size,
            "color": color,
            "backgroundColor": bg_color
        }
    }
except Exception as e:
    result = {"success": False, "error": str(e)}

with open('/tmp/computed_styles.json', 'w') as f:
    json.dump(result, f)
EOF

echo "Running DOM style extraction..."
sudo -u ga python3 /tmp/extract_styles.py || echo '{"success": false, "error": "Selenium extraction script failed"}' > /tmp/computed_styles.json

# 3. Fallback: Parse prefs.js for raw configuration strings
cat > /tmp/prefs_extracted.json << EOF
{
    "color_use": "$(grep 'browser.display.document_color_use' "$PROFILE_DIR/prefs.js" | cut -d',' -f2 | tr -d '); ' || echo "null")",
    "use_fonts": "$(grep 'browser.display.use_document_fonts' "$PROFILE_DIR/prefs.js" | cut -d',' -f2 | tr -d '); ' || echo "null")",
    "bg_color": "$(grep 'browser.display.background_color' "$PROFILE_DIR/prefs.js" | cut -d',' -f2 | tr -d '\"); ' || echo "null")",
    "fg_color": "$(grep 'browser.display.foreground_color' "$PROFILE_DIR/prefs.js" | cut -d',' -f2 | tr -d '\"); ' || echo "null")",
    "font_name": "$(grep 'font.name.sans-serif.x-western' "$PROFILE_DIR/prefs.js" | cut -d',' -f2 | tr -d '\"); ' || echo "null")",
    "font_size": "$(grep 'font.size.variable.x-western' "$PROFILE_DIR/prefs.js" | cut -d',' -f2 | tr -d '); ' || echo "null")"
}
EOF

# Combine results into final JSON payload
jq -s '.[0] * {"prefs": .[1], "prefs_modified": '"$PREFS_MODIFIED_DURING_TASK"'}' /tmp/computed_styles.json /tmp/prefs_extracted.json > /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Result payload generated at /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="