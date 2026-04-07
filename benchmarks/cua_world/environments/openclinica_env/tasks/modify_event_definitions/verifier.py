#!/usr/bin/env python3
"""
Verifier for modify_event_definitions task.
Evaluates agent modifications to existing study event definitions in OpenClinica.
"""

import json
import tempfile
import os
import logging
import sys

# Attempt to import VLM utilities
try:
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine these screenshots from a session using OpenClinica (a clinical trial management system).

Check if the user interacted with the Study Setup or Event Definition pages:
1. Is the "Build Study" or "Update Study Event Definition" interface visible in any frame?
2. Can you see forms with fields for event definition "Name", "Description", "Type", or "Category"?
3. Is there evidence that the user was actively navigating the OpenClinica web application?

Respond in JSON format:
{
    "build_study_visible": true/false,
    "event_form_visible": true/false,
    "gui_interaction_evident": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation"
}
"""

def verify_modify_event_definitions(traj, env_info, task_info):
    """
    Verify modifications to study event definitions.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/modify_event_definitions_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check nonce
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
        return {
            "passed": False,
            "score": 0,
            "feedback": "INTEGRITY FAIL: Result file nonce mismatch. Possible tampering."
        }

    score = 0
    feedback_parts = []
    events = result.get('events', {})

    # --- Criterion 1: Baseline Assessment Name (20 pts) ---
    baseline = events.get('baseline', {})
    if baseline.get('exists'):
        bl_name = baseline.get('name', '').lower()
        if 'screening' in bl_name and 'baseline' in bl_name:
            score += 20
            feedback_parts.append("✅ Baseline name updated (+20)")
        else:
            feedback_parts.append(f"❌ Baseline name incorrect: '{baseline.get('name')}'")
    else:
        feedback_parts.append("❌ Baseline event not found")

    # --- Criterion 2: Baseline Assessment Description (15 pts) ---
    if baseline.get('exists'):
        bl_desc = baseline.get('description', '').lower()
        if 'amendment 03' in bl_desc:
            score += 15
            feedback_parts.append("✅ Baseline description updated (+15)")
        else:
            feedback_parts.append("❌ Baseline description missing 'Amendment 03'")

    # --- Criterion 3: Week 4 Repeating Property (20 pts) ---
    week4 = events.get('week4', {})
    if week4.get('exists'):
        is_repeating = week4.get('repeating', False)
        # Handle string variations just in case postgres returns 't'/'true'
        if is_repeating is True or str(is_repeating).lower() in ['true', 't', '1', 'yes']:
            score += 20
            feedback_parts.append("✅ Week 4 repeating set to True (+20)")
        else:
            feedback_parts.append("❌ Week 4 repeating not set to True")
    else:
        feedback_parts.append("❌ Week 4 event not found")

    # --- Criterion 4: Week 4 Category (15 pts) ---
    if week4.get('exists'):
        w4_cat = (week4.get('category') or '').lower()
        if 'treatment window' in w4_cat:
            score += 15
            feedback_parts.append("✅ Week 4 category updated (+15)")
        else:
            feedback_parts.append(f"❌ Week 4 category incorrect: '{week4.get('category')}'")

    # --- Criterion 5: End of Treatment Category (15 pts) ---
    eot = events.get('end_of_treatment', {})
    if eot.get('exists'):
        eot_cat = (eot.get('category') or '').lower()
        if 'study completion' in eot_cat:
            score += 15
            feedback_parts.append("✅ End of Treatment category updated (+15)")
        else:
            feedback_parts.append(f"❌ End of Treatment category incorrect: '{eot.get('category')}'")
    else:
        feedback_parts.append("❌ End of Treatment event not found")

    # --- Bonus: Adverse Event Unchanged (+5 pts) ---
    ae = events.get('adverse_event', {})
    if ae.get('exists'):
        ae_name = ae.get('name', '')
        ae_type = ae.get('type', '').lower()
        ae_rep = ae.get('repeating', True)
        is_rep_true = ae_rep is True or str(ae_rep).lower() in ['true', 't', '1']
        
        if 'Adverse Event' in ae_name and ae_type == 'unscheduled' and is_rep_true:
            score += 5
            feedback_parts.append("✅ Adverse Event untouched (+5 bonus)")
        else:
            feedback_parts.append("❌ Adverse Event was improperly modified")

    # --- Anti-Gaming: Audit Log Check ---
    audit_base = int(result.get('audit_baseline', 0))
    audit_curr = int(result.get('audit_current', 0))
    if audit_curr <= audit_base:
        score -= 25
        feedback_parts.append("🚨 PENALTY: No GUI interactions found in audit log (-25)")

    # --- VLM Verification (10 pts) ---
    if query_vlm and 'sample_trajectory_frames' in globals():
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                images = frames + [final]
                vlm_res = query_vlm(prompt=_build_vlm_prompt(), images=images)
                
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    gui_evident = parsed.get("gui_interaction_evident", False)
                    form_visible = parsed.get("event_form_visible", False)
                    
                    if gui_evident and form_visible:
                        score += 10
                        feedback_parts.append("👁️ VLM: Confirmed UI workflow (+10)")
                    elif gui_evident:
                        score += 5
                        feedback_parts.append("👁️ VLM: Partial UI workflow confirmed (+5)")
                    else:
                        feedback_parts.append("👁️ VLM: Could not confirm UI workflow")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")

    # Cap score at 100 max
    score = min(max(score, 0), 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }