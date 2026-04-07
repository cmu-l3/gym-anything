#!/usr/bin/env python3
"""
Verifier for configure_product_substitute task in iDempiere.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_product_substitute(traj, env_info, task_info):
    """
    Verifies that the agent configured 'Hoe' as a substitute for 'Spade'.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # 1. Load result data from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Programmatic Criteria
    score = 0
    feedback = []
    
    # Criterion 1: Link Exists (40 pts)
    link_exists = result.get("link_exists", False)
    if link_exists:
        score += 40
        feedback.append("Success: Substitute link established between Spade and Hoe.")
    else:
        feedback.append("Fail: No substitute link found between Spade and Hoe.")

    # Criterion 2: Metadata Correctness (30 pts)
    record_name = result.get("record_name", "")
    record_desc = result.get("record_description", "")
    
    expected_name = task_info['metadata'].get("expected_name", "Alternative for Spring")
    expected_desc_part = task_info['metadata'].get("expected_description_part", "out of stock")

    if link_exists:
        # Check Name (15 pts)
        if expected_name.lower() in record_name.lower():
            score += 15
            feedback.append(f"Success: Record name matches '{expected_name}'.")
        else:
            feedback.append(f"Partial: Record name '{record_name}' does not match expected '{expected_name}'.")

        # Check Description (15 pts)
        if expected_desc_part.lower() in record_desc.lower():
            score += 15
            feedback.append(f"Success: Description contains '{expected_desc_part}'.")
        else:
            feedback.append(f"Partial: Description '{record_desc}' missing key phrase '{expected_desc_part}'.")

    # 3. VLM Verification (30 pts)
    # We want to see if the UI actually reflects the change, acting as a sanity check
    # against blind SQL insertion (though uncommon in this setup) and confirming UI navigation.
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of an iDempiere ERP session. "
            "The user should be on the 'Product' window, specifically the 'Substitute' tab. "
            "1. Is the 'Product' window visible? "
            "2. Is the 'Substitute' tab selected or visible? "
            "3. Do you see 'Hoe' or 'Spade' mentioned in the context of substitutes? "
            "Answer yes/no with reasoning."
        )
        
        try:
            vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
            # Simple heuristic parsing
            text = vlm_response.get('text', '').lower()
            if "yes" in text and ("substitute" in text or "product" in text):
                vlm_score = 30
                feedback.append("Success: VLM confirms visual presence of Substitute tab/Product window.")
            else:
                # Fallback if VLM is unsure but DB is correct
                if link_exists: 
                    vlm_score = 30 # Give benefit of doubt if DB is correct
                    feedback.append("Note: VLM uncertain, but database confirms success.")
                else:
                    feedback.append("Fail: VLM did not confirm UI navigation.")
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")
            if link_exists: vlm_score = 30 # Fallback
            
    score += vlm_score

    # Final tally
    passed = (score >= 60) and link_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }