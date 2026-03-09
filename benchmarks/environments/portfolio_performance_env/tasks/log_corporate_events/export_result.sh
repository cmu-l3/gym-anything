#!/bin/bash
echo "=== Exporting log_corporate_events result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/tesla_analysis.xml"
TASK_START_MARKER="/tmp/task_start_marker"

# Check if file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    if [ "$PORTFOLIO_FILE" -nt "$TASK_START_MARKER" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Use Python to parse XML and extract events specifically for Tesla
# We look for <security> with matching ISIN/Name, then check its <events> child
python3 << PYEOF > /tmp/task_result.json
import xml.etree.ElementTree as ET
import json
import os
import sys

result = {
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "security_found": False,
    "event_found": False,
    "events_data": [],
    "app_running": False
}

# Check if app is running
if os.system("pgrep -f PortfolioPerformance > /dev/null") == 0:
    result["app_running"] = True

try:
    if result["file_exists"]:
        tree = ET.parse("$PORTFOLIO_FILE")
        root = tree.getroot()
        
        # Namespace handling usually not needed for PP XMLs, but simple find works
        securities = root.find("securities")
        if securities is not None:
            for sec in securities.findall("security"):
                isin = sec.find("isin")
                name = sec.find("name")
                
                # Identify Tesla
                if (isin is not None and isin.text == "US88160R1014") or \
                   (name is not None and "Tesla" in (name.text or "")):
                    result["security_found"] = True
                    
                    # Check events
                    events_container = sec.find("events")
                    if events_container is not None:
                        for event in events_container.findall("event"):
                            date_elem = event.find("date")
                            label_elem = event.find("label") # PP uses 'label' or 'title' depending on version context
                            
                            # Fallback if label is named differently
                            label_text = ""
                            if label_elem is not None:
                                label_text = label_elem.text
                            
                            evt_data = {
                                "date": date_elem.text if date_elem is not None else "",
                                "label": label_text
                            }
                            result["events_data"].append(evt_data)
                            result["event_found"] = True
                    
                    break # Found Tesla, stop looking

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Set permissions so ga user/verifier can read it
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json