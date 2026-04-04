#!/usr/bin/env python3
"""
Verifier for tb_treatment_notification_config task.

Scoring (100 points total):
- At least 1 notification created (25 pts) [MANDATORY]
- Enrollment notification created (20 pts)
- Scheduled notification created (20 pts)
- Enrollment notification named correctly (10 pts)
- Scheduled notification named correctly (10 pts)
- Scheduled notification has days configured (10 pts)
- Linked to TB program (5 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_tb_notifications(traj, env_info, task_info):
    """Verify that TB program notifications were correctly configured."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/tb_notification_result.json", temp_path)
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
        notifications = result.get('notifications', [])
        count = result.get('count', 0)

        # Criterion 1: At least 1 notification created (MANDATORY)
        if count < 1:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new notification templates found. You must create notifications in the Maintenance app.",
                "details": {"count": 0}
            }
        
        score += 25
        feedback_parts.append(f"Created {count} new notification(s) (+25)")

        # Analyze created notifications
        has_enrollment = False
        has_scheduled = False
        enrollment_named_ok = False
        scheduled_named_ok = False
        scheduled_days_ok = False
        linked_to_tb = False

        for n in notifications:
            trigger = n.get('trigger', '')
            name = n.get('name', '').lower()
            prog = n.get('program_name', '').lower()
            days = n.get('days')

            # Check Program Link
            if 'tb' in prog or 'tuberculosis' in prog:
                linked_to_tb = True

            # Check Enrollment Type
            if trigger == 'ENROLLMENT':
                has_enrollment = True
                if 'enrollment' in name or 'alert' in name:
                    enrollment_named_ok = True
            
            # Check Scheduled Type
            # DHIS2 uses SCHEDULED_DAYS_DUE_DATE or similar variants
            if 'SCHEDULED' in trigger:
                has_scheduled = True
                if 'follow' in name or 'reminder' in name or 'overdue' in name:
                    scheduled_named_ok = True
                
                # Check days (should be > 0, task asks for 7)
                # Convert to int safely
                try:
                    d_int = int(days) if days is not None else 0
                    if d_int > 0:
                        scheduled_days_ok = True
                except:
                    pass

        # Score components
        if has_enrollment:
            score += 20
            feedback_parts.append("Enrollment trigger notification found (+20)")
        else:
            feedback_parts.append("Missing 'Enrollment' trigger notification")

        if has_scheduled:
            score += 20
            feedback_parts.append("Scheduled trigger notification found (+20)")
        else:
            feedback_parts.append("Missing 'Scheduled' trigger notification")

        if enrollment_named_ok:
            score += 10
            feedback_parts.append("Enrollment alert named correctly (+10)")
        
        if scheduled_named_ok:
            score += 10
            feedback_parts.append("Follow-up reminder named correctly (+10)")

        if scheduled_days_ok:
            score += 10
            feedback_parts.append("Scheduled days configured (>0) (+10)")

        if linked_to_tb:
            score += 5
            feedback_parts.append("Linked to TB programme (+5)")
        else:
            feedback_parts.append("Could not confirm link to a 'TB' named programme")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}