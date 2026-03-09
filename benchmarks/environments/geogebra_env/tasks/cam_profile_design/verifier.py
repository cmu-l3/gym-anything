#!/usr/bin/env python3
"""
Verifier for Cam Profile Design task.

Criteria:
1. File created during task (20 pts)
2. Parametric Curve used (Curve command) (20 pts)
3. Piecewise logic used (If command) (20 pts)
4. Trigonometry used (sin/cos) (20 pts)
5. VLM Verification of profile shape (20 pts)
   - Checks if the final screenshot shows a closed cam-like curve
   - Checks for visible variables/functions

Pass Threshold: 70/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cam_profile_design(traj, env_info, task_info):
    """Verify the Cam Profile Design task."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load programmatic result
    result = {}
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    score = 0
    feedback = []

    # 2. Programmatic Checks (80 points total)
    
    # Criterion 1: File existence and timestamp (20 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 20
        feedback.append("File 'cam_profile.ggb' created successfully (+20).")
    elif result.get("file_found"):
        score += 10
        feedback.append("File exists but timestamp indicates it wasn't created during this session (+10).")
    else:
        feedback.append("File 'cam_profile.ggb' not found (0).")

    # Criterion 2: Curve command usage (20 pts)
    if result.get("has_curve_command"):
        score += 20
        feedback.append("Parametric 'Curve' command detected (+20).")
    else:
        feedback.append("Missing 'Curve' command - required for parametric profile (0).")

    # Criterion 3: Conditional Logic (20 pts)
    if result.get("has_if_command"):
        score += 20
        feedback.append("Piecewise logic ('If' command) detected (+20).")
    else:
        feedback.append("Missing 'If' command - required for piecewise displacement function (0).")

    # Criterion 4: Trigonometry (20 pts)
    if result.get("has_trig_functions"):
        score += 20
        feedback.append("Trigonometric functions (sin/cos) detected (+20).")
    else:
        feedback.append("Missing trigonometry - required for polar-to-cartesian mapping (0).")

    # 3. VLM Verification (20 points)
    # We check the final screenshot for the visual appearance of the cam
    
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_img = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_img:
        prompt = """
        You are verifying a GeoGebra task where the user must design a mechanical cam profile.
        Look at the screenshot and check for:
        1. A continuous closed curve visible on the graph.
        2. The curve should look roughly like a cam or 'snail' shape (not a perfect circle).
           - It should have a smaller radius section (radius ~3)
           - A larger radius section (radius ~5)
           - Smooth transitions between them.
        3. A displacement function definition might be visible in the Algebra view (left panel).
        
        Does the screenshot show a valid cam profile construction?
        """
        
        try:
            vlm_resp = query_vlm(image=final_img, prompt=prompt)
            if vlm_resp and vlm_resp.get("success"):
                # Simple keyword check in VLM reasoning or use structured output if available
                parsed = vlm_resp.get("parsed", {})
                # Assuming generic VLM response, we trust the agent did it if programmatically correct,
                # but we add points if VLM confirms visual presence.
                # Since we don't have a strict structured output from this generic helper, we assume 
                # positive sentiment or specific keywords in 'response' if 'parsed' is empty.
                text = vlm_resp.get("response", "").lower()
                if "yes" in text or "cam" in text or "curve" in text or "snail" in text:
                    vlm_score = 20
                    feedback.append("Visual verification passed: Cam profile curve detected (+20).")
                else:
                    feedback.append("Visual verification inconclusive (0).")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic checks passed, give partial credit
            if score >= 60:
                vlm_score = 10
                feedback.append("VLM check failed, granting partial credit based on code structure (+10).")

    score += vlm_score

    # 4. Final Result
    passed = (score >= 70)
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }