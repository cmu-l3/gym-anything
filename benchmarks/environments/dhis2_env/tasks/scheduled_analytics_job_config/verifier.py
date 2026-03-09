#!/usr/bin/env python3
"""
Verifier for scheduled_analytics_job_config task.

Scoring (100 points total):
- Analytics job exists (MANDATORY) (25 pts)
- Analytics job has correct type (ANALYTICS_TABLE) (10 pts)
- Analytics job has correct cron (Daily ~2AM) (10 pts)
- Analytics job enabled (5 pts)
- Resource job exists (25 pts)
- Resource job has correct type (RESOURCE_TABLE) (10 pts)
- Resource job has correct cron (Weekly ~Sun 3AM) (10 pts)
- Resource job enabled (5 pts)

Pass threshold: 60 points
Mandatory: Analytics job must exist
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def parse_cron(expression):
    """
    Parse a cron string into components.
    DHIS2/Spring Cron: second, minute, hour, day of month, month, day of week
    Example: 0 0 2 * * ? (Daily 2 AM)
    """
    if not expression:
        return None
    parts = expression.strip().split()
    if len(parts) < 6:
        return None
    return {
        'sec': parts[0],
        'min': parts[1],
        'hour': parts[2],
        'dom': parts[3],
        'month': parts[4],
        'dow': parts[5]
    }

def verify_scheduled_analytics_job_config(traj, env_info, task_info):
    """Verify scheduled jobs creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/scheduled_job_config_result.json", temp_path)
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
        
        parsed_jobs = result.get('parsed_jobs', {})
        if not parsed_jobs or 'error' in parsed_jobs:
             return {"passed": False, "score": 0, "feedback": f"Error in job verification data: {parsed_jobs.get('error', 'Unknown')}"}

        analytics_job = parsed_jobs.get('analytics_job')
        resource_job = parsed_jobs.get('resource_job')
        
        # --- Analytics Job Verification ---
        if analytics_job:
            score += 25
            feedback_parts.append("Analytics job created (+25)")
            
            # Check type
            if analytics_job.get('jobType') == 'ANALYTICS_TABLE':
                score += 10
                feedback_parts.append("Correct type (+10)")
            else:
                feedback_parts.append(f"Wrong type: {analytics_job.get('jobType')}")
                
            # Check Enabled
            if analytics_job.get('enabled') is True:
                score += 5
                feedback_parts.append("Enabled (+5)")
            else:
                feedback_parts.append("Analytics job disabled")

            # Check Cron (Target: Daily 2 AM -> 0 0 2 * * ?)
            cron_parts = parse_cron(analytics_job.get('cronExpression', ''))
            if cron_parts:
                # Accept 2 AM
                if cron_parts['hour'] == '2' and cron_parts['min'] == '0':
                    # Check frequency (daily means all days or ? for dow)
                    # Common daily patterns: "* * ?" or "* * *" or "? * *"
                    if (cron_parts['dom'] in ['*', '?'] and cron_parts['dow'] in ['*', '?']):
                         score += 10
                         feedback_parts.append("Correct daily 2AM schedule (+10)")
                    else:
                         score += 5 # Partial credit for correct time but maybe odd frequency
                         feedback_parts.append("Correct time, verify frequency (+5)")
                else:
                    feedback_parts.append(f"Wrong time: {cron_parts['hour']}:{cron_parts['min']}")
            else:
                feedback_parts.append("Invalid cron expression")
        else:
            feedback_parts.append("Analytics job NOT found (Mandatory)")
            # Mandatory failure condition logic applied at end

        # --- Resource Job Verification ---
        if resource_job:
            score += 25
            feedback_parts.append("Resource job created (+25)")
            
            # Check type
            if resource_job.get('jobType') == 'RESOURCE_TABLE':
                score += 10
                feedback_parts.append("Correct type (+10)")
            else:
                feedback_parts.append(f"Wrong type: {resource_job.get('jobType')}")

            # Check Enabled
            if resource_job.get('enabled') is True:
                score += 5
                feedback_parts.append("Enabled (+5)")
            else:
                feedback_parts.append("Resource job disabled")

            # Check Cron (Target: Sunday 3 AM -> 0 0 3 ? * SUN or similar)
            cron_parts = parse_cron(resource_job.get('cronExpression', ''))
            if cron_parts:
                if cron_parts['hour'] == '3' and cron_parts['min'] == '0':
                    # Check frequency (Sunday)
                    # 0 or 7 or SUN usually
                    dow = cron_parts['dow'].upper()
                    if 'SUN' in dow or '0' in dow or '7' in dow:
                         score += 10
                         feedback_parts.append("Correct Sunday 3AM schedule (+10)")
                    else:
                         feedback_parts.append(f"Correct time, wrong day ({dow})")
                else:
                    feedback_parts.append(f"Wrong time: {cron_parts['hour']}:{cron_parts['min']}")
        else:
            feedback_parts.append("Resource job NOT found")

        # Mandatory Check
        passed = (score >= 60) and (analytics_job is not None)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}