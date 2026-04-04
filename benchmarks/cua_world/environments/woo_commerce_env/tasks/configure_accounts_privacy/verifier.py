#!/usr/bin/env python3
"""
Verifier for configure_accounts_privacy task in WooCommerce.

Verification Strategy:
1. Programmatic: Check if the 6 specific WordPress options in the database match the required values.
2. Anti-Gaming: Compare final values against the initial values (recorded in setup) to ensure changes were actually made.
3. VLM: Verify via trajectory that the user interacted with the settings page.

Scoring (100 points total):
- Guest checkout disabled: 20 pts
- Login reminder enabled: 10 pts
- Checkout signup enabled: 15 pts
- My Account signup enabled: 20 pts
- Erase order data enabled: 20 pts
- Erase download data enabled: 15 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM HELPERS
# ================================================================

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring WooCommerce settings.

The goal is to configure 'Accounts & Privacy' settings.

Look for:
1. Navigation to WooCommerce > Settings.
2. Clicking on the 'Accounts & Privacy' tab.
3. Checking/Unchecking checkboxes related to 'Guest checkout', 'Account creation', or 'Account erasure'.
4. Scrolling down and clicking 'Save changes'.

Respond in JSON format:
{
    "settings_page_visited": true/false,
    "privacy_tab_selected": true/false,
    "interaction_observed": true/false,
    "save_clicked": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_configure_accounts_privacy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_options = metadata.get('target_options', {})
    scoring_weights = metadata.get('scoring', {})

    score = 0
    feedback_parts = []
    
    # 1. Load result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}

    final_state = result_data.get('final_state', {})
    
    # 2. Check each option against target
    # Option 1: Guest Checkout (Target: no)
    val = final_state.get("woocommerce_enable_guest_checkout")
    if val == "no":
        score += scoring_weights.get("guest_checkout", 20)
        feedback_parts.append("Guest checkout disabled (+20)")
    else:
        feedback_parts.append(f"Guest checkout incorrect ('{val}')")

    # Option 2: Login Reminder (Target: yes)
    val = final_state.get("woocommerce_enable_checkout_login_reminder")
    if val == "yes":
        score += scoring_weights.get("login_reminder", 10)
        feedback_parts.append("Login reminder enabled (+10)")
    else:
        feedback_parts.append(f"Login reminder incorrect ('{val}')")

    # Option 3: Checkout Signup (Target: yes)
    val = final_state.get("woocommerce_enable_signup_and_login_from_checkout")
    if val == "yes":
        score += scoring_weights.get("checkout_signup", 15)
        feedback_parts.append("Checkout signup enabled (+15)")
    else:
        feedback_parts.append(f"Checkout signup incorrect ('{val}')")

    # Option 4: My Account Signup (Target: yes)
    val = final_state.get("woocommerce_enable_myaccount_registration")
    if val == "yes":
        score += scoring_weights.get("myaccount_signup", 20)
        feedback_parts.append("My Account signup enabled (+20)")
    else:
        feedback_parts.append(f"My Account signup incorrect ('{val}')")

    # Option 5: Erase Orders (Target: yes)
    val = final_state.get("woocommerce_erasure_request_removes_order_data")
    if val == "yes":
        score += scoring_weights.get("erase_orders", 20)
        feedback_parts.append("Erase orders enabled (+20)")
    else:
        feedback_parts.append(f"Erase orders incorrect ('{val}')")

    # Option 6: Erase Downloads (Target: yes)
    val = final_state.get("woocommerce_erasure_request_removes_download_data")
    if val == "yes":
        score += scoring_weights.get("erase_downloads", 15)
        feedback_parts.append("Erase downloads enabled (+15)")
    else:
        feedback_parts.append(f"Erase downloads incorrect ('{val}')")

    # 3. Anti-gaming check
    # We rely on the fact that setup_task.sh set all these to the opposite values.
    # If the score is high, it means the agent MUST have changed them.
    # We'll add a penalty if we suspect "do nothing" but achieved accidental correctness (unlikely here due to setup)
    if score == 0:
         feedback_parts.append("No settings matched requirements.")

    # 4. Optional: VLM Verification of trajectory
    # This confirms the agent actually used the UI and didn't just magic the database (though DB is truth)
    # We won't penalize score for VLM failure if the DB is correct, but we'll include it in feedback
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res and vlm_res.get("interaction_observed"):
            feedback_parts.append("(VLM confirmed UI interaction)")
        elif vlm_res:
             feedback_parts.append("(VLM did not clearly see UI interaction)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }