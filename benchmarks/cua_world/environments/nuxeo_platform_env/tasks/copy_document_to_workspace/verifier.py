#!/usr/bin/env python3
"""
Verifier for copy_document_to_workspace task.

Verification Logic:
1. Original Document Integrity (30 pts):
   - The document must still exist in the 'Projects' workspace.
   - It must have the same UID as recorded at the start (ensures it wasn't deleted and recreated).
   
2. Copy Existence (40 pts):
   - A document with title "Annual Report 2023" must exist in 'Templates'.
   - It must have a DIFFERENT UID than the original (ensures it's a copy, not a move).
   - It must have file content attached.
   
3. Anti-Gaming / Process (30 pts):
   - The copy's creation time must be AFTER the task start time.
   - VLM verification of the UI workflow (optional but recommended).

Pass Threshold: 100/100 (Strict verification for this specific workflow)
"""

import json
import os
import tempfile
import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_nuxeo_timestamp(ts_str):
    """Parses Nuxeo ISO 8601 timestamp (e.g. 2023-10-27T10:00:00.00Z) to unix timestamp."""
    try:
        if not ts_str: return 0
        # Replace Z with +00:00 for strict isoformat compatibility if needed, 
        # though recent python handles Z.
        ts_str = ts_str.replace('Z', '+00:00')
        dt = datetime.datetime.fromisoformat(ts_str)
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Failed to parse timestamp {ts_str}: {e}")
        return 0

def verify_copy_document_to_workspace(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Retrieve result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check 1: Original Document Integrity (30 pts) ---
    original_exists = result.get("original_still_exists_at_source", False)
    if original_exists:
        score += 30
        feedback.append("Original document correctly preserved in Projects workspace.")
    else:
        feedback.append("FAIL: Original document is missing from Projects workspace (Likely moved instead of copied).")

    # --- Check 2: Copy Existence & Validity (40 pts) ---
    copy_data = result.get("copy_document", {})
    copy_found = copy_data.get("found", False)
    copy_uid = copy_data.get("uid")
    original_uid = result.get("original_uid_start")
    
    if copy_found:
        if copy_uid != original_uid:
            score += 30
            feedback.append("Copy found in Templates workspace with new UID.")
            
            if copy_data.get("has_content"):
                score += 10
                feedback.append("Copy contains file content.")
            else:
                feedback.append("Warning: Copy exists but has no file content.")
        else:
            # If UIDs match, the document path changed but ID is same -> verification script logic handles checking path.
            # However, our export script specifically looked for doc at path/Templates.
            # If the UID is the same, it means Nuxeo considers it the same object, which implies a Move.
            # But technically Nuxeo objects are path-addressable. 
            # If 'original_still_exists_at_source' is true AND this is true, that's impossible for same UID unless proxy/link.
            # We enforce Copy implies New Object (New UID).
            feedback.append("FAIL: Document in Templates has same UID as original (Proxy or Move detected, not a Copy).")
    else:
        feedback.append("FAIL: No document titled 'Annual Report 2023' found in Templates workspace.")

    # --- Check 3: Anti-Gaming / Timestamp (30 pts) ---
    # Only verify this if we actually found a copy
    if copy_found and copy_uid != original_uid:
        task_start = result.get("task_start_time", 0)
        created_str = copy_data.get("created", "")
        created_ts = parse_nuxeo_timestamp(created_str)
        
        if created_ts > task_start:
            score += 30
            feedback.append("Copy was created during the task session.")
        else:
            feedback.append(f"FAIL: Document appears to be pre-existing (Created: {created_str}).")
    else:
        feedback.append("Skipping timestamp check due to missing copy.")

    # Final Pass/Fail determination
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }