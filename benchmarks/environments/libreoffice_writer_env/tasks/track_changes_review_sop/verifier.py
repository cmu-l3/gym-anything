#!/usr/bin/env python3
"""
Verifier for track_changes_review_sop task.
Verifies that the agent correctly accepted/rejected changes and cleaned up comments.
"""

import json
import os
import zipfile
import tempfile
import logging
from xml.etree import ElementTree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_track_changes_review(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_file = metadata.get('output_file', '/home/ga/Documents/records_request_sop_final.docx')
    required_text = metadata.get('required_text', [])
    forbidden_text = metadata.get('forbidden_text', [])

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Copy output document
    temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env(expected_file, temp_doc.name)
        
        # Analyze DOCX XML structure
        try:
            with zipfile.ZipFile(temp_doc.name, 'r') as z:
                xml_content = z.read('word/document.xml')
                tree = ElementTree.fromstring(xml_content)
                
                # Check for remaining tracked changes
                # Namespaces
                ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
                
                ins_count = len(tree.findall('.//w:ins', ns))
                del_count = len(tree.findall('.//w:del', ns))
                
                # Extract all text
                all_text = "".join(tree.itertext())
                
        except Exception as e:
             return {"passed": False, "score": 0, "feedback": f"Invalid DOCX file: {e}"}
             
    finally:
        if os.path.exists(temp_doc.name):
            os.unlink(temp_doc.name)

    # Scoring
    score = 0
    feedback = []

    # Criterion 1: No tracked changes remaining (30 pts)
    if ins_count == 0 and del_count == 0:
        score += 30
        feedback.append("Clean document (no tracked changes)")
    else:
        feedback.append(f"Document still has tracked changes (Ins: {ins_count}, Del: {del_count})")

    # Criterion 2: Content verification (Accepts) (35 pts)
    # Check for required text (should be present)
    found_required = 0
    for text in required_text:
        if text in all_text:
            found_required += 1
        else:
            feedback.append(f"Missing required text: '{text}'")
    
    score += int(35 * (found_required / len(required_text))) if required_text else 35

    # Criterion 3: Content verification (Rejects) (25 pts)
    # Check for forbidden text (should be absent)
    # 'Forbidden' here means text that should have been rejected (e.g., "may acknowledge")
    avoided_forbidden = 0
    for text in forbidden_text:
        if text not in all_text:
            avoided_forbidden += 1
        else:
            feedback.append(f"Found forbidden text (should have been rejected): '{text}'")
            
    score += int(25 * (avoided_forbidden / len(forbidden_text))) if forbidden_text else 25

    # Criterion 4: Comments removed (10 pts)
    # We implemented comments as text markers like [COMMENT: ...] in the setup script
    if "[COMMENT:" not in all_text:
        score += 10
        feedback.append("Comments removed")
    else:
        feedback.append("Comments still present in text")

    passed = score >= 70 and (ins_count + del_count == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }