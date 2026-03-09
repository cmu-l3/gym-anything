#!/usr/bin/env python3
"""
Verifier for measles_outbreak_alert_config task.

Scoring (100 points total):
1. User Group 'Emergency Response Team' created & contains admin (20 pts)
2. Validation Rule 'Measles Outbreak Threshold' created with correct logic (30 pts)
3. Validation Rule Group 'Epidemic Alerts' created & contains rule (20 pts)
4. Validation Notification created & linked correctly (30 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def verify_measles_alert_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/measles_alert_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        # --- 1. User Group Verification (20 pts) ---
        ug_data = result.get('user_groups_data', {}).get('userGroups', [])
        target_ug = None
        for ug in ug_data:
            if 'emergency' in ug.get('name', '').lower() and 'response' in ug.get('name', '').lower():
                target_ug = ug
                break
        
        if target_ug:
            score += 10
            feedback_parts.append("User Group created (+10)")
            # Check for admin user
            users = target_ug.get('users', [])
            has_admin = any(u.get('username') == 'admin' for u in users)
            if has_admin:
                score += 10
                feedback_parts.append("Admin added to group (+10)")
            else:
                feedback_parts.append("Admin user NOT found in group")
        else:
            feedback_parts.append("User Group 'Emergency Response Team' not found")

        # --- 2. Validation Rule Verification (30 pts) ---
        rule_data = result.get('validation_rules_data', {}).get('validationRules', [])
        target_rule = None
        for r in rule_data:
            if 'measles' in r.get('name', '').lower() and 'threshold' in r.get('name', '').lower():
                target_rule = r
                break
        
        if target_rule:
            score += 10
            feedback_parts.append("Validation Rule created (+10)")
            
            # Check Logic
            # DHIS2 Validation Rules define VALID data. 
            # To alert on > 5, valid is <= 5 (less_than_or_equal_to).
            # Alternatively, if they made a "Surveillance Rule" (older concept), it might be different, 
            # but usually in newer DHIS2 apps this distinction is handled by the rule type or operator.
            # We check if the constant '5' is involved and operator is reasonable.
            
            operator = target_rule.get('operator', '')
            left_side = target_rule.get('leftSide', {}).get('description', '') + target_rule.get('leftSide', {}).get('expression', '')
            right_side = target_rule.get('rightSide', {}).get('description', '') + target_rule.get('rightSide', {}).get('expression', '')
            
            has_measles = 'measles' in left_side.lower() or 'fClA' in left_side  # fClA is common UID prefix for measles
            has_five = '5' in right_side or '5' in left_side # 5 might be a constant ID or raw value
            
            # Flexible operator check: <= is standard for high alerts, but we accept others if the agent logic attempted it
            if has_measles and has_five:
                score += 10
                feedback_parts.append("Rule logic references Measles and 5 (+10)")
                if operator == 'less_than_or_equal_to':
                    score += 10
                    feedback_parts.append("Operator correct (<= 5) (+10)")
                else:
                    feedback_parts.append(f"Operator '{operator}' may be incorrect for high-value alert (expected <=)")
            else:
                feedback_parts.append("Rule logic missing Measles data element or threshold 5")
        else:
            feedback_parts.append("Validation Rule 'Measles Outbreak Threshold' not found")

        # --- 3. Rule Group Verification (20 pts) ---
        group_data = result.get('validation_rule_groups_data', {}).get('validationRuleGroups', [])
        target_group = None
        for g in group_data:
            if 'epidemic' in g.get('name', '').lower():
                target_group = g
                break
        
        if target_group:
            score += 10
            feedback_parts.append("Rule Group created (+10)")
            # Check if rule is in group
            rules_in_group = target_group.get('validationRules', [])
            if target_rule and any(r.get('id') == target_rule.get('id') for r in rules_in_group):
                score += 10
                feedback_parts.append("Rule added to Group (+10)")
            else:
                feedback_parts.append("Target Rule NOT found in Group")
        else:
            feedback_parts.append("Validation Rule Group 'Epidemic Alerts' not found")

        # --- 4. Notification Verification (30 pts) ---
        notif_data = result.get('notifications_data', {}).get('validationNotificationTemplates', [])
        target_notif = None
        for n in notif_data:
            if 'measles' in n.get('name', '').lower() and 'alert' in n.get('name', '').lower():
                target_notif = n
                break
        
        if target_notif:
            score += 15
            feedback_parts.append("Notification Template created (+15)")
            
            # Check Linkage to Rule Group
            linked_groups = target_notif.get('validationRuleGroups', [])
            linked_rules = target_notif.get('validationRules', []) # Sometimes direct linking allowed
            
            group_linked = target_group and any(g.get('id') == target_group.get('id') for g in linked_groups)
            rule_linked = target_rule and any(r.get('id') == target_rule.get('id') for r in linked_rules)
            
            # Check Recipient
            recipients = target_notif.get('recipientUserGroups', [])
            ug_linked = target_ug and any(u.get('id') == target_ug.get('id') for u in recipients)
            
            if (group_linked or rule_linked) and ug_linked:
                score += 15
                feedback_parts.append("Notification correctly linked to Source and Recipient (+15)")
            else:
                feedback_parts.append(f"Notification linkage issue: SourceLinked={group_linked or rule_linked}, RecipientLinked={ug_linked}")
        else:
            feedback_parts.append("Notification Template 'Measles Alert SMS' not found")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Verifier error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}