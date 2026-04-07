#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_rma(traj, env_info, task_info):
    """
    Verify the Create RMA task.
    
    Scoring Criteria:
    1. RMA Record Found & New (20 pts)
    2. Correct Business Partner (15 pts)
    3. References a Shipment (15 pts)
    4. Has Lines (Qty > 0) (15 pts)
    5. Description matches (10 pts)
    6. Draft Status (5 pts)
    7. VLM: Verified navigation to RMA window (20 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Database Records
    rma_found = result.get("rma_found", False)
    is_new = result.get("is_new_record", False)
    details = result.get("rma_details", {})
    
    if rma_found and is_new:
        score += 20
        feedback_parts.append("✅ New RMA record created.")
    elif rma_found:
        score += 10
        feedback_parts.append("⚠️ RMA found but count didn't increase (modified existing?).")
    else:
        feedback_parts.append("❌ No RMA record found.")
        return {"passed": False, "score": 0, "feedback": "No RMA record created."}

    # Check BP Name
    bp_name = details.get("bp_name", "")
    if "C&W Construction" in bp_name:
        score += 15
        feedback_parts.append("✅ Correct Business Partner.")
    else:
        feedback_parts.append(f"❌ Incorrect Business Partner: {bp_name}")

    # Check Shipment Reference
    shipment = details.get("shipment_ref", "")
    if shipment and shipment != "":
        score += 15
        feedback_parts.append(f"✅ Shipment referenced ({shipment}).")
    else:
        feedback_parts.append("❌ No original shipment referenced.")

    # Check Lines
    line_count = details.get("line_count", 0)
    if line_count > 0:
        score += 15
        feedback_parts.append(f"✅ RMA has {line_count} line(s).")
    else:
        feedback_parts.append("❌ RMA has no lines.")

    # Check Description
    desc = details.get("description", "").lower()
    if "defective" in desc or "return" in desc:
        score += 10
        feedback_parts.append("✅ Description contains key terms.")
    else:
        feedback_parts.append("⚠️ Description missing keywords (expected 'Defective' or 'Return').")

    # Check Status (Should be Draft/DR or In Progress/IP, not Completed/CO/CL necessarily, task asked for Draft)
    status = details.get("doc_status", "")
    if status in ["DR", "IP"]:
        score += 5
        feedback_parts.append("✅ Document in Draft status.")
    elif status in ["CO", "CL"]:
        # We don't penalize too heavily if they completed it, but instructions said 'Draft'
        feedback_parts.append("⚠️ Document was completed (instructions said Draft).")
    
    # 3. VLM Verification (Trajectory)
    # Check if they actually visited the RMA window
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        prompt = """
        Analyze these screenshots of a user interacting with iDempiere ERP.
        1. Do you see a window titled "Return Material" or "RMA" or "Customer Return"?
        2. Do you see a form where "Business Partner" is set to "C&W Construction"?
        3. Do you see a line item being added?
        
        Answer 'YES' if the user appears to be working on an RMA, otherwise 'NO'.
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_img], prompt=prompt)
            if vlm_response.get("success") and "YES" in vlm_response.get("result", "").upper():
                vlm_score = 20
                feedback_parts.append("✅ Visual verification passed.")
            else:
                feedback_parts.append("⚠️ Visual verification inconclusive.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            
    score += vlm_score

    # Final result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }