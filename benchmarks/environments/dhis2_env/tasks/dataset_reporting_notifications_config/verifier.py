#!/usr/bin/env python3
"""
Verifier for dataset_reporting_notifications_config task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_dataset_notification_config(traj, env_info, task_info):
    """
    Verify the configuration of User Group, Dataset, and Notification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        # Copy result file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/notification_config_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

        score = 0
        feedback_parts = []
        details = result.get('details', {})

        # 1. User Group (15 pts)
        if result.get('user_group_found'):
            score += 10
            feedback_parts.append("User Group created (+10)")
            ug_det = details.get('user_group', {})
            if ug_det.get('has_admin'):
                score += 5
                feedback_parts.append("User Group has admin (+5)")
            else:
                feedback_parts.append("User Group missing admin member")
        else:
            feedback_parts.append("User Group 'Ebola Response Team' not found")

        # 2. Dataset Basic (20 pts)
        ds_found = result.get('dataset_found')
        if ds_found:
            score += 10
            feedback_parts.append("Dataset created (+10)")
            ds_det = details.get('dataset', {})
            if ds_det.get('periodType') == 'Monthly':
                score += 10
                feedback_parts.append("Correct Period Type (+10)")
            else:
                feedback_parts.append(f"Wrong Period Type: {ds_det.get('periodType')}")
        else:
            feedback_parts.append("Dataset 'Ebola Emergency Reporting' not found")

        # 3. Data Elements (15 pts)
        if ds_found:
            count = details.get('dataset', {}).get('element_count', 0)
            if count >= 2:
                score += 15
                feedback_parts.append(f"Has {count} Data Elements (+15)")
            else:
                feedback_parts.append(f"Insufficient Data Elements: {count} (need >= 2)")

        # 4. Org Units (15 pts)
        if ds_found:
            if details.get('dataset', {}).get('has_bo_org_unit'):
                score += 15
                feedback_parts.append("Assigned to Bo District (+15)")
            else:
                feedback_parts.append("Not assigned to Bo District")

        # 5. Notification Exists (20 pts)
        nt_found = result.get('notification_found')
        if nt_found:
            score += 20
            feedback_parts.append("Notification created (+20)")
        else:
            feedback_parts.append("No notification template found for dataset")

        # 6. Notification Config (15 pts)
        if nt_found:
            nt_det = details.get('notification', {})
            valid_trig = nt_det.get('trigger') == 'COMPLETE'
            valid_recip = 'Ebola Response Team' in nt_det.get('recipient', '')
            valid_vars = nt_det.get('template_has_vars', False)

            if valid_trig: score += 5
            else: feedback_parts.append(f"Wrong trigger: {nt_det.get('trigger')}")

            if valid_recip: score += 5
            else: feedback_parts.append(f"Wrong recipient: {nt_det.get('recipient')}")
            
            if valid_vars: score += 5
            else: feedback_parts.append("Message template missing variables")
        
        # Calculate final pass/fail
        # Requirement: Dataset + Notification MUST exist for meaningful pass
        passed = (score >= 65) and ds_found and nt_found

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier Error: {str(e)}"}