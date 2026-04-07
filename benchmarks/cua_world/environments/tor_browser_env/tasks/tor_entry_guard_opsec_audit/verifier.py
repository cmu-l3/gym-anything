#!/usr/bin/env python3
"""
Verifier for tor_entry_guard_opsec_audit task.

Checks:
1. Did the agent create the output file?
2. Does it have the correct format?
3. Does the extracted fingerprint actually exist in the live Tor state file? (Anti-gaming gate)
4. Were the Country and AS Name populated?
5. Did the agent actually visit the metrics page? (History verification)
6. Optional VLM verification on trajectory to ensure GUI interaction.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tor_entry_guard_audit(traj, env_info, task_info):
    """Verify the Entry Guard OPSEC audit report."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Use try-finally to clean up the temp file reliably
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close()
    
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Result JSON not found or invalid."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    logger.info(f"Verification data: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []
    
    file_exists = result.get('file_exists', False)
    content = result.get('file_content', '')
    valid_fps = result.get('valid_guard_fingerprints', [])
    history_visited = result.get('history_visited_metrics', False)
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start_time', 0)

    # 1. File existence (10 pts)
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file /home/ga/Documents/guard_audit.txt was not created."
        }
    
    score += 10
    feedback_parts.append("File exists (10/10)")

    # Anti-gaming: Ensure file was created AFTER task start
    if file_mtime > 0 and task_start > 0 and file_mtime < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output file predates task start time. Invalid submission."
        }

    # Extract required fields via regex
    has_header = "=== ENTRY GUARD AUDIT ===" in content
    
    fp_match = re.search(r'Fingerprint:\s*([A-Fa-f0-9]{40})', content)
    country_match = re.search(r'Country:\s*(.+)', content)
    as_match = re.search(r'AS Name:\s*(.+)', content)

    extracted_fp = fp_match.group(1).upper() if fp_match else None
    extracted_country = country_match.group(1).strip() if country_match else None
    extracted_as = as_match.group(1).strip() if as_match else None

    # 2. Correct Formatting (10 pts)
    if has_header and extracted_fp and extracted_country and extracted_as:
        score += 10
        feedback_parts.append("Format correct (10/10)")
    else:
        feedback_parts.append("Format incomplete or headers missing (0/10)")

    # 3. Fingerprint Match against truth in `state` file (40 pts) - REQUIRED GATE
    fingerprint_gate_passed = False
    if extracted_fp:
        if extracted_fp in valid_fps:
            score += 40
            fingerprint_gate_passed = True
            feedback_parts.append(f"Fingerprint valid and matched local state file (40/40)")
        else:
            feedback_parts.append(f"Extracted Fingerprint ({extracted_fp}) NOT found in live Tor state file (0/40)")
    else:
        feedback_parts.append("No 40-char Fingerprint extracted from report (0/40)")

    # 4. Country extracted (10 pts)
    if extracted_country and len(extracted_country) > 1 and not extracted_country.startswith('['):
        score += 10
        feedback_parts.append("Country field populated (10/10)")
    else:
        feedback_parts.append("Country field missing or placeholder (0/10)")

    # 5. AS Name extracted (10 pts)
    if extracted_as and len(extracted_as) > 1 and not extracted_as.startswith('['):
        score += 10
        feedback_parts.append("AS Name field populated (10/10)")
    else:
        feedback_parts.append("AS Name field missing or placeholder (0/10)")

    # 6. Browser History Verification (20 pts)
    if history_visited:
        score += 20
        feedback_parts.append("Relay Search visit found in places.sqlite (20/20)")
    else:
        # Fallback to VLM Trajectory Verification if SQLite checking failed but work was done
        feedback_parts.append("Relay Search visit NOT found in history (0/20)")
        
        # Check if we can fallback to VLM verification of trajectory
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt = "Does any of these trajectory frames show the Tor Relay Search (metrics.torproject.org) interface in Tor Browser? Answer only YES or NO."
                vlm_result = query_vlm(images=frames, prompt=prompt)
                if "YES" in str(vlm_result).upper():
                    score += 20
                    feedback_parts[-1] = "Relay Search visit verified via VLM trajectory (20/20)"
        except Exception as e:
            logger.warning(f"VLM trajectory fallback failed or unavailable: {e}")

    # Pass threshold is 60 AND the Fingerprint Match Gate must be met
    passed = (score >= 60) and fingerprint_gate_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }