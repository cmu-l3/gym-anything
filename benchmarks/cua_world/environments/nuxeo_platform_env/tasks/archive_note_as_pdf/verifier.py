#!/usr/bin/env python3
"""
Verifier for archive_note_as_pdf task.
Verifies that the agent exported a note as PDF and uploaded it back to Nuxeo.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archive_note_as_pdf(traj, env_info, task_info):
    """
    Verify the task based on Nuxeo API state and local file evidence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('archived_doc_title', 'Q3 Status Report - Archived')
    expected_desc = metadata.get('expected_description', 'Static archive of the Q3 report')
    expected_mime = metadata.get('expected_mimetype', 'application/pdf')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check if the archived document exists in Nuxeo (via API search result)
    search_data = result.get('search_result', {})
    entries = search_data.get('entries', [])
    
    doc_found = False
    doc_data = None
    
    if entries and len(entries) > 0:
        doc_data = entries[0]
        doc_found = True
        score += 20
        feedback.append("Archived document found in Nuxeo.")
    else:
        feedback.append("Archived document NOT found in Nuxeo.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 2. Verify Document Type (should be File)
    doc_type = doc_data.get('type', '')
    if doc_type == 'File':
        score += 10
        feedback.append("Document type is correct (File).")
    else:
        feedback.append(f"Incorrect document type: {doc_type} (expected File).")

    # 3. Verify Content (MIME type and data presence)
    properties = doc_data.get('properties', {})
    content = properties.get('file:content', {})
    
    if content:
        mime_type = content.get('mime-type', '')
        length = content.get('length', 0)
        
        if mime_type == expected_mime:
            score += 25
            feedback.append("Document content is PDF.")
        else:
            feedback.append(f"Incorrect MIME type: {mime_type}.")
            
        if try_parse_int(length) > 0:
            score += 15
            feedback.append("Document is not empty.")
        else:
            feedback.append("Document content is empty (0 bytes).")
    else:
        feedback.append("No file content attached to the document.")

    # 4. Verify Description
    actual_desc = properties.get('dc:description', '')
    if expected_desc in actual_desc:
        score += 15
        feedback.append("Description is correct.")
    else:
        feedback.append(f"Description mismatch. Expected '{expected_desc}', got '{actual_desc}'.")

    # 5. Verify Original Note Preservation
    if result.get('original_note_exists'):
        score += 15
        feedback.append("Original Note preserved.")
    else:
        feedback.append("Original Note seems to be missing.")

    # 6. Anti-gaming / Download evidence (Bonus/Validation)
    # Check if created timestamp is valid (after task start)
    # Note: We rely on the export script's timestamp check or Nuxeo's dc:created
    # dc:created format is ISO 8601 string
    
    # Using the local download evidence as a proxy for "did the agent actually download it?"
    if result.get('download_evidence'):
        feedback.append("Verified PDF download on filesystem.")
    else:
        # Not a hard fail, as they might have saved it elsewhere or renamed it
        feedback.append("No local download detected in Downloads folder (agent may have saved elsewhere).")

    # Calculate final status
    passed = score >= 65 and doc_found and (properties.get('file:content') is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }

def try_parse_int(value):
    try:
        return int(value)
    except (ValueError, TypeError):
        return 0