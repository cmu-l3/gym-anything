#!/usr/bin/env python3
"""
Verifier for tls_decryption_with_keylog task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tls_decryption(traj, env_info, task_info):
    """
    Verify that the user correctly decrypted the TLS traffic and extracted the secret flag.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    feedback_parts = []
    score = 0
    
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    user_content = result.get('user_content', '')
    ground_truth = result.get('ground_truth', '')
    pref_configured = result.get('pref_configured', False)

    # Criterion 1: Output file exists (20 pts)
    if output_exists:
        score += 20
        feedback_parts.append("Output file 'decrypted_flag.txt' exists")
    else:
        feedback_parts.append("Output file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Correct Secret Found (60 pts)
    # The secret is a UUID, randomly generated at runtime.
    # We require an exact match (whitespace was stripped in export).
    if user_content == ground_truth and len(ground_truth) > 0:
        score += 60
        feedback_parts.append("Correct secret flag found")
    else:
        feedback_parts.append(f"Incorrect secret. Expected '{ground_truth}', got '{user_content}'")

    # Criterion 3: Wireshark Configuration Detected (20 pts)
    # Checks if 'tls.keylog_file' appears in recent/preferences
    if pref_configured:
        score += 20
        feedback_parts.append("Wireshark TLS preferences updated")
    else:
        # If they got the right answer but didn't save prefs, maybe they used tshark CLI?
        # If the answer is correct, we might be lenient, but the task asked to Configure Wireshark.
        # However, if they got the exact UUID, they MUST have decrypted it somehow.
        if score >= 80: # They got the file and the secret
            feedback_parts.append("Wireshark prefs not saved, but decryption successful (full points)")
            score += 20
        else:
            feedback_parts.append("Wireshark TLS preferences not detected")

    # Anti-gaming check: File creation time
    if not file_created and output_exists:
        feedback_parts.append("WARNING: Output file timestamp suspicious (not created during task)")
        # We don't fail strictly here because file systems can be weird, but good to note.

    passed = score >= 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }