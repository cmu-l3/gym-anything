#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_notifications(traj, env_info, task_info):
    """
    Verify that OrangeHRM email notifications were configured correctly.
    
    Expected:
    1. Email Config: SMTP, localhost, port 25, admin@gymhrcorp.com
    2. Subscriber 1: HR Leave Team -> leave@gymhrcorp.com (Leave Application)
    3. Subscriber 2: Recruitment Team -> jobs@gymhrcorp.com (Job Application)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract data
    config = result.get('config', {})
    subscribers = result.get('subscribers', [])
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criteria 1: Email Configuration (30 points)
    # ---------------------------------------------------------
    conf_score = 0
    
    # Check Sent As
    expected_sent_as = metadata.get('expected_sent_as', 'admin@gymhrcorp.com')
    actual_sent_as = config.get('sent_as', '')
    if actual_sent_as == expected_sent_as:
        conf_score += 10
        feedback_parts.append("✅ Sent-as address correct")
    else:
        feedback_parts.append(f"❌ Sent-as address incorrect (Expected: {expected_sent_as}, Found: {actual_sent_as})")

    # Check SMTP Host
    expected_host = metadata.get('expected_smtp_host', 'localhost')
    actual_host = config.get('smtp_host', '')
    if actual_host == expected_host:
        conf_score += 10
        feedback_parts.append("✅ SMTP host correct")
    else:
        feedback_parts.append(f"❌ SMTP host incorrect (Found: {actual_host})")

    # Check SMTP Port
    expected_port = metadata.get('expected_smtp_port', 25)
    actual_port = config.get('smtp_port', 0)
    try:
        if int(actual_port) == int(expected_port):
            conf_score += 10
            feedback_parts.append("✅ SMTP port correct")
        else:
            feedback_parts.append(f"❌ SMTP port incorrect (Found: {actual_port})")
    except ValueError:
        feedback_parts.append(f"❌ SMTP port invalid (Found: {actual_port})")
        
    score += conf_score

    # ---------------------------------------------------------
    # Criteria 2: Subscribers (70 points)
    # ---------------------------------------------------------
    expected_subs = metadata.get('subscribers', [])
    
    for expected in expected_subs:
        name_match = False
        email_match = False
        topic_match = False
        
        # Look for this subscriber in the actual list
        found_sub = None
        for actual in subscribers:
            # Check email match
            if actual.get('email', '').strip() == expected.get('email', '').strip():
                email_match = True
                
                # Check name match
                if actual.get('subscriber_name', '').strip() == expected.get('name', '').strip():
                    name_match = True
                
                # Check notification type match
                actual_notif = actual.get('notification_name', '')
                for keyword in expected.get('notification_keywords', []):
                    if keyword.lower() in actual_notif.lower():
                        topic_match = True
                        break
                
                found_sub = actual
                break
        
        # Scoring per subscriber
        sub_points = 0
        if email_match:
            sub_points += 15 # Email is the most critical ID
        if name_match:
            sub_points += 10
        if topic_match:
            sub_points += 10
            
        score += sub_points
        
        if email_match and topic_match:
            feedback_parts.append(f"✅ Subscriber '{expected['name']}' configured correctly")
        elif email_match:
            feedback_parts.append(f"⚠️ Subscriber '{expected['name']}' found but with wrong notification type or name")
        else:
            feedback_parts.append(f"❌ Subscriber '{expected['name']}' ({expected['email']}) NOT found")

    # ---------------------------------------------------------
    # VLM Trajectory Check (Tie-breaker / Confirmation)
    # ---------------------------------------------------------
    # If score is borderline (e.g. 60-70), VLM can confirm UI interaction
    # For now, we rely primarily on DB state as it's definitive.
    
    final_passed = score >= 70
    
    return {
        "passed": final_passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }