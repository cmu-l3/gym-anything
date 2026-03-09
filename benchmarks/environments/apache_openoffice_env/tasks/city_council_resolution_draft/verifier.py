#!/usr/bin/env python3
"""
Verifier for City Council Resolution Draft task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolution(traj, env_info, task_info):
    """
    Verify the created resolution document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_contractor = metadata.get("contractor", "Climate Control Systems").lower()
    expected_amount_part = "248,500"
    expected_account = "505-8200-562.45-01"
    
    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/safe_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Evaluation
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timestamp (10 pts)
    if result.get("file_exists") and result.get("timestamp_valid"):
        score += 10
        feedback_parts.append("File created successfully.")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("File exists but timestamp verification failed (modified before task?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Resolution file not found."}

    # 2. Line Numbering (30 pts) - CRITICAL TECHNICAL SKILL
    if result.get("line_numbering_enabled"):
        score += 30
        feedback_parts.append("Line numbering enabled.")
    else:
        feedback_parts.append("Line numbering NOT enabled (Tools > Line Numbering required).")

    # 3. Content Verification (Contractor, Amount, Account) (30 pts)
    content_text = result.get("content_text", "").lower()
    
    # Contractor
    if expected_contractor in content_text:
        score += 10
        feedback_parts.append("Contractor name correct.")
    else:
        feedback_parts.append(f"Contractor name missing or incorrect (expected '{expected_contractor}').")

    # Amount
    if expected_amount_part in content_text or expected_amount_part.replace(",", "") in content_text:
        score += 10
        feedback_parts.append("Contract amount correct.")
    else:
        feedback_parts.append(f"Contract amount missing (expected '{expected_amount_part}').")

    # Account
    if expected_account in content_text:
        score += 10
        feedback_parts.append("Account code correct.")
    else:
        feedback_parts.append("Account code missing.")

    # 4. Structure (WHEREAS clauses) (20 pts)
    whereas_count = result.get("whereas_count", 0)
    if whereas_count >= 3:
        score += 20
        feedback_parts.append(f"Preamble correct ({whereas_count} WHEREAS clauses).")
    elif whereas_count > 0:
        score += 10
        feedback_parts.append(f"Preamble incomplete ({whereas_count} WHEREAS clauses, expected 3+).")
    else:
        feedback_parts.append("Missing 'WHEREAS' preamble clauses.")

    # 5. Signature Block (10 pts)
    if "mayor" in content_text and "city clerk" in content_text:
        score += 10
        feedback_parts.append("Signature block present.")
    else:
        feedback_parts.append("Signature block missing (Mayor/City Clerk).")

    # Final Pass Determination
    # Must have file, Line Numbering, and at least some correct content
    passed = (score >= 70) and result.get("line_numbering_enabled")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }