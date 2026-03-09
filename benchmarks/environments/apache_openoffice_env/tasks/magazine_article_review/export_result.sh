#!/bin/bash
echo "=== Exporting Magazine Article Review Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state
take_screenshot /tmp/task_final.png

RESULT_FILE="/tmp/task_result.json"
OUTPUT_ODT="/home/ga/Documents/AI_Draft_Reviewed.odt"

# Check existence
if [ -f "$OUTPUT_ODT" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_ODT")
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
fi

# Use Python to parse the ODT XML structure to verify specific criteria
# We need to check for Tracked Changes tags and Comments
python3 << PYEOF
import zipfile
import json
import os
import re

output_file = "$OUTPUT_ODT"
result = {
    "file_exists": False,
    "file_size": 0,
    "track_changes_enabled": False,
    "title_changed": False,
    "typo_fixed": False,
    "paragraph_deleted": False,
    "comment_added": False,
    "comment_text_found": False,
    "tracked_change_count": 0,
    "export_timestamp": ""
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # 1. Check if Track Changes is enabled/present
            # ODT stores this in <text:tracked-changes>
            if '<text:tracked-changes' in content_xml:
                result["track_changes_enabled"] = True
                # Count total changes
                result["tracked_change_count"] = content_xml.count('<text:changed-region')

            # 2. Check for Comment
            # ODT comments use <office:annotation>
            if '<office:annotation' in content_xml:
                result["comment_added"] = True
                # Check comment content "Define acronym"
                if "Define acronym" in content_xml or "define acronym" in content_xml:
                    result["comment_text_found"] = True

            # 3. Check specific tracked changes
            # This is tricky in raw XML, but we look for deleted/inserted content within change regions
            
            # Title Change: "Computer Brains" -> "The Evolution"
            # We look for "The Evolution" in the text, AND evidence that the old title was removed or new one inserted via tracking
            # Simple check: Does the file contain the new title?
            if "The Evolution of Generative AI" in content_xml:
                # Was it tracked? We look for the string inside a text:p that might have changes
                # or just simplistic: if track changes is enabled and we see the new text, we assume adherence unless proven otherwise
                # A robust check looks for the deletion of "Computer Brains"
                if "Computer Brains" in content_xml and result["track_changes_enabled"]:
                     result["title_changed"] = True
                elif "The Evolution of Generative AI" in content_xml:
                     # Fallback if deletion text isn't kept in buffer
                     result["title_changed"] = True

            # Typo Fix: "Generatve" -> "Generative"
            if "Generative" in content_xml:
                # If tracked, "Generatve" might still exist in a deletion tag
                if "Generatve" in content_xml and result["track_changes_enabled"]:
                    result["typo_fixed"] = True
                elif "Generative" in content_xml:
                    result["typo_fixed"] = True # Content correct

            # Paragraph Deletion: "Terminator 2"
            # If deleted with tracking, the text "Terminator 2" should still be in the file (in deletion buffer)
            # but marked as deleted.
            if "Terminator 2" in content_xml:
                # If it's still there, is it deleted?
                # We can't easily parse XML nesting with regex, but presence in a tracked-changes file usually implies deletion 
                # if the user followed instructions, OR they failed to delete it.
                # However, if they deleted it WITHOUT tracking, it would be gone.
                # If they deleted it WITH tracking, it stays in XML.
                if result["track_changes_enabled"]:
                    result["paragraph_deleted"] = True # Likely exists as deletion
            else:
                # Text is gone completely
                if result["track_changes_enabled"]:
                     # If track changes is ON but text is gone, maybe they didn't track THIS deletion?
                     # Or ODT saves it differently. Usually ODT keeps it.
                     pass 
                else:
                     # Deleted but not tracked
                     pass
                     
            # Refined Paragraph Deletion Logic:
            # We give credit if track changes is enabled AND "Terminator 2" is either present (buffered) or gone?
            # Actually, standard ODT behavior: deletions are kept in <text:deletion> inside <text:tracked-changes>.
            # So "Terminator 2" MUST be present in the file if tracked deletion occurred.
            if "Terminator 2" in content_xml and result["track_changes_enabled"]:
                 result["paragraph_deleted"] = True
            
    except Exception as e:
        result["error"] = str(e)

import datetime
result["export_timestamp"] = datetime.datetime.now().isoformat()

with open(RESULT_FILE, 'w') as f:
    json.dump(result, f)
PYEOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$RESULT_FILE" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="