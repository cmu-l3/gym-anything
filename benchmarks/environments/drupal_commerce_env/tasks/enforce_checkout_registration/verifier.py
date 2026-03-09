#!/usr/bin/env python3
"""
Verifier for Enforce Checkout Registration task.

Checks the Drupal Configuration API export for 'commerce_checkout_flow.default'.

Criteria:
1. configuration.panes.login.allow_guest_checkout must be False (0)
2. configuration.panes.login.allow_registration must be True (1)
3. The login pane must be enabled (step is not '_disabled')
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_checkout_registration(traj, env_info, task_info):
    """
    Verify the checkout flow configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            config_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Check if we got a valid config object
    # Drush export of a config entity usually has keys like 'uuid', 'langcode', 'status', 'configuration'
    if 'configuration' not in config_data:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Invalid configuration data exported (missing 'configuration' key)"
        }
        
    panes = config_data.get('configuration', {}).get('panes', {})
    login_pane = panes.get('login', {})
    
    if not login_pane:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Login pane configuration missing entirely"
        }

    # CRITERION 1: Guest Checkout Disabled (50 pts)
    # Drupal config stores booleans often as integers 0/1 or actual booleans. Handle both.
    guest_val = login_pane.get('allow_guest_checkout')
    guest_disabled = False
    
    if guest_val is False or guest_val == 0 or str(guest_val).lower() == 'false':
        guest_disabled = True
    
    if guest_disabled:
        score += 50
        feedback_parts.append("Guest checkout disabled")
    else:
        feedback_parts.append(f"Guest checkout is still enabled (value: {guest_val})")
        
    # CRITERION 2: Registration Enabled (30 pts)
    reg_val = login_pane.get('allow_registration')
    reg_enabled = False
    
    if reg_val is True or reg_val == 1 or str(reg_val).lower() == 'true':
        reg_enabled = True
        
    if reg_enabled:
        score += 30
        feedback_parts.append("Registration enabled")
    else:
        feedback_parts.append(f"Registration is not enabled (value: {reg_val})")
        
    # CRITERION 3: Pane is active (20 pts)
    # The 'step' key in the pane config determines where it appears.
    # If step is '_disabled', the pane is hidden.
    pane_step = login_pane.get('step', '_disabled')
    
    if pane_step != '_disabled':
        score += 20
        feedback_parts.append(f"Login pane is active (step: {pane_step})")
    else:
        feedback_parts.append("Login pane is disabled/hidden")
        
    # Pass threshold
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }