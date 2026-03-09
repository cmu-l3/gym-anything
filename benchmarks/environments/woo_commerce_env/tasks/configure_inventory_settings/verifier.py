#!/usr/bin/env python3
"""
Verifier for configure_inventory_settings task in WooCommerce.

Verification Strategy:
1. Programmatic: Check 9 specific settings in the database via exported JSON.
2. VLM: Analyze trajectory to confirm navigation to "Products > Inventory" and form interaction.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent configuring WooCommerce settings.

Look for the "Products > Inventory" settings screen.
Key indicators:
- Tabs visible: "General", "Products", "Shipping", etc.
- Sub-tabs under Products: "General", "Inventory", "Downloadable products".
- Fields visible: "Manage stock", "Hold stock (minutes)", "Notifications", "Notification recipient", "Low stock threshold".

Assess:
1. DID_NAVIGATE: Did the agent successfully navigate to the Inventory settings tab?
2. DID_INTERACT: Did the agent interact with the form fields (typing, clicking checkboxes)?
3. DID_SAVE: Did the agent click the "Save changes" button?

Respond in JSON:
{
    "did_navigate": true/false,
    "did_interact": true/false,
    "did_save": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_configure_inventory_settings(traj, env_info, task_info):
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON
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

    # 3. Define Scoring Criteria
    actual_settings = result.get("settings", {})
    target_settings = task_info.get("metadata", {}).get("target_settings", {})
    
    score = 0
    max_score = 100
    feedback = []
    
    # Programmatic Checks (80 points total)
    # Weights vary by complexity/likelihood of default value
    
    criteria = [
        ("woocommerce_manage_stock", "yes", 5, "Stock management enabled"),
        ("woocommerce_hold_stock_minutes", "45", 15, "Hold stock = 45 min"),
        ("woocommerce_notify_low_stock", "yes", 5, "Low stock notifications enabled"),
        ("woocommerce_notify_no_stock", "yes", 5, "Out of stock notifications enabled"),
        ("woocommerce_stock_email_recipient", "warehouse@example.com", 15, "Recipient = warehouse@example.com"),
        ("woocommerce_notify_low_stock_amount", "10", 10, "Low stock threshold = 10"),
        ("woocommerce_notify_no_stock_amount", "2", 10, "Out of stock threshold = 2"),
        ("woocommerce_hide_out_of_stock_items", "yes", 10, "Hide out of stock items"),
        ("woocommerce_stock_format", "low_amount", 5, "Stock display format")
    ]
    
    correct_count = 0
    
    for key, expected, points, desc in criteria:
        actual = actual_settings.get(key, "").strip()
        if actual == expected:
            score += points
            correct_count += 1
            feedback.append(f"[PASS] {desc}")
        else:
            feedback.append(f"[FAIL] {desc} (Expected: '{expected}', Got: '{actual}')")

    # 4. VLM Verification (20 points)
    # Check trajectory for correct navigation and interaction
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        # Sample frames from trajectory
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        try:
            vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("did_navigate"):
                    vlm_score += 10
                    feedback.append("[PASS] VLM confirmed navigation to Inventory settings")
                if parsed.get("did_interact") or parsed.get("did_save"):
                    vlm_score += 10
                    feedback.append("[PASS] VLM confirmed interaction/saving")
            else:
                feedback.append("[WARN] VLM query failed, awarding partial credit based on DB success")
                # Fallback: if DB checks passed > 50%, assume VLM would pass
                if score > 40:
                    vlm_score = 20
        except Exception as e:
            logger.error(f"VLM error: {e}")
            if score > 40: vlm_score = 20
            
    else:
        # No VLM available, re-weight programmatic score to 100? 
        # Or just award VLM points if programmatic score is high enough (evidence of work)
        if score >= 40:
            vlm_score = 20
            feedback.append("[NOTE] VLM skipped, points awarded based on result success")

    total_score = score + vlm_score
    
    # 5. Final Determination
    # Must get at least the critical changes right (email, hold stock, thresholds)
    critical_keys = [
        "woocommerce_hold_stock_minutes", 
        "woocommerce_stock_email_recipient", 
        "woocommerce_notify_low_stock_amount"
    ]
    critical_passed = all(actual_settings.get(k) == target_settings.get(k) for k in critical_keys)
    
    passed = (total_score >= 70) and critical_passed
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback)
    }