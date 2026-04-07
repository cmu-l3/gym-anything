#!/usr/bin/env python3
"""
Verifier for clinical_data_audit task.
Validates extraction of UI-bound audit logs and administrative event locking.
"""

import os
import json
import logging
import tempfile
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm, sample_trajectory_frames

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine these screenshots of an agent operating OpenClinica.
Did the agent open the 'Discrepancy Notes' or 'Audit Logs' modal window?
Look for a popup table containing audit history, discrepancy notes, or data point changes.

Respond in JSON format:
{
    "audit_modal_opened": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Briefly describe if the modal is visible."
}
"""

def verify_clinical_data_audit(traj, env_info, task_info):
    """
    Scoring Breakdown (100 pts total):
    - Findings File Exists: 10 pts
    - Original Value Found ('195'): 15 pts
    - Modified Value Found ('125'): 15 pts
    - Username Found ('mrivera'): 15 pts
    - Reason Keyword Found ('transcription'): 15 pts
    - Event Locked in DB (status_id = 7, 6, or 5): 30 pts
    - Direct DB Query Penalty: -50 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Read Exported Results ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/clinical_data_audit_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result JSON not found. Export script failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. File Evaluation
    file_exists = result.get('file_exists', False)
    content = result.get('file_content', '').lower()

    if file_exists:
        score += 10
        feedback.append("File 'audit_findings.txt' exists (+10)")
        
        # Verify content attributes
        if '195' in content:
            score += 15
            feedback.append("Found original value '195' (+15)")
        else:
            feedback.append("Missing original value '195' (0/15)")

        if '125' in content:
            score += 15
            feedback.append("Found modified value '125' (+15)")
        else:
            feedback.append("Missing modified value '125' (0/15)")

        if 'mrivera' in content:
            score += 15
            feedback.append("Found username 'mrivera' (+15)")
        else:
            feedback.append("Missing username 'mrivera' (0/15)")

        if 'transcription' in content:
            score += 15
            feedback.append("Found reason 'transcription' (+15)")
        else:
            feedback.append("Missing reason 'transcription' (0/15)")
    else:
        feedback.append("File 'audit_findings.txt' NOT found (0/70 for file checks)")

    # 2. Event Locking Status
    # status_id 4 = Completed. status_id 5, 6, 7 are Stopped, Skipped, Locked variants
    # The UI lock sets it to 7 (Locked) usually, but we accept >= 5 to cover administrative stops/freezes.
    event_status = result.get('event_status_id', 0)
    if event_status >= 5:
        score += 30
        feedback.append("Event successfully locked in DB (+30)")
    else:
        feedback.append(f"Event is NOT locked (status_id: {event_status}) (0/30)")

    # 3. Anti-Gaming Check
    if result.get('psql_used', False):
        score -= 50
        feedback.append("PENALTY: Direct database terminal interaction detected (-50)")

    # 4. Optional VLM Context (To confirm UI trajectory)
    try:
        frames = sample_trajectory_frames(traj, n=6)
        if frames and env_info.get('query_vlm'):
            vlm_res = env_info['query_vlm'](prompt=_build_vlm_prompt(), images=frames)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('audit_modal_opened', False):
                feedback.append("VLM confirmed audit modal was visually opened.")
    except Exception as e:
        logger.warning(f"VLM trajectory check failed: {e}")

    # Final logic
    passed = (score >= 70) and file_exists and (event_status >= 5) and not result.get('psql_used', False)
    
    # Floor score at 0
    score = max(0, score)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }