#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import get_final_screenshot, query_vlm

def verify_add_documents_to_favorites(traj, env_info, task_info):
    """
    Verifies that the agent added specific documents to the Favorites collection.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    api_check = result_data.get("api_check", {})
    
    # Scoring
    score = 0
    feedback_items = []
    
    # Check Annual Report
    ar_status = api_check.get("annual_report", {})
    if ar_status.get("in_favorites"):
        score += 40
        feedback_items.append("Annual Report added to Favorites.")
    else:
        feedback_items.append(f"Annual Report NOT in Favorites (Found collections: {ar_status.get('collections')}).")

    # Check Contract Template
    ct_status = api_check.get("contract_template", {})
    if ct_status.get("in_favorites"):
        score += 40
        feedback_items.append("Contract Template added to Favorites.")
    else:
        feedback_items.append(f"Contract Template NOT in Favorites (Found collections: {ct_status.get('collections')}).")

    # VLM Verification (Bonus/Confirmation)
    # Check if a star icon is visible or "Favorites" text is prominent
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = "Does the screen show a 'Favorites' list with documents in it, or documents with a highlighted 'star' icon indicating they are favorites?"
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', '').lower().startswith('yes'):
                vlm_score = 20
                feedback_items.append("Visual confirmation of Favorites UI.")
        except:
            pass
    
    # If API check is perfect, give full points regardless of VLM (API is ground truth)
    if score == 80:
        score += 20
        feedback_items.append("Perfect execution verified via API.")
    else:
        score += vlm_score

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items)
    }