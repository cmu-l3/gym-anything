#!/bin/bash
echo "=== Exporting Airline Reporting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Paths
TEMPLATE_PATH="/home/ga/RProjects/airline_template.Rmd"
SCRIPT_PATH="/home/ga/RProjects/render_reports.R"
UA_REPORT="/home/ga/RProjects/report_UA.html"
DL_REPORT="/home/ga/RProjects/report_DL.html"

# Helper to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "new"
        else
            echo "old"
        fi
    else
        echo "missing"
    fi
}

# Check files
TEMPLATE_STATUS=$(check_file "$TEMPLATE_PATH")
SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")
UA_STATUS=$(check_file "$UA_REPORT")
DL_STATUS=$(check_file "$DL_REPORT")

# Analyze content using Python for robustness
# We extract: 
# 1. Does the Rmd have 'params:'?
# 2. Does the script call 'render'?
# 3. Do the HTML files contain expected strings?
# 4. Are the HTML files identical (bad) or different (good)?
# 5. Is nycflights13 installed?

PYTHON_ANALYSIS=$(python3 << PYEOF
import os
import sys

results = {
    "rmd_has_params": False,
    "script_calls_render": False,
    "ua_has_content": False,
    "dl_has_content": False,
    "reports_differ": False,
    "nycflights_installed": False
}

# Check Rmd content
if os.path.exists("$TEMPLATE_PATH"):
    try:
        with open("$TEMPLATE_PATH", 'r', errors='ignore') as f:
            content = f.read()
            if 'params:' in content or 'params :' in content:
                results["rmd_has_params"] = True
    except: pass

# Check automation script
if os.path.exists("$SCRIPT_PATH"):
    try:
        with open("$SCRIPT_PATH", 'r', errors='ignore') as f:
            content = f.read()
            if 'render' in content:
                results["script_calls_render"] = True
    except: pass

# Check HTML content
ua_content = ""
dl_content = ""

if os.path.exists("$UA_REPORT"):
    try:
        with open("$UA_REPORT", 'r', errors='ignore') as f:
            ua_content = f.read()
            # Check for United string (flexible matching)
            if "United Air Lines" in ua_content or "United Airlines" in ua_content:
                results["ua_has_content"] = True
    except: pass

if os.path.exists("$DL_REPORT"):
    try:
        with open("$DL_REPORT", 'r', errors='ignore') as f:
            dl_content = f.read()
            # Check for Delta string
            if "Delta Air Lines" in dl_content or "Delta Airlines" in dl_content:
                results["dl_has_content"] = True
    except: pass

# Check if reports differ (anti-gaming: simple copy check)
# They should differ significantly, but we check if they are identical
if ua_content and dl_content:
    if len(ua_content) != len(dl_content) or ua_content != dl_content:
        results["reports_differ"] = True

# Check if package is installed via R
# We'll rely on the shell script to check this via R command below, 
# but we can check if the library dir has it if we knew the path.
# Instead, we'll let the shell part handle package verification.

print(f"{results['rmd_has_params']}|{results['script_calls_render']}|{results['ua_has_content']}|{results['dl_has_content']}|{results['reports_differ']}")
PYEOF
)

IFS='|' read -r RMD_HAS_PARAMS SCRIPT_CALLS_RENDER UA_HAS_CONTENT DL_HAS_CONTENT REPORTS_DIFFER <<< "$PYTHON_ANALYSIS"

# Check package installation
PKG_INSTALLED="false"
if R --vanilla --slave -e "quit(status=!('nycflights13' %in% rownames(installed.packages())))" >/dev/null 2>&1; then
    PKG_INSTALLED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "template_status": "$TEMPLATE_STATUS",
    "script_status": "$SCRIPT_STATUS",
    "ua_report_status": "$UA_STATUS",
    "dl_report_status": "$DL_STATUS",
    "rmd_has_params": $RMD_HAS_PARAMS,
    "script_calls_render": $SCRIPT_CALLS_RENDER,
    "ua_report_valid_content": $UA_HAS_CONTENT,
    "dl_report_valid_content": $DL_HAS_CONTENT,
    "reports_are_distinct": $REPORTS_DIFFER,
    "nycflights13_installed": $PKG_INSTALLED
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="