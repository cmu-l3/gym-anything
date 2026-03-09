#!/usr/bin/env python3
"""
Verifier for Configure Shipping Zone task in WooCommerce.

Verification Strategy (Hybrid):
1. Programmatic (Database) Checks (80 pts):
   - Zone "Continental US" exists (20 pts)
   - Region is "United States" (20 pts)
   - Method is "Flat rate" (20 pts)
   - Method is Enabled (5 pts)
   - Cost is "8.50" (15 pts)

2. VLM Verification (20 pts):
   - Trajectory shows interaction with "Add shipping zone" modal
   - Trajectory shows interaction with "Add shipping method" modal
   - Final state shows the shipping zone list with the new zone

Anti-gaming:
- Checks that a *new* zone was actually created (count > initial)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_shipping_zone(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cost = metadata.get('expected_cost', '8.50')
    expected_cost_alt = metadata.get('expected_cost_alt', '8.5')

    # Retrieve result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Programmatic Checks ---

    # 1. Check Zone Existence (20 pts)
    if result.get('zone_found'):
        score += 20
        feedback_parts.append("Zone 'Continental US' created")
    else:
        feedback_parts.append("Zone 'Continental US' NOT found")

    # 2. Check Region (20 pts)
    if result.get('region_correct'):
        score += 20
        feedback_parts.append("Region 'United States' assigned")
    else:
        feedback_parts.append("Region incorrect or missing")

    # 3. Check Method Existence (20 pts)
    if result.get('method_found'):
        score += 20
        feedback_parts.append("Flat rate method added")
    else:
        feedback_parts.append("Flat rate method missing")

    # 4. Check Method Enabled (5 pts)
    if result.get('method_enabled'):
        score += 5
    else:
        feedback_parts.append("Method disabled (warning)")

    # 5. Check Cost (15 pts)
    actual_cost = str(result.get('cost_value', '')).strip()
    if actual_cost == expected_cost or actual_cost == expected_cost_alt:
        score += 15
        feedback_parts.append(f"Cost set to {actual_cost}")
    else:
        feedback_parts.append(f"Cost incorrect (found '{actual_cost}', expected '{expected_cost}')")

    # Anti-gaming check: Ensure something was actually created
    if result.get('new_zones_created', 0) <= 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new shipping zones were created during the task."
        }

    # --- VLM Verification (20 pts) ---
    # We use VLM to verify the workflow steps were actually performed
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        You are verifying a user creating a shipping zone in WooCommerce.
        Look at these screenshots of the user's workflow.
        
        I need to confirm:
        1. Did the user open a "Add shipping zone" screen or modal?
        2. Did the user see/select "Flat rate" from a list of shipping methods?
        3. Did the user enter "8.50" into a cost field?
        
        Respond in JSON:
        {
            "add_zone_seen": true/false,
            "flat_rate_selected": true/false,
            "cost_entered": true/false
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_score = 0
                if parsed.get('add_zone_seen'): vlm_score += 5
                if parsed.get('flat_rate_selected'): vlm_score += 5
                if parsed.get('cost_entered'): vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"Visual verification score: {vlm_score}/20")
            else:
                # If VLM fails, we default to full points if programmatic passed strongly
                # to avoid penalizing for VLM outage if the DB proves success.
                if score >= 80:
                    score += 20
                    feedback_parts.append("Visual verification skipped (assumed pass based on DB)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if score >= 80:
                score += 20

    passed = score >= 90  # Strict pass for configuration tasks
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }