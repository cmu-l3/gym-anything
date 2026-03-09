#!/usr/bin/env python3
"""
Verifier for set_out_of_office_delegate task.

Verification Logic:
1. API Check (Primary):
   - Retrieve User Profile JSON.
   - Check 'delegates' list.
   - Verify entry exists for 'sally-acm'.
   - Verify start date is today (approx) and end date is ~7 days in future.
   
2. VLM Check (Secondary):
   - Analyze screenshot to see if 'Delegates' tab is visible.
   - Confirm 'Sally Acm' is listed in the UI.
"""

import json
import tempfile
import os
import logging
import datetime
from dateutil import parser

# Import VLM utils from framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback/Mock for standalone testing
    def query_vlm(prompt, image): return {"success": False}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_out_of_office_delegate(traj, env_info, task_info):
    """
    Verify that the user configured the out-of-office delegation correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_username = metadata.get('target_delegate_username', 'sally-acm')
    target_name = metadata.get('target_delegate_name', 'Sally Acm')
    
    # ── Load Result JSON ─────────────────────────────────────────────────────
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
    
    # ── API Verification (80 Points) ─────────────────────────────────────────
    profile_data = result.get('profile_data', {})
    delegates = profile_data.get('delegates', [])
    
    # 1. Check if any delegate exists
    if delegates and len(delegates) > 0:
        score += 20
        feedback_parts.append("Delegation rule created")
        
        # Find the specific delegate
        found_delegate = None
        for d in delegates:
            # Check various fields where username might be stored
            d_user = d.get('delegateUser', {})
            d_username = d_user.get('username', '')
            d_email = d_user.get('email', '')
            
            if target_username in d_username or target_username in d_email or "sally" in str(d).lower():
                found_delegate = d
                break
        
        # 2. Check for correct user
        if found_delegate:
            score += 30
            feedback_parts.append(f"Correct delegate selected ({target_name})")
            
            # 3. Check dates
            start_str = found_delegate.get('startDate')
            end_str = found_delegate.get('endDate')
            
            if start_str and end_str:
                try:
                    # Parse dates (handling ISO formats often returned by APIs)
                    # Convert timestamps if necessary (ArkCase often uses epoch ms)
                    if isinstance(start_str, int): start_date = datetime.datetime.fromtimestamp(start_str/1000)
                    else: start_date = parser.parse(start_str)
                    
                    if isinstance(end_str, int): end_date = datetime.datetime.fromtimestamp(end_str/1000)
                    else: end_date = parser.parse(end_str)
                    
                    # Remove timezone for simple comparison
                    start_date = start_date.replace(tzinfo=None)
                    end_date = end_date.replace(tzinfo=None)
                    now = datetime.datetime.now().replace(tzinfo=None)
                    
                    # Check start date (should be close to today)
                    if abs((start_date - now).days) <= 1:
                        score += 15
                        feedback_parts.append("Start date is correct (Today)")
                    
                    # Check end date (should be future)
                    duration_days = (end_date - start_date).days
                    if 4 <= duration_days <= 10:
                        score += 15
                        feedback_parts.append(f"Duration is correct (~{duration_days} days)")
                    elif end_date > now:
                        score += 5
                        feedback_parts.append("End date is in the future")
                    else:
                        feedback_parts.append("End date is invalid (in the past)")
                        
                except Exception as e:
                    feedback_parts.append(f"Date parsing error: {e}")
        else:
            feedback_parts.append("Wrong delegate user selected")
    else:
        feedback_parts.append("No delegation rules found in profile")

    # ── VLM Verification (20 Points) ─────────────────────────────────────────
    # We use this as a fallback or boost if API worked partially, 
    # or to verify UI state even if API failed (partial credit for effort)
    
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        vlm_prompt = f"""
        Analyze this screenshot of the ArkCase interface.
        1. Is the user viewing the 'User Profile', 'Preferences', or 'Delegates' screen?
        2. Is 'Sally Acm' (or sally-acm) visible in a list?
        3. Are there dates visible indicating a scheduled duration?
        
        Respond JSON: {{ "is_delegates_screen": bool, "sally_visible": bool, "dates_visible": bool }}
        """
        
        vlm_res = query_vlm(image=final_screenshot, prompt=vlm_prompt)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('is_delegates_screen'):
                score += 10
                feedback_parts.append("VLM: Navigated to Delegates screen")
                
            if parsed.get('sally_visible') and parsed.get('dates_visible'):
                score += 10
                feedback_parts.append("VLM: Delegate details visible")
    
    # ── Final Assessment ─────────────────────────────────────────────────────
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }