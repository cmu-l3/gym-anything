#!/bin/bash
echo "=== Exporting Task Results ==="

# Define paths
DIAGRAM_FILE="/home/ga/Diagrams/stamping_vsm.drawio"
PDF_FILE="/home/ga/Diagrams/stamping_vsm.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize result variables
FILE_EXISTS=false
FILE_MODIFIED=false
PDF_EXISTS=false
PAGE_COUNT=0
CELL_COUNT=0
HAS_REQUIRED_PROCESSES=false
HAS_REQUIRED_DATA=false
HAS_TOTALS=false
HAS_FUTURE_STATE=false

# 1. Check PDF Export
if [ -f "$PDF_FILE" ] && [ $(stat -c %s "$PDF_FILE") -gt 1000 ]; then
    PDF_EXISTS=true
fi

# 2. Analyze Diagram File (using Python for robust XML/Compressed parsing)
if [ -f "$DIAGRAM_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi

    # Python script to parse draw.io XML (handling potential compression)
    python3 - << ENDPYTHON > /tmp/analysis_result.json
import sys
import os
import zlib
import base64
import json
import urllib.parse
import xml.etree.ElementTree as ET

def decode_node_text(text):
    """Decode draw.io node text which might be compressed."""
    if not text: return ""
    try:
        # Check if it looks like XML directly
        if text.strip().startswith("<"):
            return text
        # Try decoding: URL decode -> Base64 -> Inflate (raw)
        decoded = base64.b64decode(text)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except Exception:
        return text

def analyze_diagram(file_path):
    result = {
        "page_count": 0,
        "cell_count": 0,
        "text_content": [],
        "page_names": []
    }
    
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result["page_count"] = len(diagrams)
        
        all_text = ""
        
        for diag in diagrams:
            result["page_names"].append(diag.get('name', ''))
            
            # Content can be in the 'text' of the diagram node (compressed)
            # or as children if uncompressed
            content_xml = diag.text
            
            if content_xml and not list(diag):
                # Compressed content
                expanded_xml = decode_node_text(content_xml)
                if expanded_xml.startswith("<"):
                    try:
                        diag_root = ET.fromstring(expanded_xml)
                        cells = diag_root.findall(".//mxCell")
                        result["cell_count"] += len(cells)
                        for cell in cells:
                            val = cell.get("value", "")
                            if val: all_text += " " + val
                    except:
                        pass
            else:
                # Uncompressed content directly in file
                cells = diag.findall(".//mxCell")
                result["cell_count"] += len(cells)
                for cell in cells:
                    val = cell.get("value", "")
                    if val: all_text += " " + val
                    
        result["text_content"] = all_text.lower()
        
    except Exception as e:
        result["error"] = str(e)
        
    return result

analysis = analyze_diagram("$DIAGRAM_FILE")
print(json.dumps(analysis))
ENDPYTHON

    # Read analysis results
    if [ -f /tmp/analysis_result.json ]; then
        PAGE_COUNT=$(jq '.page_count' /tmp/analysis_result.json)
        CELL_COUNT=$(jq '.cell_count' /tmp/analysis_result.json)
        TEXT_CONTENT=$(jq -r '.text_content' /tmp/analysis_result.json)
        PAGE_NAMES=$(jq -r '.page_names | join(",")' /tmp/analysis_result.json)
        
        # Check required processes
        REQ_PROCS=("welding ii" "assembly i" "assembly ii" "shipping")
        PROCS_FOUND=0
        for proc in "${REQ_PROCS[@]}"; do
            if [[ "$TEXT_CONTENT" == *"$proc"* ]]; then
                ((PROCS_FOUND++))
            fi
        done
        if [ "$PROCS_FOUND" -ge 4 ]; then HAS_REQUIRED_PROCESSES=true; fi
        
        # Check required data values (C/T 46, 62, 40)
        REQ_DATA=("46" "62" "40" "23.5" "188")
        DATA_FOUND=0
        for val in "${REQ_DATA[@]}"; do
            if [[ "$TEXT_CONTENT" == *"$val"* ]]; then
                ((DATA_FOUND++))
            fi
        done
        if [ "$DATA_FOUND" -ge 3 ]; then HAS_REQUIRED_DATA=true; fi
        
        # Check Totals specifically
        if [[ "$TEXT_CONTENT" == *"23.5"* ]] && [[ "$TEXT_CONTENT" == *"188"* ]]; then
            HAS_TOTALS=true
        fi
        
        # Check Future State elements
        FUTURE_TERMS=("weld cell" "assembly cell" "supermarket" "fifo" "kaizen")
        FUTURE_FOUND=0
        for term in "${FUTURE_TERMS[@]}"; do
            if [[ "$TEXT_CONTENT" == *"$term"* ]]; then
                ((FUTURE_FOUND++))
            fi
        done
        if [ "$FUTURE_FOUND" -ge 3 ]; then HAS_FUTURE_STATE=true; fi
    fi
fi

# Create JSON Output
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "page_count": $PAGE_COUNT,
    "cell_count": $CELL_COUNT,
    "has_required_processes": $HAS_REQUIRED_PROCESSES,
    "has_required_data": $HAS_REQUIRED_DATA,
    "has_totals": $HAS_TOTALS,
    "has_future_state": $HAS_FUTURE_STATE,
    "page_names": "$PAGE_NAMES",
    "timestamp": $(date +%s)
}
EOF

# Safe copy to avoid permission issues
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "Export complete. Result:"
cat /tmp/final_result.json