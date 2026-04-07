#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting E-Commerce i18n Result ==="

WORKSPACE_DIR="/home/ga/workspace/shopfront-i18n"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1

rm -f "$RESULT_FILE"

# Create a hidden validation script to run inside the container.
# This prevents the agent from simply faking test outputs.
cat > /tmp/validate_hidden.js << 'EOF'
const i18n = require('/home/ga/workspace/shopfront-i18n/src/i18n');
const config = require('/home/ga/workspace/shopfront-i18n/src/i18n/config');
const fs = require('fs');

let results = {
    configFixed: false,
    interpolatorFixed: false,
    currencyFixed: false,
    dateFixed: false,
    pluralsFixed: false
};

// 1. Config Test
try {
    let circular = false;
    try { i18n.t('missing.key.test', {}, 'ja'); } catch(e) { circular = true; }
    results.configFixed = !circular && config.returnNull === false;
} catch(e) {}

// 2. Interpolator Test
try {
    const str = i18n.t('greeting', {name: 'Agent'}, 'en');
    results.interpolatorFixed = str === 'Hello Agent!';
} catch(e) {}

// 3. Currency Test
try {
    const jpy = i18n.formatCurrency(1234, 'JPY', 'ja-JP');
    const usd = i18n.formatCurrency(1234.56, 'USD', 'en-US');
    results.currencyFixed = !jpy.includes('.') && usd.includes('.');
} catch(e) {}

// 4. Date Test
try {
    const deDate = i18n.formatDate('2024-03-15', 'de-DE');
    results.dateFixed = deDate.includes('15.') || deDate.includes('15.03.');
} catch(e) {}

// 5. Plurals Test
try {
    const deJson = JSON.parse(fs.readFileSync('/home/ga/workspace/shopfront-i18n/src/locales/de.json', 'utf8'));
    const hasZero = deJson.cart.itemCount_zero !== undefined;
    const hasFew = deJson.cart.itemCount_few !== undefined;
    const hasMany = deJson.cart.itemCount_many !== undefined;
    const hasOther = deJson.cart.itemCount_other !== undefined;
    results.pluralsFixed = !hasZero && !hasFew && !hasMany && hasOther;
} catch(e) {}

console.log(JSON.stringify(results));
EOF

# Run the validation script
VALIDATION_JSON=$(node /tmp/validate_hidden.js 2>/dev/null || echo '{"error": "Validation script crashed"}')

# Collect source files to output
python3 << PYEXPORT
import json, os, stat

workspace = "$WORKSPACE_DIR"
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

files_to_export = {
    "src/i18n/config.js":        os.path.join(workspace, "src/i18n/config.js"),
    "src/i18n/interpolator.js":  os.path.join(workspace, "src/i18n/interpolator.js"),
    "src/i18n/formatter.js":     os.path.join(workspace, "src/i18n/formatter.js"),
    "src/locales/de.json":       os.path.join(workspace, "src/locales/de.json")
}

output = {
    "validation": $VALIDATION_JSON,
    "files": {},
    "modified_during_task": False
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            output["files"][label] = f.read()
            
        # Anti-gaming: Ensure files were actually modified during the task
        mtime = os.stat(path).st_mtime
        if mtime > task_start:
            output["modified_during_task"] = True
            
    except Exception as e:
        output["files"][label] = f"ERROR: {str(e)}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(output, out, indent=2)
PYEXPORT

chmod 666 "$RESULT_FILE"
echo "=== Export Complete ==="