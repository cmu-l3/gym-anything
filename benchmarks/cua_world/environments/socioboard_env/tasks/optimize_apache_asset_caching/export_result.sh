#!/bin/bash
echo "=== Exporting optimize_apache_asset_caching result ==="

source /workspace/scripts/task_utils.sh

# Take a final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved."

# 1. Create dynamic test files in the web root to prevent hardcoded responses
WEB_ROOT="/opt/socioboard/socioboard-web-php/public"
TEST_ID=$(date +%s)

# Create dummy static assets
sudo touch "$WEB_ROOT/verify_asset_${TEST_ID}.png"
sudo touch "$WEB_ROOT/verify_asset_${TEST_ID}.css"
sudo touch "$WEB_ROOT/verify_asset_${TEST_ID}.js"
sudo chown www-data:www-data "$WEB_ROOT/verify_asset_${TEST_ID}".*

# 2. Extract headers, syntax status, and module status via Python to output JSON securely
TEMP_JSON=$(mktemp /tmp/caching_result.XXXXXX.json)

python3 <<EOF
import json
import subprocess

def get_headers(url):
    try:
        res = subprocess.run(['curl', '-s', '-I', url], capture_output=True, text=True, timeout=5)
        return res.stdout
    except Exception as e:
        return str(e)

# Check Apache status
syntax_res = subprocess.run(['apache2ctl', 'configtest'], capture_output=True, text=True)
syntax_ok = "Syntax OK" in syntax_res.stderr or "Syntax OK" in syntax_res.stdout
active_res = subprocess.run(['systemctl', 'is-active', '--quiet', 'apache2'])
active = active_res.returncode == 0

# Fetch headers for test files
data = {
    "apache_syntax_ok": syntax_ok,
    "apache_active": active,
    "headers_png": get_headers(f"http://localhost/verify_asset_${TEST_ID}.png"),
    "headers_css": get_headers(f"http://localhost/verify_asset_${TEST_ID}.css"),
    "headers_js": get_headers(f"http://localhost/verify_asset_${TEST_ID}.js"),
    "headers_php": get_headers("http://localhost/index.php"),
    "modules": subprocess.run(['apache2ctl', '-M'], capture_output=True, text=True).stdout,
    "screenshot_path": "/tmp/task_final.png"
}

with open("$TEMP_JSON", "w") as f:
    json.dump(data, f, indent=2)
EOF

# Clean up the dummy test files
sudo rm -f "$WEB_ROOT/verify_asset_${TEST_ID}".*

# Safely copy to the final /tmp/task_result.json with open permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="