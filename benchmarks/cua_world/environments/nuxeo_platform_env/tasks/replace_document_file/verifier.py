#!/usr/bin/env python3
"""
Verifier for replace_document_file task.
Checks if the Nuxeo document's file blob was replaced while preserving metadata.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_replace_document_file(traj, env_info, task_info):
    """
    Verify that the 'Contract Template' document file was replaced correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # 1. Verify Document Exists (15 pts)
    if not result.get('doc_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The document 'Contract Template' no longer exists at the expected path."
        }
    score += 15
    feedback_parts.append("Document exists")

    # 2. Verify Blob Changed (25 pts) - CRITICAL
    initial_digest = result.get('initial_digest')
    current_digest = result.get('blob_digest')
    
    if not current_digest:
        feedback_parts.append("No file attached to document")
    elif current_digest == initial_digest:
        feedback_parts.append("File attachment was NOT changed (digest matches original)")
    else:
        score += 25
        feedback_parts.append("File attachment replaced successfully")

    # 3. Verify Metadata Preservation (25 pts)
    # Title must match exactly
    current_title = result.get('title', '')
    expected_title = "Contract Template"
    if current_title == expected_title:
        score += 15
        feedback_parts.append(f"Title preserved ('{current_title}')")
    else:
        feedback_parts.append(f"Title changed to '{current_title}' (expected '{expected_title}')")

    # Description must be preserved
    current_desc = result.get('description', '')
    expected_desc = "Standard service agreement template v1.0" # Set in setup_task.sh
    if current_desc == expected_desc:
        score += 10
        feedback_parts.append("Description preserved")
    else:
        feedback_parts.append(f"Description changed (expected '{expected_desc}')")

    # 4. Verify New Blob Content (15 pts)
    # Check if file size roughly matches the expected replacement file
    blob_length = result.get('blob_length', 0)
    expected_size = result.get('expected_file_size', 0)
    
    # Allow 20% tolerance (metadata/compression differences possible but unlikely for raw upload)
    # Since Nuxeo stores the raw blob, size should be identical usually.
    if expected_size > 0:
        size_diff = abs(blob_length - expected_size)
        tolerance = expected_size * 0.2
        if size_diff <= tolerance:
            score += 15
            feedback_parts.append(f"New file size matches expected ({blob_length} bytes)")
        else:
            feedback_parts.append(f"New file size ({blob_length}) differs significantly from source ({expected_size})")
    else:
        # Fallback if expected size unknown
        if blob_length > 0 and current_digest != initial_digest:
            score += 15 # Give benefit of doubt if we confirmed digest changed and have length
            feedback_parts.append("New file has valid length")

    # 5. Anti-Gaming / Timestamp Check (10 pts)
    # Nuxeo stores time in ISO 8601, e.g., "2023-10-27T10:00:00.00Z"
    last_modified_str = result.get('last_modified')
    task_start_ts = result.get('task_start', 0)
    
    modified_during_task = False
    if last_modified_str:
        try:
            # Handle 'Z' manually if python < 3.11 for fromisoformat
            if last_modified_str.endswith('Z'):
                last_modified_str = last_modified_str[:-1] + '+00:00'
            mod_time = datetime.fromisoformat(last_modified_str)
            if mod_time.timestamp() > task_start_ts:
                modified_during_task = True
        except Exception as e:
            logger.warning(f"Failed to parse timestamp: {e}")
            pass

    if modified_during_task:
        score += 10
        feedback_parts.append("Document modified during task window")
    elif current_digest != initial_digest:
        # If digest changed but timestamp parsing failed or lagged, we might still verify via digest
        pass 
    else:
        feedback_parts.append("Document not modified since task start")

    # 6. Trajectory/VLM Check (10 pts)
    # Simple check: did they produce a final screenshot showing the UI?
    if result.get('screenshot_path'):
        score += 10
        feedback_parts.append("Verification evidence provided")

    # Final Evaluation
    # Must have changed the blob to pass
    blob_changed = (current_digest != initial_digest) and (current_digest is not None)
    
    passed = (score >= 60) and blob_changed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }