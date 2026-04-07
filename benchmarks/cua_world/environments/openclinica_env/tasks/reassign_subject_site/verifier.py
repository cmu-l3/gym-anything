#!/usr/bin/env python3
"""Verifier for reassign_subject_site task using hybrid DB and VLM trajectory analysis."""

import json
import tempfile
import os
import logging
import sys

# Import framework VLM utilities to sample trajectory frames
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallbacks if running outside standard framework structure
    def sample_trajectory_frames(traj, n=3): return []
    def get_final_screenshot(traj): return None

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """You are verifying an agent's trajectory in OpenClinica. 
The agent's task was to "Reassign" a subject from a main study to a site ("Boston Clinic") and change their ID to "BOS-101".

Look at these sequential screenshots from the agent's session:
1. Did the agent navigate through the OpenClinica web interface?
2. Is there evidence of the "Reassign Subject" page, Study/Site dropdowns, or the Subject Matrix?
3. Can you see the identifiers "BOS-101" or "Boston Clinic" being entered or successfully saved?

Respond with a JSON object:
{
    "used_gui": true/false,
    "reassign_workflow_visible": true/false,
    "identifiers_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""


def verify_reassign_subject_site(traj, env_info, task_info):
    """
    Verify the subject reassignment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/reassign_subject_site_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read DB results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Integrity Nonce
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

    if expected_nonce and result.get('result_nonce') != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "Integrity Failure: Nonce mismatch"}

    score = 0
    feedback_parts = []
    
    # 3. Database Criteria Checks
    bos101_exists = result.get('bos101_exists', False)
    bos101_study_id = result.get('bos101_study_id', 0)
    site_study_id = result.get('site_study_id', -1)
    dm101_exists = result.get('dm101_exists', True)
    
    db_criteria_met = False

    if bos101_exists:
        score += 30
        feedback_parts.append("✅ Subject renamed to BOS-101")
        
        if bos101_study_id == site_study_id and site_study_id != 0:
            score += 40
            feedback_parts.append("✅ Subject assigned to Boston Clinic site")
            db_criteria_met = True
        else:
            feedback_parts.append(f"❌ Subject study_id ({bos101_study_id}) does not match Boston Clinic ({site_study_id})")
    else:
        feedback_parts.append("❌ BOS-101 not found in database")

    if not dm101_exists:
        score += 10
        feedback_parts.append("✅ Old DM-101 label no longer exists")
    else:
        feedback_parts.append("❌ DM-101 still exists (subject duplicated instead of reassigned/renamed?)")

    # 4. Trajectory VLM Check (Anti-gaming & process verification)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=images)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_gui"): vlm_score += 5
                if parsed.get("reassign_workflow_visible"): vlm_score += 10
                if parsed.get("identifiers_visible"): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"✅ VLM Trajectory Verification: +{vlm_score}/20 pts")
            else:
                feedback_parts.append("⚠️ VLM verification failed to process")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for VLM")

    # 5. Audit Log Anti-gaming Penalty
    audit_diff = result.get('audit_current', 0) - result.get('audit_baseline', 0)
    if audit_diff <= 0 and db_criteria_met:
        score -= 100
        feedback_parts.append("🚨 PENALTY: DB changed but no OpenClinica audit logs generated. Direct SQL bypass detected.")

    passed = (score >= 70) and db_criteria_met
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts)
    }