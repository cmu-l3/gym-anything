#!/usr/bin/env python3
"""
Verifier for restructure_product_catalog_hierarchy task.

VERIFICATION STRATEGY:
1. DB Foreign Keys (Categories): Checks if the nested tree was correctly established in the DB.
2. DB Foreign Keys (Products): Checks if products point to the exact IDs of the new sub-categories.
3. VLM Trajectory (Anti-Gaming/Validation): Verifies visual interactions with the hierarchy tools.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    categories = result.get('categories', [])
    products = result.get('products', [])
    
    score = 0
    feedback_parts = []
    
    # Build dictionary mapping names to category objects
    # If duplicates exist, we take the one that actually has a parent (more likely to be correct)
    cat_map = {}
    for c in categories:
        name = c.get('name')
        if name not in cat_map:
            cat_map[name] = c
        elif c.get('parent_id'):
            cat_map[name] = c # Prefer the linked one if duplicates

    # --- HIERARCHY EVALUATION ---
    l1_id = None
    l2_sec_id = None
    l2_auto_id = None
    l3_cam_id = None
    l3_sen_id = None

    # L1: Smart Home Technologies (10 pts)
    if 'Smart Home Technologies' in cat_map:
        cat = cat_map['Smart Home Technologies']
        if not cat.get('parent_id'):
            score += 10
            l1_id = cat.get('id')
            feedback_parts.append("L1 'Smart Home Technologies' created")
        else:
            feedback_parts.append("L1 'Smart Home Technologies' exists but incorrectly has a parent")
    else:
        feedback_parts.append("L1 'Smart Home Technologies' missing")

    # L2: Security (10 pts)
    if 'Security' in cat_map:
        cat = cat_map['Security']
        l2_sec_id = cat.get('id')
        if l1_id and cat.get('parent_id') == l1_id:
            score += 10
            feedback_parts.append("L2 'Security' correctly linked to L1")
        else:
            feedback_parts.append("L2 'Security' exists but not linked to L1")
    else:
        feedback_parts.append("L2 'Security' missing")

    # L2: Automation (10 pts)
    if 'Automation' in cat_map:
        cat = cat_map['Automation']
        l2_auto_id = cat.get('id')
        if l1_id and cat.get('parent_id') == l1_id:
            score += 10
            feedback_parts.append("L2 'Automation' correctly linked to L1")
        else:
            feedback_parts.append("L2 'Automation' exists but not linked to L1")
    else:
        feedback_parts.append("L2 'Automation' missing")

    # L3: Cameras (10 pts)
    if 'Cameras' in cat_map:
        cat = cat_map['Cameras']
        l3_cam_id = cat.get('id')
        if l2_sec_id and cat.get('parent_id') == l2_sec_id:
            score += 10
            feedback_parts.append("L3 'Cameras' correctly linked to Security")
        else:
            feedback_parts.append("L3 'Cameras' exists but not linked to Security")
    else:
        feedback_parts.append("L3 'Cameras' missing")

    # L3: Sensors (10 pts)
    if 'Sensors' in cat_map:
        cat = cat_map['Sensors']
        l3_sen_id = cat.get('id')
        if l2_sec_id and cat.get('parent_id') == l2_sec_id:
            score += 10
            feedback_parts.append("L3 'Sensors' correctly linked to Security")
        else:
            feedback_parts.append("L3 'Sensors' exists but not linked to Security")
    else:
        feedback_parts.append("L3 'Sensors' missing")

    # --- PRODUCT ASSIGNMENT EVALUATION ---
    prod_map = {p.get('name'): p for p in products}

    # Product 1: WiFi Doorbell Camera 4K -> Cameras (15 pts)
    p1 = prod_map.get('WiFi Doorbell Camera 4K')
    if p1 and l3_cam_id and p1.get('category_id') == l3_cam_id:
        score += 15
        feedback_parts.append("Camera product assigned to Cameras")
    elif p1 and p1.get('category_id'):
        feedback_parts.append(f"Camera product assigned to wrong category ID: {p1.get('category_id')}")
    else:
        feedback_parts.append("Camera product unassigned")

    # Product 2: Motion Sensor Pro -> Sensors (15 pts)
    p2 = prod_map.get('Motion Sensor Pro')
    if p2 and l3_sen_id and p2.get('category_id') == l3_sen_id:
        score += 15
        feedback_parts.append("Sensor product assigned to Sensors")
    elif p2 and p2.get('category_id'):
        feedback_parts.append("Sensor product assigned to wrong category")
    else:
        feedback_parts.append("Sensor product unassigned")

    # Product 3: Smart Hub Controller -> Automation (20 pts)
    p3 = prod_map.get('Smart Hub Controller')
    if p3 and l2_auto_id and p3.get('category_id') == l2_auto_id:
        score += 20
        feedback_parts.append("Hub product assigned to Automation")
    elif p3 and p3.get('category_id'):
        feedback_parts.append("Hub product assigned to wrong category")
    else:
        feedback_parts.append("Hub product unassigned")

    # --- VLM TRAJECTORY CHECK (Anti-Gaming Check) ---
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        if all_frames:
            vlm_prompt = """
            You are verifying if a user successfully navigated a CRM interface.
            Look at these sequential screenshots from the session. 
            Did the user interact with BOTH the "Product Categories" module AND the "Products" module?
            Answer in JSON format: {"categories_module_seen": true/false, "products_module_seen": true/false}
            """
            vlm_res = query_vlm(images=all_frames, prompt=vlm_prompt)
            if vlm_res and vlm_res.get('parsed'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('categories_module_seen') and parsed.get('products_module_seen'):
                    feedback_parts.append("VLM verified correct module navigation.")
                else:
                    feedback_parts.append("VLM did not verify all module interactions.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }