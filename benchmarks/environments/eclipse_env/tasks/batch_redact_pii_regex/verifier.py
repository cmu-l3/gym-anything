#!/usr/bin/env python3
"""Verifier for batch_redact_pii_regex task."""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_redact_pii_regex(traj, env_info, task_info):
    """
    Verify that PII was redacted using regex search/replace.
    
    Criteria:
    1. Zero real SSNs remaining (Critical) - 35 pts
    2. Zero real MRNs remaining (Critical) - 35 pts
    3. Correct number of placeholders found (Validation) - included in above, 
       but ensures they didn't just delete the text.
    4. Files still exist - 15 pts
    5. VLM: Evidence of using Search/Replace dialog - 15 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result JSON
    result_data = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}

    # Extract metrics
    ssn_remaining = result_data.get('ssn_remaining', 999)
    mrn_remaining = result_data.get('mrn_remaining', 999)
    ssn_redacted = result_data.get('ssn_redacted', 0)
    mrn_redacted = result_data.get('mrn_redacted', 0)
    files_exist = result_data.get('files_exist', False)
    
    # Expected counts (from task design)
    EXPECTED_SSN_COUNT = 15
    EXPECTED_MRN_COUNT = 10
    
    score = 0
    feedback = []
    
    # 1. SSN Redaction (35 pts)
    if ssn_remaining == 0:
        if ssn_redacted >= EXPECTED_SSN_COUNT:
            score += 35
            feedback.append(f"SSN redaction complete ({ssn_redacted} placeholders).")
        else:
            # They deleted some SSNs instead of replacing
            score += 20
            feedback.append(f"SSNs removed, but count mismatch (found {ssn_redacted} placeholders, expected {EXPECTED_SSN_COUNT}). Potential data loss.")
    else:
        feedback.append(f"FAILED: {ssn_remaining} real SSNs still found in files.")

    # 2. MRN Redaction (35 pts)
    if mrn_remaining == 0:
        if mrn_redacted >= EXPECTED_MRN_COUNT:
            score += 35
            feedback.append(f"MRN redaction complete ({mrn_redacted} placeholders).")
        else:
            score += 20
            feedback.append(f"MRNs removed, but count mismatch (found {mrn_redacted} placeholders, expected {EXPECTED_MRN_COUNT}). Potential data loss.")
    else:
        feedback.append(f"FAILED: {mrn_remaining} real MRNs still found in files.")

    # 3. File Integrity (15 pts)
    if files_exist:
        score += 15
    else:
        feedback.append("CRITICAL: One or more project files were deleted.")

    # 4. VLM Verification (15 pts)
    # Check if they used the Search dialog (Ctrl+H)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, num_samples=5)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        prompt = """
        Review these screenshots of an agent working in Eclipse IDE.
        The goal was to perform a "Search and Replace" using Regular Expressions.
        
        Look for:
        1. The "Search" dialog window (often tabbed "File Search").
        2. The "Regular expression" checkbox being checked.
        3. A regex pattern like "\\d{3}-\\d{2}" or "MRN-" entered in the 'Containing text' field.
        4. The "Replace..." or "Replace All" workflow being used.
        
        Did the agent use the Search/Replace dialog with regex?
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, images=frames).get('parsed', {})
            # We assume query_vlm returns a standard structure or we parse the text
            # Since the simpler query_vlm returns a dict with 'response', let's assume simple boolean checking
            # But the provided utils suggest 'parsed' dict if using structured output. 
            # We'll stick to a simpler heuristic if structured isn't guaranteed.
            
            # Simple heuristic check on response text if 'parsed' is empty
            resp_text = str(vlm_resp) if vlm_resp else ""
            if "yes" in resp_text.lower() or "true" in resp_text.lower():
                vlm_score = 15
                feedback.append("VLM confirmed usage of Search/Replace dialog.")
            else:
                feedback.append("VLM did not definitively confirm Search dialog usage.")
                
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            # Fallback: if score is high (perfect redaction), give benefit of doubt for UI usage
            if score >= 85:
                vlm_score = 15
                feedback.append("VLM skipped, assuming UI usage due to perfect result.")
    
    score += vlm_score

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " ".join(feedback)
    }