#!/bin/bash
set -e
echo "=== Exporting Franchise Ops Manual Formatting Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close ONLYOFFICE gracefully to ensure file buffers are flushed
source /workspace/scripts/task_utils.sh
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    # Try sending Ctrl+S just in case they forgot to save but did the work
    DISPLAY=:1 xdotool key --delay 100 ctrl+s 2>/dev/null || true
    sleep 2
    kill_onlyoffice ga
    sleep 2
fi

TARGET_DIR="/home/ga/Documents/TextDocuments"
FINAL_PATH="$TARGET_DIR/pct_boh_manual_final.docx"
DRAFT_PATH="$TARGET_DIR/pct_boh_manual_draft.docx"

# Determine which file to analyze (Final preferred, Draft as fallback)
FILE_TO_ANALYZE="$DRAFT_PATH"
FILE_SAVED_AS_FINAL="false"

if [ -f "$FINAL_PATH" ]; then
    FILE_TO_ANALYZE="$FINAL_PATH"
    FILE_SAVED_AS_FINAL="true"
fi

# Python script to parse the DOCX file and extract formatting metrics
# This runs INSIDE the container where python-docx is guaranteed to be installed
cat > /tmp/analyze_docx.py << 'PYEOF'
import sys
import json
import os
from docx import Document

file_path = sys.argv[1]
file_saved_as_final = sys.argv[2] == "true"
start_time = int(sys.argv[3])

result = {
    "file_analyzed": file_path,
    "saved_as_final": file_saved_as_final,
    "modified_during_task": False,
    "table_count": 0,
    "title": None,
    "sections": {},
    "subheadings": {},
    "warnings": []
}

if not os.path.exists(file_path):
    print(json.dumps(result))
    sys.exit(0)

# Check modification time
mtime = os.path.getmtime(file_path)
result["modified_during_task"] = mtime > start_time

try:
    doc = Document(file_path)
    result["table_count"] = len(doc.tables)
    
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text:
            continue
            
        # Parse formatting (checking runs)
        is_bold = any(r.bold for r in para.runs if r.text.strip())
        is_italic = any(r.italic for r in para.runs if r.text.strip())
        is_underline = any(r.underline for r in para.runs if r.text.strip())
        
        # Font size pt logic (fallback to 0 if not explicitly set)
        pts = [r.font.size.pt for r in para.runs if r.font.size and r.text.strip()]
        pt_size = max(pts) if pts else 0
        
        # Alignment (0=LEFT, 1=CENTER, 2=RIGHT, None=Inherited/Left)
        align = para.alignment
        align_val = 0 if align is None else align
        
        format_data = {
            "text": text[:50],
            "bold": is_bold,
            "italic": is_italic,
            "underline": is_underline,
            "pt_size": pt_size,
            "alignment": align_val
        }

        # Match specific targets
        if "PACIFIC COAST TACOS - BACK OF HOUSE OPERATIONS" in text:
            result["title"] = format_data
            
        for sec in ["1.0", "2.0", "3.0"]:
            if text.startswith(sec):
                result["sections"][sec] = format_data
                
        for sub in ["1.1", "1.2", "2.1", "2.2", "3.1"]:
            if text.startswith(sub):
                result["subheadings"][sub] = format_data
                
        if text.startswith("CRITICAL SAFETY:"):
            result["warnings"].append(format_data)

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Run the analysis
python3 /tmp/analyze_docx.py "$FILE_TO_ANALYZE" "$FILE_SAVED_AS_FINAL" "$TASK_START"

# Ensure host can read the result
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "DOCX analysis complete. Exported to /tmp/task_result.json."
echo "=== Export Complete ==="