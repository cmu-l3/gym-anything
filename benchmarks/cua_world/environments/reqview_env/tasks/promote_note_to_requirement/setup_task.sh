#!/bin/bash
set -e
echo "=== Setting up promote_note_to_requirement task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh task project
# We use a unique name to ensure no collision with other tasks
PROJECT_DIR=$(setup_task_project "promote_note")
SRS_JSON="$PROJECT_DIR/documents/SRS.json"

echo "Project directory: $PROJECT_DIR"

# 3. Inject the "Note" (Text object without ID) into SRS.json
# We look for Section 2 (System Features) and add a child object that has text but NO 'id'.
if [ -f "$SRS_JSON" ]; then
    python3 << PYEOF
import json
import uuid
import sys
import re

srs_path = "$SRS_JSON"
target_text = "The system data must be encrypted at rest using AES-256."

try:
    with open(srs_path, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"Error reading SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

def find_section_and_inject(items, section_prefix="2"):
    """
    Find a section starting with the prefix (e.g., '2 ' or just being the 2nd main section)
    and inject the note.
    """
    # In ReqView JSON, section numbering isn't always explicit in 'heading', 
    # but we can look for "System Features" which is standard in the example project.
    for item in items:
        heading = item.get('heading', '')
        # Check for System Features section
        if 'System Features' in heading or heading.startswith('2 '):
            if 'children' not in item:
                item['children'] = []
            
            # Create the Note object (No 'id' field!)
            note_object = {
                "guid": str(uuid.uuid4()),
                "text": f"<p>{target_text}</p>",
                "type": "Note"  # Some templates use 'Note' or just empty type for text
            }
            
            # Insert at the top of children for visibility
            item['children'].insert(0, note_object)
            print(f"Injected note into section: {heading}")
            return True
        
        # Recurse
        if 'children' in item:
            if find_section_and_inject(item['children'], section_prefix):
                return True
    return False

if find_section_and_inject(data.get('data', [])):
    with open(srs_path, 'w') as f:
        json.dump(data, f, indent=2)
    print("Successfully injected un-ID'd note.")
else:
    print("WARNING: Could not find 'System Features' section to inject note.")
    # Fallback: Append to root if specific section not found (unlikely in example project)
    data['data'].append({
        "guid": str(uuid.uuid4()),
        "text": f"<p>{target_text}</p>", 
        "heading": "Security Notes" # Create a new section if needed
    })
    with open(srs_path, 'w') as f:
        json.dump(data, f, indent=2)

PYEOF
else
    echo "ERROR: SRS.json not found at $SRS_JSON"
    exit 1
fi

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch ReqView with the modified project
launch_reqview_with_project "$PROJECT_DIR"

# 6. UI Setup
# Dismiss dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open SRS document
open_srs_document

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="