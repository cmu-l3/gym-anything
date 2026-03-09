#!/bin/bash
# Export script for Generate XML Sitemap task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Generate XML Sitemap Result ==="

take_screenshot /tmp/task_end_screenshot.png

SITEMAP_PATH="/home/ga/Documents/SEO/sitemaps/sitemap.xml"
REPORT_PATH="/home/ga/Documents/SEO/reports/sitemap_summary.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
SF_RUNNING="false"
SITEMAP_EXISTS="false"
SITEMAP_CREATED_AFTER_START="false"
SITEMAP_VALID_XML="false"
SITEMAP_HAS_NAMESPACE="false"
SITEMAP_URL_COUNT=0
SITEMAP_HAS_TARGET_DOMAIN="false"
REPORT_EXISTS="false"
REPORT_CREATED_AFTER_START="false"
REPORT_CONTENT_LENGTH=0
REPORT_HAS_DATE="false"
REPORT_HAS_NUMBER="false"
REPORT_HAS_DOMAIN="false"
WINDOW_INFO=""

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# --- SITEMAP VERIFICATION ---
if [ -f "$SITEMAP_PATH" ]; then
    SITEMAP_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$SITEMAP_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        SITEMAP_CREATED_AFTER_START="true"
        
        # Verify XML content using Python
        # (Safer than grep for XML structure)
        python3 << PYEOF
import xml.etree.ElementTree as ET
import json
import re

sitemap_info = {
    "valid_xml": False,
    "has_namespace": False,
    "url_count": 0,
    "has_target_domain": False
}

try:
    tree = ET.parse("$SITEMAP_PATH")
    root = tree.getroot()
    sitemap_info["valid_xml"] = True
    
    # Check namespace (standard sitemap is usually http://www.sitemaps.org/schemas/sitemap/0.9)
    if "sitemap" in root.tag and "http" in root.tag:
        sitemap_info["has_namespace"] = True
    
    # Count URLs
    # Namespaces make findall tricky, just iterate
    count = 0
    has_domain = False
    for child in root:
        if "url" in child.tag.lower():
            count += 1
            # Check for loc tag
            for prop in child:
                if "loc" in prop.tag.lower():
                    if "books.toscrape.com" in prop.text:
                        has_domain = True
                        
    sitemap_info["url_count"] = count
    sitemap_info["has_target_domain"] = has_domain

except Exception as e:
    print(f"XML Parse Error: {e}")

with open("/tmp/sitemap_analysis.json", "w") as f:
    json.dump(sitemap_info, f)
PYEOF

        # Read back Python analysis
        if [ -f "/tmp/sitemap_analysis.json" ]; then
            SITEMAP_VALID_XML=$(python3 -c "import json; print(json.load(open('/tmp/sitemap_analysis.json'))['valid_xml'])")
            SITEMAP_HAS_NAMESPACE=$(python3 -c "import json; print(json.load(open('/tmp/sitemap_analysis.json'))['has_namespace'])")
            SITEMAP_URL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/sitemap_analysis.json'))['url_count'])")
            SITEMAP_HAS_TARGET_DOMAIN=$(python3 -c "import json; print(json.load(open('/tmp/sitemap_analysis.json'))['has_target_domain'])")
        fi
    fi
fi

# --- REPORT VERIFICATION ---
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_CREATED_AFTER_START="true"
        CONTENT=$(cat "$REPORT_PATH")
        REPORT_CONTENT_LENGTH=${#CONTENT}
        
        # Check for numbers (URL count)
        if echo "$CONTENT" | grep -qE "[0-9]+"; then
            REPORT_HAS_NUMBER="true"
        fi
        
        # Check for domain
        if echo "$CONTENT" | grep -qi "books.toscrape.com"; then
            REPORT_HAS_DOMAIN="true"
        fi
        
        # Check for date (simple check for 202X or common formats)
        if echo "$CONTENT" | grep -qE "202[0-9]|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"; then
            REPORT_HAS_DATE="true"
        fi
    fi
fi

# Write full result JSON
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "sitemap_exists": "$SITEMAP_EXISTS" == "true",
    "sitemap_created_after_start": "$SITEMAP_CREATED_AFTER_START" == "true",
    "sitemap_valid_xml": "$SITEMAP_VALID_XML" == "True",
    "sitemap_has_namespace": "$SITEMAP_HAS_NAMESPACE" == "True",
    "sitemap_url_count": int("$SITEMAP_URL_COUNT"),
    "sitemap_has_target_domain": "$SITEMAP_HAS_TARGET_DOMAIN" == "True",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_created_after_start": "$REPORT_CREATED_AFTER_START" == "true",
    "report_content_length": int("$REPORT_CONTENT_LENGTH"),
    "report_has_date": "$REPORT_HAS_DATE" == "true",
    "report_has_number": "$REPORT_HAS_NUMBER" == "true",
    "report_has_domain": "$REPORT_HAS_DOMAIN" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="