#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_status_categories(traj, env_info, task_info):
    """
    Verify creation of status categories and statuses in Vicidial.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cats = {c['id']: c for c in metadata.get('expected_categories', [])}
    expected_stats = {s['id']: s for s in metadata.get('expected_statuses', [])}

    # Load result
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
    
    # 1. Verify Categories (40 pts)
    # 10 pts for existence of all 4, 10 for names, 10 for flags, 10 for anti-gaming (implied by existence after clean)
    found_cats = {c['id']: c for c in result.get('categories', [])}
    
    cats_exist_score = 0
    cats_props_score = 0
    
    for cid, exp in expected_cats.items():
        if cid in found_cats:
            cats_exist_score += 5 # 5 pts per category existence (max 20)
            actual = found_cats[cid]
            props_ok = True
            
            if actual['name'] != exp['name']:
                feedback.append(f"Category {cid} name mismatch: '{actual['name']}' vs '{exp['name']}'")
                props_ok = False
            if actual['sale'] != exp['sale']:
                feedback.append(f"Category {cid} Sale flag wrong")
                props_ok = False
            if actual['dead'] != exp['dead']:
                feedback.append(f"Category {cid} Dead Lead flag wrong")
                props_ok = False
                
            if props_ok:
                cats_props_score += 5 # 5 pts per category correct props (max 20)
        else:
            feedback.append(f"Category {cid} missing")

    score += cats_exist_score + cats_props_score

    # 2. Verify Statuses (40 pts)
    found_stats = {s['id']: s for s in result.get('statuses', [])}
    
    stats_exist_score = 0
    stats_props_score = 0
    
    for sid, exp in expected_stats.items():
        if sid in found_stats:
            stats_exist_score += 4 # 4 pts per status existence (max 20)
            actual = found_stats[sid]
            props_ok = True
            
            if actual['name'] != exp['name']:
                feedback.append(f"Status {sid} name mismatch")
                props_ok = False
            if actual['category'] != exp['category']:
                feedback.append(f"Status {sid} linked to wrong category: {actual['category']}")
                props_ok = False
            if actual['human'] != exp['human']:
                feedback.append(f"Status {sid} Human Answered flag wrong")
                props_ok = False
            if actual['callback'] != exp['callback']:
                feedback.append(f"Status {sid} Scheduled Callback flag wrong")
                props_ok = False
                
            if props_ok:
                stats_props_score += 4 # 4 pts per status correct props (max 20)
        else:
            feedback.append(f"Status {sid} missing")
            
    score += stats_exist_score + stats_props_score

    # 3. VLM Verification (20 pts)
    # Ensure they actually used the interface
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "You are verifying a Vicidial administration task. "
        "The user should have navigated to the 'Admin' section, then 'Status Categories', "
        "and 'System Statuses' to add new records. "
        "Look at the sequence of images.\n"
        "1. Do you see the Vicidial Admin interface (gray/blue table look)?\n"
        "2. Do you see forms for 'ADD NEW STATUS CATEGORY' or 'ADD NEW SYSTEM STATUS'?\n"
        "3. Do you see lists of statuses or categories?\n"
        "Return JSON: {\"interface_used\": true, \"forms_seen\": true, \"confidence\": 0-1}"
    )
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('interface_used') and vlm_data.get('forms_seen'):
        score += 20
        feedback.append("VLM confirmed UI usage.")
    else:
        feedback.append("VLM could not confirm UI usage (forms not seen).")

    # Final Pass check
    passed = (score >= 70) and (len(found_cats) == 4) and (len(found_stats) == 5)
    
    if not passed and len(found_cats) == 4 and len(found_stats) == 5:
        feedback.append("All records exist but properties (flags/names) are incorrect.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }