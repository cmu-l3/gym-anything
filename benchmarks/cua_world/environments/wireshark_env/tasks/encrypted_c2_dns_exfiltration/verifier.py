#!/usr/bin/env python3
"""
Verifier for encrypted_c2_dns_exfiltration task.

Scoring (100 points total):
  - c2_server_sni:     15 pts (case-insensitive exact match)
  - c2_command_text:   20 pts (JSON-parsed key equality)
  - exfil_domain:      15 pts (case-insensitive exact match)
  - exfil_source_ip:   10 pts (exact match)
  - decoded_sha256:    25 pts (case-insensitive hex match)
  - decoded_first_line:15 pts (exact string match, whitespace-stripped)

Pass threshold: score >= 70 AND valid JSON output AND file created during task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """Verify the forensic evidence report."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result assembled by export_result.sh
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

    # Basic checks
    if not result.get('output_exists'):
        return {"passed": False, "score": 0,
                "feedback": "Output file forensic_evidence.json not found"}

    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0,
                "feedback": "Output file was not created during the task"}

    user = result.get('user_json', {})
    gt = result.get('ground_truth', {})

    if not user:
        return {"passed": False, "score": 0,
                "feedback": "Output file is not valid JSON or is empty"}

    score = 0
    feedback = []

    # --- 1. c2_server_sni (15 pts) ---
    user_sni = str(user.get('c2_server_sni', '')).strip().lower()
    gt_sni = str(gt.get('c2_server_sni', '')).strip().lower()
    if user_sni and user_sni == gt_sni:
        score += 15
        feedback.append("c2_server_sni correct")
    else:
        feedback.append(f"c2_server_sni wrong (got '{user_sni}')")

    # --- 2. c2_command_text (20 pts) ---
    # Parse both as JSON and compare key-value pairs
    try:
        user_cmd = user.get('c2_command_text', '')
        if isinstance(user_cmd, str):
            user_cmd_parsed = json.loads(user_cmd)
        else:
            user_cmd_parsed = user_cmd

        gt_cmd = gt.get('c2_command_text', '')
        if isinstance(gt_cmd, str):
            gt_cmd_parsed = json.loads(gt_cmd)
        else:
            gt_cmd_parsed = gt_cmd

        if user_cmd_parsed == gt_cmd_parsed:
            score += 20
            feedback.append("c2_command_text correct")
        else:
            # Partial credit: check key fields
            partial = 0
            for key in ['domain', 'xor_key', 'method']:
                if user_cmd_parsed.get(key) == gt_cmd_parsed.get(key):
                    partial += 5
            score += min(partial, 15)
            feedback.append(f"c2_command_text partial match ({partial}/20)")
    except (json.JSONDecodeError, TypeError, AttributeError):
        feedback.append("c2_command_text not valid JSON")

    # --- 3. exfil_domain (15 pts) ---
    user_domain = str(user.get('exfil_domain', '')).strip().lower()
    gt_domain = str(gt.get('exfil_domain', '')).strip().lower()
    if user_domain and user_domain == gt_domain:
        score += 15
        feedback.append("exfil_domain correct")
    else:
        feedback.append(f"exfil_domain wrong (got '{user_domain}')")

    # --- 4. exfil_source_ip (10 pts) ---
    user_ip = str(user.get('exfil_source_ip', '')).strip()
    gt_ip = str(gt.get('exfil_source_ip', '')).strip()
    if user_ip and user_ip == gt_ip:
        score += 10
        feedback.append("exfil_source_ip correct")
    else:
        feedback.append(f"exfil_source_ip wrong (got '{user_ip}')")

    # --- 5. decoded_sha256 (25 pts) ---
    user_hash = str(user.get('decoded_sha256', '')).strip().lower()
    gt_hash = str(gt.get('decoded_sha256', '')).strip().lower()
    if user_hash and len(user_hash) == 64 and user_hash == gt_hash:
        score += 25
        feedback.append("decoded_sha256 correct")
    else:
        feedback.append(f"decoded_sha256 wrong")

    # --- 6. decoded_first_line (15 pts) ---
    user_line = str(user.get('decoded_first_line', '')).strip()
    gt_line = str(gt.get('decoded_first_line', '')).strip()
    if user_line and user_line == gt_line:
        score += 15
        feedback.append("decoded_first_line correct")
    else:
        # Partial credit for close match
        if user_line and gt_line and user_line.lower() == gt_line.lower():
            score += 10
            feedback.append("decoded_first_line correct (case-insensitive)")
        else:
            feedback.append(f"decoded_first_line wrong (got '{user_line}')")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
