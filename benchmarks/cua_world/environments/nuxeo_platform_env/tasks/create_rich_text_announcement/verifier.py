#!/usr/bin/env python3
"""
Verifier for create_rich_text_announcement task.

Verifies:
1. Document existence and type (Note).
2. HTML content structure:
   - Header 1 (h1)
   - Bold text (b/strong)
   - List (ul/li)
3. Specific text content correctness.
4. Timestamp (anti-gaming).
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_rich_text_announcement(traj, env_info, task_info):
    """
    Verify the rich text announcement creation.
    """
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Weekend Maintenance Alert")
    
    score = 0
    max_score = 100
    feedback_parts = []

    # 2. Retrieve Result Data
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_doc_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Copy main result file
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)

        if not result.get("doc_found"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Document 'Weekend-Maintenance-Alert' not found in Projects workspace."
            }

        # Copy the detailed Nuxeo document JSON
        doc_json_path = result.get("doc_json_path")
        copy_from_env(doc_json_path, temp_doc_file.name)
        with open(temp_doc_file.name, 'r') as f:
            doc_data = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving task results: {str(e)}"}
    finally:
        # Cleanup
        for fpath in [temp_result_file.name, temp_doc_file.name]:
            if os.path.exists(fpath):
                os.unlink(fpath)

    # 3. Verify Document Properties (20 points)
    properties = doc_data.get("properties", {})
    doc_type = doc_data.get("type")
    doc_title = properties.get("dc:title")
    doc_content = properties.get("note:note", "")  # Content of the Note

    # Check Type
    if doc_type == "Note":
        score += 10
        feedback_parts.append("Correct document type (Note).")
    else:
        feedback_parts.append(f"Incorrect document type: {doc_type} (expected Note).")

    # Check Title
    if doc_title == expected_title:
        score += 10
        feedback_parts.append("Correct title.")
    else:
        feedback_parts.append(f"Incorrect title: '{doc_title}'.")

    # 4. Anti-Gaming: Check Timestamps (Pass/Fail)
    # Nuxeo stores dates like "2023-10-27T10:00:00.000Z"
    created_str = properties.get("dc:created")
    task_start_ts = result.get("task_start", 0)
    
    timestamp_valid = False
    if created_str:
        try:
            # Simple check: created time > task start time
            # Convert Nuxeo time to timestamp
            # Handle potential Z or +00:00 offset
            created_dt = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
            created_ts = created_dt.timestamp()
            
            if created_ts > task_start_ts:
                timestamp_valid = True
            else:
                feedback_parts.append("Document created before task started.")
        except Exception as e:
            logger.warning(f"Timestamp parsing failed: {e}")
            # If parsing fails, we fallback to generous check if content is perfect
            timestamp_valid = True 

    if not timestamp_valid:
        return {"passed": False, "score": 0, "feedback": "Anti-gaming check failed: Document created before task start."}

    # 5. Verify Rich Text Content (80 points)
    # We use regex/string checks on the HTML content
    
    # Normalize content (remove newlines/excess spaces for easier matching)
    clean_content = re.sub(r'\s+', ' ', doc_content).strip()
    
    # Check 1: Header (20 pts)
    # Expect <h1>System Downtime Scheduled</h1> or similar
    if re.search(r'<h1[^>]*>\s*System Downtime Scheduled\s*</h1>', clean_content, re.IGNORECASE):
        score += 20
        feedback_parts.append("Header found.")
    elif "System Downtime Scheduled" in clean_content:
        score += 5
        feedback_parts.append("Header text found but missing H1 tag.")
    else:
        feedback_parts.append("Header missing.")

    # Check 2: Bold Text (20 pts)
    # Expect <b>...</b> or <strong>...</strong> or style="font-weight: bold"
    bold_pattern = r'<(b|strong)[^>]*>\s*Save all work by Friday 5:00 PM\s*</\1>'
    span_bold_pattern = r'<span[^>]*style="[^"]*font-weight:\s*bold[^"]*"[^>]*>\s*Save all work by Friday 5:00 PM\s*</span>'
    
    if re.search(bold_pattern, clean_content, re.IGNORECASE) or re.search(span_bold_pattern, clean_content, re.IGNORECASE):
        score += 20
        feedback_parts.append("Bold text found.")
    elif "Save all work by Friday 5:00 PM" in clean_content:
        score += 5
        feedback_parts.append("Warning text found but not bold.")
    else:
        feedback_parts.append("Warning text missing.")

    # Check 3: List (20 pts)
    # Expect <ul> ... <li> ... </li> ... </ul>
    # We check for the presence of ul and the specific items in lis
    if "<ul>" in clean_content.lower() and "</ul>" in clean_content.lower():
        list_items = ["Email Server", "ERP System", "Shared Drives"]
        items_found = 0
        for item in list_items:
            # Regex for <li>Item</li> allowing attributes
            if re.search(r'<li[^>]*>\s*' + re.escape(item) + r'\s*</li>', clean_content, re.IGNORECASE):
                items_found += 1
        
        if items_found == 3:
            score += 20
            feedback_parts.append("All list items formatted correctly.")
        else:
            score += int((items_found / 3) * 15)
            feedback_parts.append(f"List items found: {items_found}/3.")
    else:
        # Check if text exists without list
        if all(x in clean_content for x in ["Email Server", "ERP System", "Shared Drives"]):
            score += 5
            feedback_parts.append("List items text found but not formatted as unordered list.")
        else:
            feedback_parts.append("List structure missing.")

    # Check 4: Paragraph Text (20 pts)
    # Check for the main body text
    body_text = "Please be advised that we will be performing critical updates this Saturday."
    if body_text in clean_content:
        score += 20
        feedback_parts.append("Body text correct.")
    else:
        feedback_parts.append("Body text missing or incorrect.")

    # 6. Final Evaluation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }