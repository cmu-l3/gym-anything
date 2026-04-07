#!/usr/bin/env python3
"""Verifier for protocol_amendment_events task."""

import json
import tempfile
import os
import logging
import sys

logger = logging.getLogger(__name__)

# Import VLM utilities from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Handle gracefully if module structures differ
    def query_vlm(*args, **kwargs):
        return {"success": False, "error": "VLM not available in this environment"}
    def sample_trajectory_frames(*args, **kwargs):
        return []
    def get_final_screenshot(*args, **kwargs):
        return None


def _build_vlm_prompt():
    """Build VLM prompt to check if agent actually used the OpenClinica Build Study UI."""
    return """Examine these screenshots of OpenClinica taken during an agent's task execution.

Check the following:
1. Is the OpenClinica web interface visible in the browser?
2. Did the agent navigate to the "Build Study" or "View Event Definitions" pages?
3. Can you see forms indicating the creation of new Study Event Definitions (e.g., 'Week 4 Safety', 'Unscheduled Safety Visit')?
4. Is there evidence of interacting with the Event Definition creation fields (Name, Type, Repeating, Description)?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "build_study_ui_used": true/false,
    "event_forms_used": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation"
}
"""


def verify_protocol_amendment(traj, env_info, task_info):
    """
    Verify protocol_amendment_events task completion.

    Scoring (100 points base + bonuses/penalties):
    - 20 pts: Follow-up Visit removed (status != 1)
    - 20 pts: Week 4 Safety Assessment exists (status == 1)
    - 20 pts: Week 12 Efficacy Evaluation exists (status == 1)
    - 20 pts: Unscheduled Safety Visit exists (status == 1)
    - 20 pts: End of Treatment Visit exists (status == 1)
    - Up to +10 pts bonus: VLM visual verification of workflow
    - -15 pts penalty: Baseline Assessment modified/removed
    - -20 pts penalty: No audit log records (API/DB gaming detected)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/protocol_amendment_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found. Export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Integrity Verification
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
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Nonce mismatch (tampering detected)."}

    score = 0
    feedback_parts = []

    def check_bool_str(val, expected):
        """Helper to match postgres boolean representations to intended boolean state."""
        val = str(val).lower()
        if expected:
            return val in ['t', 'true', '1', 'yes']
        else:
            return val in ['f', 'false', '0', 'no']

    # --- Criterion 1: Follow-up Visit removed ---
    fu_status = result.get('followup', {}).get('status', 0)
    if fu_status != 1 and fu_status != 0:
        score += 20
        feedback_parts.append("✅ Follow-up Visit removed (+20)")
    elif fu_status == 0:
        # Edge case: It was deleted entirely (acceptable, though status=5 is standard UI removal)
        score += 20
        feedback_parts.append("✅ Follow-up Visit removed (hard deleted) (+20)")
    else:
        feedback_parts.append("❌ Follow-up Visit is still available (0/20)")

    # --- Criterion 2: Week 4 Safety Assessment ---
    w4 = result.get('week4', {})
    if w4.get('status') == 1:
        score += 20
        feedback = "✅ Week 4 Safety Assessment created (+20)"
        if w4.get('type') == 'scheduled' and check_bool_str(w4.get('repeating'), False):
            feedback += " [Correct Properties]"
        feedback_parts.append(feedback)
    else:
        feedback_parts.append("❌ Week 4 Safety Assessment not found or active (0/20)")

    # --- Criterion 3: Week 12 Efficacy Evaluation ---
    w12 = result.get('week12', {})
    if w12.get('status') == 1:
        score += 20
        feedback = "✅ Week 12 Efficacy Evaluation created (+20)"
        if w12.get('type') == 'scheduled' and check_bool_str(w12.get('repeating'), False):
            feedback += " [Correct Properties]"
        feedback_parts.append(feedback)
    else:
        feedback_parts.append("❌ Week 12 Efficacy Evaluation not found or active (0/20)")

    # --- Criterion 4: Unscheduled Safety Visit ---
    usv = result.get('unsched', {})
    if usv.get('status') == 1:
        score += 20
        feedback = "✅ Unscheduled Safety Visit created (+20)"
        if usv.get('type') == 'unscheduled' and check_bool_str(usv.get('repeating'), True):
            feedback += " [Correct Properties]"
        feedback_parts.append(feedback)
    else:
        feedback_parts.append("❌ Unscheduled Safety Visit not found or active (0/20)")

    # --- Criterion 5: End of Treatment Visit ---
    eot = result.get('end_trt', {})
    if eot.get('status') == 1:
        score += 20
        feedback = "✅ End of Treatment Visit created (+20)"
        if eot.get('type') == 'scheduled' and check_bool_str(eot.get('repeating'), False):
            feedback += " [Correct Properties]"
        feedback_parts.append(feedback)
    else:
        feedback_parts.append("❌ End of Treatment Visit not found or active (0/20)")

    # --- Penalty: Baseline Assessment Intact ---
    baseline = result.get('baseline', {})
    if baseline.get('status') != 1:
        score -= 15
        feedback_parts.append("⚠️ PENALTY: Baseline Assessment was modified or removed (-15)")

    # --- Penalty: Audit Log / Anti-gaming ---
    audit_base = result.get('audit_baseline', 0)
    audit_curr = result.get('audit_current', 0)
    if audit_curr <= audit_base:
        score -= 20
        feedback_parts.append("⚠️ PENALTY: No audit log records found. Suspected GUI bypass (-20)")

    # --- VLM Verification (Bonus Points) ---
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame and final_frame not in frames:
        frames.append(final_frame)
    
    if frames:
        vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=frames)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            ui_used = parsed.get("build_study_ui_used", False)
            forms_used = parsed.get("event_forms_used", False)
            if ui_used and forms_used:
                score += 10
                feedback_parts.append("🌟 VLM confirmed Build Study UI workflow (+10 bonus)")
            elif ui_used:
                score += 5
                feedback_parts.append("🌟 VLM confirmed OpenClinica UI usage (+5 bonus)")

    # Cap score at 100 max, allow negatives to floor to 0
    score = max(0, min(100, score))
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }