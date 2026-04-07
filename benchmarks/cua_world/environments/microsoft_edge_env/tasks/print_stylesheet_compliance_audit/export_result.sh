#!/bin/bash
set -e

echo "=== Exporting Print Stylesheet Compliance Audit Result ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Desktop/turing_print_audit.pdf"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Metadata
FILE_EXISTS="false"
FILE_SIZE="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze PDF Content (using python inside container)
# We extract text to check for forbidden sidebar elements
echo "Analyzing PDF content..."
python3 << PYEOF > /tmp/pdf_analysis.json
import json
import sys
import os

result = {
    "is_valid_pdf": False,
    "page_count": 0,
    "text_content_sample": "",
    "has_required_text": False,
    "has_forbidden_text": False,
    "found_forbidden_terms": []
}

filepath = "$OUTPUT_PATH"

if os.path.exists(filepath):
    try:
        # Import here to handle case where pip install might have failed
        from pypdf import PdfReader
        
        reader = PdfReader(filepath)
        result["is_valid_pdf"] = True
        result["page_count"] = len(reader.pages)
        
        full_text = ""
        for page in reader.pages:
            full_text += page.extract_text() + "\n"
            
        # Normalize text
        full_text_lower = full_text.lower()
        result["text_content_sample"] = full_text[:500] # First 500 chars
        
        # Check required
        required = ["turing machine", "mathematical model"]
        result["has_required_text"] = all(r in full_text_lower for r in required)
        
        # Check forbidden (Sidebar elements)
        forbidden = ["donate to wikipedia", "current events", "random article", "upload file"]
        found = []
        for term in forbidden:
            if term in full_text_lower:
                found.append(term)
        
        if found:
            result["has_forbidden_text"] = True
            result["found_forbidden_terms"] = found
            
    except ImportError:
        result["error"] = "pypdf not installed"
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Combine results
# Read the python analysis
ANALYSIS=$(cat /tmp/pdf_analysis.json)

# Create final JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "pdf_analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="