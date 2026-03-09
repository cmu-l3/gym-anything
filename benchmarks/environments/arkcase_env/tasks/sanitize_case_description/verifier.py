#!/usr/bin/env python3
"""
Verifier for sanitize_case_description task.

Criteria:
1. PII Removal (40 pts): The random phone number must be gone.
2. Redaction Marker (25 pts): The text '[REDACTED]' must be present.
3. Content Preservation (25 pts): The rest of the description must remain.
4. Case Found (10 pts): The case must still exist and be accessible.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sanitize_case_description(traj, env_info, task_info):
    """
    Verify that the agent removed the PII and added the redaction marker.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Programmatic Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Programmatic Criteria
    
    # Criterion A: Case Found (10 pts)
    if result.get("case_found", False):
        score += 10
        feedback_parts.append("Case found and accessible")
    else:
        return {"passed": False, "score": 0, "feedback": "Target case could not be verified (deleted or ID lost)"}

    # Criterion B: PII Removal (40 pts)
    if not result.get("pii_present", True):
        score += 40
        feedback_parts.append("PII successfully removed")
    else:
        feedback_parts.append(f"FAIL: PII ({result.get('pii_target')}) still present in description")

    # Criterion C: Redaction Marker (25 pts)
    if result.get("marker_present", False):
        score += 25
        feedback_parts.append("Redaction marker '[REDACTED]' found")
    else:
        feedback_parts.append("FAIL: Redaction marker '[REDACTED]' missing")

    # Criterion D: Content Preservation (25 pts)
    # The original description minus PII plus marker is roughly the same length.
    # We check if length > 30 chars (Original is ~140 chars)
    desc_len = result.get("description_length", 0)
    if desc_len > 30:
        score += 25
        feedback_parts.append("Narrative text preserved")
    else:
        feedback_parts.append(f"FAIL: Description text looks deleted/truncated (len: {desc_len})")

    # 3. Optional VLM Verification (Anti-Gaming / Sanity Check)
    # We check if the user actually opened a form dialog or edit mode
    if score >= 50:  # Only run expensive VLM if they are close to passing
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_prompt = (
                "Is the user editing a form in a case management system? "
                "Look for 'Edit' buttons, text input fields, or a case details view being modified."
            )
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer", False):
                feedback_parts.append("(VLM confirmed editing workflow)")
            # We don't deduct points for VLM failure here as the API check is definitive,
            # but it validates the workflow.

    passed = (score >= 75) and (not result.get("pii_present", True)) and result.get("marker_present", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }