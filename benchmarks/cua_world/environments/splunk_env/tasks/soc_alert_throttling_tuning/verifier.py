#!/usr/bin/env python3
"""Verifier for soc_alert_throttling_tuning task.

Evaluates the correct configuration of a stateful alert in Splunk,
specifically focusing on the suppression/throttling settings.

Scoring Breakdown (100 points total):
- Alert Creation (20 pts): Alert exists and was not pre-existing.
- Search Logic (15 pts): Queries web_logs and uses aggregation.
- Scheduled Execution (15 pts): Alert is scheduled with cron.
- Throttling Enabled (20 pts): alert.suppress is enabled.
- Throttling Period (15 pts): Period is configured to exactly 1 hour.
- Throttling by Entity (15 pts): Specific field(s) defined for suppression.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_truthy(val):
    """Handle Splunk API's mixed return types for booleans."""
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return val > 0
    if isinstance(val, str):
        return val.lower() in ['1', 'true', 't', 'yes', 'y']
    return False


def verify_soc_alert_throttling_tuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_index = metadata.get('expected_index', 'web_logs')
    valid_periods = metadata.get('suppression_period_options', ["1h", "60m", "3600s", "3600"])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    alert = result.get('alert_analysis', {})
    
    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Alert Exists (20 points)
    if alert.get('found', False) and not alert.get('was_preexisting', False):
        score += 20
        feedback_parts.append(f"Alert '{alert.get('name')}' created successfully.")
        subscores['alert_created'] = True
    elif alert.get('found', False):
        feedback_parts.append("FAIL: Alert existed before task started (gaming detected).")
        subscores['alert_created'] = False
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts), "subscores": subscores}
    else:
        feedback_parts.append("FAIL: Alert 'Web_Error_Spike' not found.")
        subscores['alert_created'] = False
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts), "subscores": subscores}

    search_text = alert.get('search', '').lower()

    # Criterion 2: Search Logic (15 points)
    has_index = expected_index in search_text
    has_aggregation = any(cmd in search_text for cmd in ['stats', 'count', 'chart', 'timechart', 'transaction'])
    
    if has_index and has_aggregation:
        score += 15
        feedback_parts.append(f"Search queries '{expected_index}' and aggregates data.")
        subscores['search_logic'] = True
    else:
        feedback_parts.append(f"FAIL: Search logic must query '{expected_index}' and use aggregation (e.g., stats).")
        subscores['search_logic'] = False

    # Criterion 3: Scheduled Execution (15 points)
    is_scheduled = is_truthy(alert.get('is_scheduled'))
    has_cron = bool(alert.get('cron_schedule', '').strip())
    
    if is_scheduled and has_cron:
        score += 15
        feedback_parts.append(f"Alert is scheduled ({alert.get('cron_schedule')}).")
        subscores['scheduled'] = True
    else:
        feedback_parts.append("FAIL: Alert is not scheduled or missing cron expression.")
        subscores['scheduled'] = False

    # Criterion 4: Throttling Enabled (20 points)
    is_suppressed = is_truthy(alert.get('suppress'))
    if is_suppressed:
        score += 20
        feedback_parts.append("Throttling (suppression) is enabled.")
        subscores['throttling_enabled'] = True
    else:
        feedback_parts.append("FAIL: Throttling is not enabled.")
        subscores['throttling_enabled'] = False

    # Criterion 5: Throttling Period (15 points)
    period = str(alert.get('suppress_period', '')).strip().lower()
    if period in valid_periods:
        score += 15
        feedback_parts.append(f"Throttling period correctly set to 1 hour ({period}).")
        subscores['throttling_period'] = True
    else:
        feedback_parts.append(f"FAIL: Throttling period must be 1 hour (got '{period}').")
        subscores['throttling_period'] = False

    # Criterion 6: Throttling by Entity (15 points)
    suppress_fields = alert.get('suppress_fields', '')
    if suppress_fields:
        # Check if the field is actually present in the search (anti-gaming/sanity check)
        # Handle cases where multiple fields might be specified (e.g., "clientip, status")
        fields = [f.strip().lower() for f in suppress_fields.split(',')]
        field_in_search = any(f in search_text for f in fields)
        
        if field_in_search:
            score += 15
            feedback_parts.append(f"Throttling restricted by entity field(s): {suppress_fields}.")
            subscores['throttling_entity'] = True
        else:
            # Partial credit if they filled it out but the search string doesn't overtly match the field name
            score += 10
            feedback_parts.append(f"Throttling restricted by field '{suppress_fields}', but field not explicitly seen in SPL.")
            subscores['throttling_entity'] = True
    else:
        feedback_parts.append("FAIL: Throttling must be restricted by a specific field (e.g., clientip), not globally.")
        subscores['throttling_entity'] = False

    # A passing score requires the core concepts: Alert exists, throttling enabled, and period correct.
    key_criteria_met = subscores.get('alert_created') and subscores.get('throttling_enabled') and subscores.get('throttling_period')
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "search_query": alert.get('search'),
            "cron_schedule": alert.get('cron_schedule'),
            "suppress_period": period,
            "suppress_fields": suppress_fields
        }
    }