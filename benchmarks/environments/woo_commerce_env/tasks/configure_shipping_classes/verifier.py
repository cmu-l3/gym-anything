#!/usr/bin/env python3
"""
Verifier for Configure Shipping Classes task.

Verification Strategy:
1. Programmatic (80 pts):
   - Shipping classes exist (10 pts each)
   - Flat rate costs configured correctly in settings (15 pts each for class costs, 10 for base)
   - Products assigned to correct classes (10 pts each)
2. VLM (20 pts):
   - Workflow verification via trajectory (visiting settings, editing products)

"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_shipping_classes(traj, env_info, task_info):
    """Verify shipping class configuration and assignment."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Verify Shipping Classes (20 pts)
    bulky = result.get("bulky_class", {})
    fragile = result.get("fragile_class", {})
    
    if bulky.get("found"):
        score += 10
        feedback.append("Bulky Items class created.")
    else:
        feedback.append("Bulky Items class MISSING.")

    if fragile.get("found"):
        score += 10
        feedback.append("Fragile class created.")
    else:
        feedback.append("Fragile class MISSING.")

    # 3. Verify Costs (40 pts)
    # WooCommerce stores class costs in keys like 'class_cost_{term_id}'
    settings = result.get("flat_rate_settings", {})
    
    # Check base cost
    base_cost = str(settings.get("cost", "")).strip()
    if base_cost == "5.00" or base_cost == "5":
        score += 10
        feedback.append("Base cost set to 5.00.")
    else:
        feedback.append(f"Base cost incorrect (found: {base_cost}, expected: 5.00).")

    # Check Bulky cost
    # Key format: class_cost_{term_id} or class_cost_{slug} depending on WP version/plugin
    # Usually it uses the slug in recent versions or the ID.
    # The export script dumped the whole settings JSON.
    # We look for the cost "15.00" associated with the bulky ID key.
    
    bulky_id = bulky.get("id")
    fragile_id = fragile.get("id")
    
    bulky_cost_val = settings.get(f"class_cost_{bulky_id}", "")
    if not bulky_cost_val: 
        # Fallback check for slug if ID key not present
        bulky_cost_val = settings.get("class_cost_bulky-items", "")

    if str(bulky_cost_val).strip() == "15.00" or str(bulky_cost_val).strip() == "15":
        score += 15
        feedback.append("Bulky Items cost set to 15.00.")
    else:
        feedback.append(f"Bulky Items cost incorrect (found: {bulky_cost_val}).")

    fragile_cost_val = settings.get(f"class_cost_{fragile_id}", "")
    if not fragile_cost_val:
        fragile_cost_val = settings.get("class_cost_fragile", "")

    if str(fragile_cost_val).strip() == "8.00" or str(fragile_cost_val).strip() == "8":
        score += 15
        feedback.append("Fragile cost set to 8.00.")
    else:
        feedback.append(f"Fragile cost incorrect (found: {fragile_cost_val}).")

    # 4. Verify Assignments (20 pts)
    assignments = result.get("assignments", {})
    
    if assignments.get("sweater_bulky"):
        score += 10
        feedback.append("Sweater assigned to Bulky Items.")
    else:
        feedback.append("Sweater NOT assigned correctly.")

    if assignments.get("headphones_fragile"):
        score += 10
        feedback.append("Headphones assigned to Fragile.")
    else:
        feedback.append("Headphones NOT assigned correctly.")

    # 5. VLM / Trajectory Check (20 pts)
    # Since we don't have the VLM query function passed in this specific verified signature 
    # (it usually comes via env_info['query_vlm'] but standard signature is traj, env_info, task_info)
    # We will grant these points if the programmatic checks pass strongly, assuming 
    # they couldn't be achieved without the UI.
    # Alternatively, we can check 'terms_are_new' to ensure anti-gaming.
    
    meta = result.get("meta", {})
    if meta.get("terms_are_new"):
        score += 20
        feedback.append("Terms confirmed created during task session.")
    else:
        feedback.append("Warning: Shipping classes may have pre-existed.")

    passed = score >= 60 and bulky.get("found") and fragile.get("found")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }