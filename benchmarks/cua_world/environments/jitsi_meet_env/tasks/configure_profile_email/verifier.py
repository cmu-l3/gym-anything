#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_configure_profile_email(traj, env_info, task_info):
    """
    Verifies that the Jitsi profile email was configured correctly.
    
    Strategy:
    1. Disk Check: Checks if the email string exists in Firefox profile files (persistence).
    2. VLM Check: Analyzes the final screenshot to see if the Profile Settings tab is open 
       and displays the correct email.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metadata
    expected_email = task_info.get('metadata', {}).get('expected_email', 'alex.manager@corp.global')
    
    # 2. Evaluation Criteria
    score = 0
    feedback = []
    
    # Criterion A: Application Running (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback.append("Firefox is running.")
    else:
        feedback.append("Firefox is NOT running.")

    # Criterion B: Data Persistence (40 pts)
    # The export script grepped the profile directory for the email string.
    if result.get('email_found_on_disk', False):
        score += 40
        feedback.append("Email successfully saved to browser storage.")
    else:
        feedback.append("Email NOT found in browser storage.")

    # Criterion C: Visual Verification (50 pts)
    # We check the final screenshot to see if the user left the Settings > Profile tab open as requested
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_img = get_final_screenshot(traj)
    vlm_passed = False
    
    if final_img:
        prompt = f"""
        You are verifying a Jitsi Meet task. 
        Goal: The user should have the 'Settings' dialog open, specifically the 'Profile' tab.
        Check for:
        1. A settings/profile dialog box is visible.
        2. The 'Profile' tab or section is selected.
        3. The E-mail field is visible.
        4. The E-mail field contains exactly: '{expected_email}'
        
        Answer JSON:
        {{
            "settings_open": true/false,
            "profile_tab_selected": true/false,
            "email_field_visible": true/false,
            "email_matches": true/false,
            "current_email_value": "string or null"
        }}
        """
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=final_img)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('settings_open'):
                score += 10
                feedback.append("Settings dialog is open.")
                
                if parsed.get('profile_tab_selected'):
                    score += 10
                    feedback.append("Profile tab is selected.")
                    
                    if parsed.get('email_matches'):
                        score += 30
                        vlm_passed = True
                        feedback.append(f"Visual check confirmed email: {expected_email}")
                    else:
                        seen = parsed.get('current_email_value', 'unknown')
                        feedback.append(f"Visual check failed. Saw: '{seen}' vs Expected: '{expected_email}'")
                else:
                    feedback.append("Profile tab not selected.")
            else:
                feedback.append("Settings dialog not visible in final screenshot.")
                
        except Exception as e:
            feedback.append(f"VLM analysis failed: {str(e)}")
    else:
        feedback.append("No final screenshot available for analysis.")

    # 3. Final Scoring
    # Pass if Disk Check passes OR Visual Check passes (robustness)
    # Ideally both, but sometimes disk sync lags or VLM misses.
    # We require at least 60 points.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }