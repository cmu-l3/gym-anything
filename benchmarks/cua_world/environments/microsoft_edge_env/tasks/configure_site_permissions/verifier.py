#!/usr/bin/env python3
"""
Verifier for configure_site_permissions task.

Verification Logic:
1. Validates that the agent created a report file after task start.
2. Validates that the report mentions the required domains.
3. Parses Edge's Preferences file to verify actual site permissions.
   - Notifications: youtube (Block), facebook (Block), teams (Allow)
   - Camera: zoom (Allow)
   - Location: maps.google (Allow)
   
Setting Values in Edge Preferences:
- 1 = Allow
- 2 = Block
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_site_permissions(traj, env_info, task_info):
    """
    Verifies site permissions and report creation.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_configs = metadata.get('expected_configs', [])
    
    # Copy result file
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
    feedback_parts = []
    
    # 2. Verify Report Creation (15 points total)
    report = result.get('report', {})
    report_content = report.get('content_preview', '').lower()
    
    if report.get('exists', False) and report.get('modified_after_start', False):
        score += 10
        feedback_parts.append("Report file created")
        
        # Check report content (5 points)
        # Check if it mentions at least 3 of the 5 domains
        mentioned_count = 0
        domains = ["youtube", "facebook", "teams", "zoom", "maps"]
        for d in domains:
            if d in report_content:
                mentioned_count += 1
        
        if mentioned_count >= 3:
            score += 5
            feedback_parts.append(f"Report mentions {mentioned_count}/5 domains")
        else:
            feedback_parts.append(f"Report content missing key domains (found {mentioned_count}/5)")
    else:
        feedback_parts.append("Report file missing or not updated")

    # 3. Verify Edge Preferences (85 points total)
    # 17 points per correct permission setting (5 settings * 17 = 85)
    
    edge_state = result.get('edge_state', {})
    content_settings = edge_state.get('content_settings', {})
    
    # Helper to check a setting
    def check_permission(perm_type, target_domain, expected_setting):
        settings_dict = content_settings.get(perm_type, {})
        
        # Edge stores keys like "https://www.youtube.com:443,*" or "[*.]youtube.com,*"
        # We need to find if any key contains our target domain and matches the setting
        for pattern, value_obj in settings_dict.items():
            if target_domain in pattern:
                # Found the domain entry
                actual_setting = value_obj.get('setting')
                if actual_setting == expected_setting:
                    return True, actual_setting
                return False, actual_setting
        return False, None

    # Check each expected config
    configs_passed = 0
    
    for config in expected_configs:
        domain = config['domain']
        p_type = config['type']
        exp_setting = config['setting'] # 1 or 2
        
        passed, actual = check_permission(p_type, domain, exp_setting)
        
        if passed:
            score += 17
            configs_passed += 1
            feedback_parts.append(f"Correct: {domain} ({config['setting_name']})")
        else:
            if actual is None:
                feedback_parts.append(f"Missing: {domain} in {p_type}")
            else:
                act_name = "Block" if actual == 2 else "Allow" if actual == 1 else str(actual)
                feedback_parts.append(f"Wrong: {domain} is {act_name}")

    # 4. Final Scoring
    # Pass threshold: Report exists (at least basic) + 3/5 permissions correct
    # Min score to pass: 10 (report) + 51 (3 * 17) = 61. Rounding up threshold to 65.
    
    passed = score >= 65
    
    # Verification of app state (Anti-gaming check)
    if not edge_state.get('preferences_found', False):
        score = 0
        passed = False
        feedback_parts.append("CRITICAL: Edge Preferences file not found.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }