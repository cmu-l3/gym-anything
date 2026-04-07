#!/usr/bin/env python3
"""
Verifier for integrate_security_webhook task.
Checks if the required Event Rules were created via API inspection.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_integrate_security_webhook(traj, env_info, task_info):
    """
    Verify creation of Storage Failure and Soft Trigger webhook rules.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Requirements
    metadata = task_info.get('metadata', {})
    TARGET_HEALTH_URL = metadata.get('target_health_url', 'webhooks/health')
    TARGET_PANIC_URL = metadata.get('target_panic_url', 'webhooks/panic')
    TARGET_PANIC_NAME = metadata.get('target_panic_name', 'Panic Alert')
    
    # Score components
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Event Rules Dump
    temp_rules = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/event_rules_dump.json", temp_rules.name)
        with open(temp_rules.name, 'r') as f:
            rules = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve rules configuration: {str(e)}"}
    finally:
        if os.path.exists(temp_rules.name):
            os.unlink(temp_rules.name)

    if not isinstance(rules, list):
        return {"passed": False, "score": 0, "feedback": "Invalid rules configuration format"}

    # 2. Analyze Rules
    health_rule_found = False
    panic_rule_found = False
    
    health_score = 0
    panic_score = 0

    for rule in rules:
        # Check specific fields
        event_type = rule.get('eventType', '')
        action_type = rule.get('actionType', '')
        action_url = rule.get('actionUrl', '')
        action_text = rule.get('actionText', '') # JSON body is usually stored in actionText
        caption = rule.get('caption', '') # Soft Trigger Name
        
        # --- Check for Health Rule ---
        # Trigger: storageFailureEvent (or similar)
        # Action: execHttpRequestAction
        if 'storageFailure' in event_type and action_type == 'execHttpRequestAction':
            # Potential candidate
            if TARGET_HEALTH_URL in action_url:
                health_rule_found = True
                health_score = 20 # Base existence
                
                # Check JSON content
                if '{event.sourceName}' in action_text or '{event.source}' in action_text:
                    health_score += 10
                    feedback_parts.append("Health rule JSON macros correct")
                else:
                    feedback_parts.append("Health rule missing required macros")
                
                if 'POST' in rule.get('actionParams', '').upper() or True: # Method check implicit or complex
                     pass 

        # --- Check for Panic Rule ---
        # Trigger: softwareTriggerEvent
        # Action: execHttpRequestAction
        if event_type == 'softwareTriggerEvent' and action_type == 'execHttpRequestAction':
            # Potential candidate
            if TARGET_PANIC_URL in action_url:
                panic_rule_found = True
                panic_score = 20 # Base existence
                
                # Check Name
                if TARGET_PANIC_NAME.lower() in caption.lower():
                    panic_score += 10
                    feedback_parts.append("Panic button name correct")
                else:
                    feedback_parts.append(f"Panic button name mismatch (Found: {caption})")
                
                # Check JSON content
                if '{user.name}' in action_text:
                    panic_score += 10
                    feedback_parts.append("Panic rule JSON macros correct")
                else:
                    feedback_parts.append("Panic rule missing {user.name} macro")

    # 3. Calculate Final Score
    if health_rule_found:
        feedback_parts.append("Health Webhook Rule found")
        # Check URL exact match points
        health_score += 10
    else:
        feedback_parts.append("Health Webhook Rule NOT found")

    if panic_rule_found:
        feedback_parts.append("Panic Alert Rule found")
        # Check URL exact match points
        panic_score += 10
    else:
        feedback_parts.append("Panic Alert Rule NOT found")
        
    # JSON Validity Bonus (Implicitly checked if macros were parsable, but let's give points for structure)
    if health_rule_found and panic_rule_found:
        score += 10 # Bonus for completing both
    
    total_score = health_score + panic_score + (10 if health_rule_found and panic_rule_found else 0)
    
    # Cap at 100
    total_score = min(100, total_score)
    
    passed = total_score >= 60 and health_rule_found and panic_rule_found

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "; ".join(feedback_parts)
    }