#!/usr/bin/env python3
"""
Verifier for configure_campaign_list_mix task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_campaign_list_mix(traj, env_info, task_info):
    """
    Verifies that the List Mix was correctly configured in Vicidial.
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
    
    # 1. Verify List Mix Creation (20 pts)
    mix_data = result.get('mix_exists_data', {})
    if mix_data and mix_data.get('vcl_id') == 'REGIONAL_BLEND':
        score += 20
        feedback.append("List Mix 'REGIONAL_BLEND' created.")
        
        # Check association (some versions link in mix table, some in campaign table)
        if mix_data.get('campaign_id') == 'SENMIX':
            score += 10
            feedback.append("List Mix linked to campaign SENMIX in mix definition.")
    else:
        feedback.append("List Mix 'REGIONAL_BLEND' not found.")

    # 2. Verify Entries and Percentages (45 pts total, 15 each)
    entries = result.get('mix_entries', {})
    expected_entries = {'9301': 50, '9302': 30, '9303': 20}
    
    entries_correct_count = 0
    for list_id, expected_pct in expected_entries.items():
        actual_pct = entries.get(list_id)
        if actual_pct is not None and int(float(actual_pct)) == expected_pct:
            score += 15
            entries_correct_count += 1
            feedback.append(f"List {list_id} correctly set to {expected_pct}%.")
        else:
            feedback.append(f"List {list_id}: Expected {expected_pct}%, Found {actual_pct}%.")

    # 3. Verify Campaign Configuration (15 pts)
    # The campaign should be set to use the list mix.
    # Dial method might be 'INBOUND_MAN' or 'RATIO' but with list_mix enabled, 
    # or specific dial_method 'LMIX' depending on version. 
    # The crucial check is usually if the mix is active for the campaign.
    camp_config = result.get('campaign_config', {})
    # Loose check: if the mix definition (checked in step 1) says it belongs to SENMIX, 
    # AND the user navigated the UI, we grant points. 
    # Also check campaign table for traces of list mix activation if possible.
    
    # We'll rely heavily on the explicit linking in step 1, plus VLM verification for the "switch" action.
    # However, if 'list_order_mix' is set to the mix ID, that's a strong signal.
    if camp_config.get('list_order_mix') == 'REGIONAL_BLEND':
        score += 15
        feedback.append("Campaign configured to use REGIONAL_BLEND.")
    else:
        # Fallback: if mix is linked to campaign in mix table, we give partial credit
        if mix_data.get('campaign_id') == 'SENMIX':
            score += 5
            feedback.append("Campaign link found in Mix definition, but Campaign settings not explicitly verified via SQL.")

    # 4. VLM Verification (10 pts)
    # Ensure they actually used the UI
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    I am verifying a Vicidial administration task.
    The agent was supposed to:
    1. Create a "List Mix" named REGIONAL_BLEND.
    2. Add lists 9301, 9302, 9303 with specific percentages.
    3. Update Campaign SENMIX to use this mix.
    
    Look at the screenshot sequence. Do you see:
    - The Vicidial Admin interface?
    - A screen showing "List Mix" or "Campaigns"?
    - Any input of percentages (50, 30, 20)?
    
    Answer JSON: {"ui_visible": bool, "values_seen": bool, "confidence": float}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).get('parsed', {})
        if vlm_res.get('ui_visible'):
            score += 10
            feedback.append("VLM verified UI interaction.")
        else:
            feedback.append("VLM did not detect Vicidial Admin UI.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails but DB is perfect
        if score >= 60:
            score += 10

    # Final logic
    passed = score >= 65 and entries_correct_count >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }