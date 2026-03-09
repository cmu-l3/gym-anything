#!/bin/bash
# export_result.sh - Post-task hook for a11y_compliance_audit

echo "=== Exporting a11y_compliance_audit results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush WAL to disk (ensure history is readable)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Environment Variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
OUTPUT_FILE="/home/ga/Documents/accessibility_audit.json"

# 4. Verify History (Did they visit the sites?)
VISIT_WIKI=0
VISIT_CRAIGSLIST=0
VISIT_ARCHIVE=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite
    
    # Check Wikipedia
    VISIT_WIKI=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%en.wikipedia.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check Craigslist
    VISIT_CRAIGSLIST=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%craigslist.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check Archive.org
    VISIT_ARCHIVE=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%archive.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    rm -f /tmp/places_export.sqlite
fi

# 5. Check Output File Stats
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 6. Analyze JSON Content (Robust Python Parsing)
# We embed a python script to parse the user's JSON and return metrics
cat > /tmp/analyze_json.py << 'EOF'
import json
import sys
import re

try:
    with open("/home/ga/Documents/accessibility_audit.json", "r") as f:
        data = json.load(f)
        
    result = {
        "valid_json": True,
        "has_metadata": False,
        "site_count": 0,
        "sites_found": [],
        "total_issues": 0,
        "wcag_refs_valid": 0,
        "issue_types": set()
    }
    
    # Check Metadata
    if "audit_metadata" in data:
        meta = data["audit_metadata"]
        if meta.get("tool") and meta.get("standard") and meta.get("date"):
            result["has_metadata"] = True
            
    # Check Sites
    sites = data.get("sites", {})
    result["site_count"] = len(sites)
    
    wcag_pattern = re.compile(r"^[1-4]\.\d+(\.\d+)?$")
    
    for domain, site_data in sites.items():
        result["sites_found"].append(domain)
        issues = site_data.get("issues", [])
        result["total_issues"] += len(issues)
        
        for issue in issues:
            # Check issue type diversity
            if "type" in issue:
                result["issue_types"].add(issue["type"])
                
            # Check WCAG criteria format (e.g., 1.1.1)
            crit = issue.get("wcag_criterion", "")
            if wcag_pattern.match(str(crit).strip()):
                result["wcag_refs_valid"] += 1
                
    # Convert set to list for JSON serialization
    result["issue_types"] = list(result["issue_types"])
    
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid_json": False, "error": str(e)}))
EOF

if [ "$FILE_EXISTS" = "true" ]; then
    JSON_ANALYSIS=$(python3 /tmp/analyze_json.py)
else
    JSON_ANALYSIS='{"valid_json": false, "error": "File not found"}'
fi

# 7. Construct Final Result JSON
# Using a temp file to avoid permission issues when creating the final result
cat > /tmp/temp_result.json << EOF
{
    "task_start": $TASK_START,
    "visits": {
        "wikipedia": $VISIT_WIKI,
        "craigslist": $VISIT_CRAIGSLIST,
        "archive": $VISIT_ARCHIVE
    },
    "file_stats": {
        "exists": $FILE_EXISTS,
        "fresh": $FILE_FRESH,
        "size": $FILE_SIZE
    },
    "json_analysis": $JSON_ANALYSIS
}
EOF

# Move to final location (copy_from_env will read this)
cp /tmp/temp_result.json /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json