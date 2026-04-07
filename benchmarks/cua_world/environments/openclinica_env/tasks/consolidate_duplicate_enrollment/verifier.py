#!/usr/bin/env python3
"""Verifier for consolidate_duplicate_enrollment task."""

import json
import tempfile
import os
import logging
import sys

# Attempt to import gym_anything VLM utils securely
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback if unavailable
    def sample_trajectory_frames(traj, n=5):
        return []
    def get_final_screenshot(traj):
        return None

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine the screenshots of OpenClinica (a clinical trial management system).

Check the following:
1. Is OpenClinica visible in Firefox (not an error page, login page, or blank page)?
2. Is there a Subject Matrix, subject list, or event schedule visible?
3. Can you see any indication that subject 'DM-205' is removed/deleted (or absent), while 'DM-204' is active or updated?
4. Is there evidence of a secondary ID 'MRN-88492' or scheduled event for 'DM-204'?
5. Does the agent's workflow progression demonstrate the completion of this task?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "subject_matrix_visible": true/false,
    "dm204_updated_visible": true/false,
    "dm205_removed_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def _safe_int(value, default=0):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return default
    return default

def verify_consolidate_duplicate_enrollment(traj, env_info, task_info):
    """
    Verify task completion.
    
    Scoring:
    - DM-205 Removed (status_id != 1): 25 pts
    - DM-204 Secondary ID == 'MRN-88492': 25 pts
    - DM-204 Event Created (date is not empty): 25 pts
    - DM-204 Event Date Correct ('2024-05-15'): 15 pts
    - VLM Visual Confirmation: up to 10 pts
    - Direct DB Tampering Penalty: -100 if no GUI activity.

    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result Data Export
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/consolidate_duplicate_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Cross-Reference with Nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch"}

    score = 0
    feedback_parts = []
    
    dm205_status_id = _safe_int(result.get('dm205_status_id', 1), default=1)
    dm204_secondary_id = result.get('dm204_secondary_id', '').strip()
    dm204_event_date = result.get('dm204_event_date', '').strip()
    
    # ---------------------------------------------------------
    # Criterion 1: DM-205 Removed (25 pts)
    # ---------------------------------------------------------
    dm205_removed = False
    # In OpenClinica: 1=Available, 3=Removed, 4=Auto-Removed, 5=Deleted
    if dm205_status_id != 1:  
        score += 25
        dm205_removed = True
        feedback_parts.append(f"DM-205 successfully removed (status_id={dm205_status_id}) (+25)")
    else:
        feedback_parts.append("FAIL: DM-205 not removed (0/25)")

    # ---------------------------------------------------------
    # Criterion 2: DM-204 Secondary ID (25 pts)
    # ---------------------------------------------------------
    if dm204_secondary_id == 'MRN-88492':
        score += 25
        feedback_parts.append("DM-204 Secondary ID correctly updated (+25)")
    else:
        feedback_parts.append(f"FAIL: DM-204 Secondary ID is '{dm204_secondary_id}', expected 'MRN-88492' (0/25)")

    # ---------------------------------------------------------
    # Criterion 3: DM-204 Event Created (25 pts)
    # ---------------------------------------------------------
    dm204_event_created = False
    if dm204_event_date:
        score += 25
        dm204_event_created = True
        feedback_parts.append("DM-204 Baseline Assessment event scheduled (+25)")
    else:
        feedback_parts.append("FAIL: DM-204 Baseline Assessment event not found (0/25)")

    # ---------------------------------------------------------
    # Criterion 4: DM-204 Event Date Correct (15 pts)
    # ---------------------------------------------------------
    if dm204_event_date and '2024-05-15' in dm204_event_date:
        score += 15
        feedback_parts.append("DM-204 event date correct: 2024-05-15 (+15)")
    elif dm204_event_date:
        feedback_parts.append(f"FAIL: DM-204 event date is '{dm204_event_date}', expected 2024-05-15 (0/15)")

    # ---------------------------------------------------------
    # DB Tampering Check (Penalty)
    # ---------------------------------------------------------
    audit_baseline = _safe_int(result.get('audit_baseline_count', 0))
    audit_current = _safe_int(result.get('audit_log_count', 0))
    if audit_current <= audit_baseline:
        score -= 100
        feedback_parts.append("PENALTY: No GUI activity detected in audit log (direct DB manipulation suspected) (-100)")

    # ---------------------------------------------------------
    # VLM Verification (Up to 10 bonus pts)
    # ---------------------------------------------------------
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            images = frames
            if final_frame:
                images.append(final_frame)
            
            if images:
                try:
                    # Provide all frames representing trajectory
                    vlm_result = query_vlm(prompt=_build_vlm_prompt(), images=images)
                except Exception:
                    # Fallback single image support
                    vlm_result = query_vlm(prompt=_build_vlm_prompt(), image=images[-1])
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("openclinica_visible"):
                        vlm_score += 2
                    if parsed.get("subject_matrix_visible"):
                        vlm_score += 3
                    if parsed.get("dm204_updated_visible") or parsed.get("dm205_removed_visible"):
                        vlm_score += 5
                    
                    confidence = parsed.get("confidence", "low")
                    multiplier = {"high": 1.0, "medium": 0.8, "low": 0.5}.get(confidence, 0.5)
                    vlm_score = int(vlm_score * multiplier)
                    score += vlm_score
                    feedback_parts.append(f"VLM Visual Check: {vlm_score}/10 pts")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")

    passed = score >= 75 and dm205_removed and dm204_event_created

    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }