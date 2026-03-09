#!/usr/bin/env python3
"""
Verifier for create_goods_receipt task in Manager.io.
"""

import json
import tempfile
import os
import logging

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_goods_receipt(traj, env_info, task_info):
    """
    Verify that the Goods Receipts module was enabled and the correct receipt created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Module Enabled (15 pts)
    if result.get("module_enabled"):
        score += 15
        feedback.append("Goods Receipts module enabled (+15)")
    else:
        feedback.append("FAIL: Goods Receipts module NOT enabled")

    # 2. Verify Record Created (15 pts)
    # Anti-gaming: Ensure count increased
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    
    if current_count > initial_count:
        score += 15
        feedback.append("New goods receipt created (+15)")
    else:
        feedback.append("FAIL: No new goods receipt record found")

    # 3. Verify Details (Programmatic) (45 pts total)
    details = result.get("details", {})
    
    if details.get("supplier_correct"):
        score += 15
        feedback.append("Supplier 'Exotic Liquids' correct (+15)")
    else:
        feedback.append("FAIL: Supplier incorrect or missing")

    if details.get("date_correct"):
        score += 10
        feedback.append("Date '2024-07-15' correct (+10)")
    else:
        feedback.append("FAIL: Date incorrect")

    if details.get("ref_correct"):
        score += 10
        feedback.append("Reference 'GR-2024-001' correct (+10)")
    else:
        feedback.append("FAIL: Reference incorrect")

    if details.get("chai_correct"):
        score += 5
        feedback.append("Line Item: Chai (50) found (+5)")
    else:
        feedback.append("FAIL: Chai item missing or wrong quantity")

    if details.get("chang_correct"):
        score += 5
        feedback.append("Line Item: Chang (30) found (+5)")
    else:
        feedback.append("FAIL: Chang item missing or wrong quantity")

    # 4. VLM Verification (20 pts)
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            # Use trajectory frames to verify the workflow (Settings -> Enable -> Create)
            frames = sample_trajectory_frames(traj, n=4)
            final_ss = get_final_screenshot(traj)
            
            prompt = """
            Analyze these screenshots of a user using accounting software (Manager.io).
            
            I am looking for two specific actions:
            1. Did the user go to a 'Settings' or 'Customize' screen to enable a module? (Look for checkboxes or a list of modules)
            2. Did the user fill out a 'Goods Receipt' form? (Look for fields like Supplier, Date, Reference)
            
            Also look at the FINAL screenshot:
            - Does it show a saved Goods Receipt view?
            - Can you see 'Exotic Liquids' or 'GR-2024-001'?
            
            Return JSON:
            {
                "settings_interaction": true/false,
                "form_filled": true/false,
                "final_result_visible": true/false,
                "confidence": "high/medium/low"
            }
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames + [final_ss])
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("settings_interaction"):
                    vlm_score += 5
                if parsed.get("form_filled"):
                    vlm_score += 5
                if parsed.get("final_result_visible"):
                    vlm_score += 10
                feedback.append(f"VLM verification score: {vlm_score}/20")
            else:
                feedback.append("VLM verification failed to run")
                # Fallback: grant partial points if programmatic passed
                if score >= 60:
                    vlm_score = 10 
                    feedback.append("Fallback VLM points (+10)")

        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback.append("VLM error (skipped)")
    
    score += vlm_score

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }