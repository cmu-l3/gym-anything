#!/usr/bin/env python3
"""
Verifier for advanced_correlation_rule_creation

Scoring (100 points total):
- Timeline file exists and was created after task start: 15 points
- Timeline contains correct attacker IP '203.0.113.42': 25 points
- Timeline mentions compromised account 'sysadmin' and escalation: 20 points
- Correlation rule created in ELA (new count > baseline): 25 points
- Privilege escalation alert profile created: 15 points

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_advanced_correlation_rule_creation(traj, env_info, task_info):
    """Verify multi-stage attack correlation rule creation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_ip = metadata.get('attacker_ip', '203.0.113.42')
    expected_user = metadata.get('compromised_account', 'sysadmin')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/advanced_correlation_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    task_start = result.get('task_start', 0)

    # --- Criterion 1: Timeline file exists and created after task start (15 pts) ---
    timeline_exists = result.get('timeline_exists', False)
    timeline_mtime = result.get('timeline_mtime', 0)
    timeline_size = result.get('timeline_size', 0)

    if timeline_exists and int(timeline_mtime) > int(task_start) and timeline_size > 50:
        score += 15
        subscores['timeline_created'] = True
        feedback_parts.append(f"Attack timeline created ({timeline_size} bytes)")
    elif timeline_exists and timeline_size > 50:
        score += 5
        subscores['timeline_created'] = False
        feedback_parts.append("Timeline exists but appears to be from a previous session")
    else:
        subscores['timeline_created'] = False
        feedback_parts.append("Attack timeline not found at ~/Desktop/attack_timeline.txt")

    # --- Criterion 2: Correct attacker IP identified (25 pts) ---
    if result.get('has_attacker_ip', False):
        score += 25
        subscores['correct_ip'] = True
        feedback_parts.append(f"Correct attacker IP '{expected_ip}' documented in timeline")
    else:
        subscores['correct_ip'] = False
        feedback_parts.append(f"Timeline does not identify '{expected_ip}' as the attacker IP")

    # --- Criterion 3: Compromised account and escalation documented (20 pts) ---
    has_sysadmin = result.get('has_sysadmin', False)
    has_escalation = result.get('has_escalation', False)

    if has_sysadmin and has_escalation:
        score += 20
        subscores['attack_chain'] = True
        feedback_parts.append(f"Attack chain documented: '{expected_user}' account and privilege escalation")
    elif has_sysadmin:
        score += 10
        subscores['attack_chain'] = False
        feedback_parts.append(f"'{expected_user}' mentioned but escalation stage not documented")
    elif has_escalation:
        score += 5
        subscores['attack_chain'] = False
        feedback_parts.append("Escalation mentioned but compromised account not identified")
    else:
        subscores['attack_chain'] = False
        feedback_parts.append("Timeline missing compromised account or privilege escalation details")

    # --- Criterion 4: Correlation rule created (25 pts) ---
    corr_rule_found = result.get('corr_rule_found', False)
    corr_created = result.get('corr_created', False)
    new_corr_count = result.get('new_corr_count', 0)

    if corr_rule_found:
        score += 25
        subscores['correlation_rule'] = True
        feedback_parts.append("Named correlation rule for multi-stage attack created")
    elif corr_created and new_corr_count > 0:
        score += 15
        subscores['correlation_rule'] = False
        feedback_parts.append(f"Correlation rule created ({new_corr_count} new) but not specifically named for brute-force-to-compromise")
    else:
        subscores['correlation_rule'] = False
        feedback_parts.append("No correlation rule found in ELA (navigate to Correlation section to create one)")

    # --- Criterion 5: Privilege escalation alert created (15 pts) ---
    priv_esc_found = result.get('priv_esc_alert_found', False)
    alert_created = result.get('alert_created', False)
    new_alert_count = result.get('new_alert_count', 0)

    if priv_esc_found:
        score += 15
        subscores['priv_esc_alert'] = True
        feedback_parts.append("Privilege escalation alert profile created")
    elif alert_created and new_alert_count > 0:
        score += 8
        subscores['priv_esc_alert'] = False
        feedback_parts.append(f"New alert created ({new_alert_count} new) but not named for privilege escalation")
    else:
        subscores['priv_esc_alert'] = False
        feedback_parts.append("No privilege escalation alert profile found")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "task_start": task_start,
            "timeline_mtime": timeline_mtime,
            "timeline_size": timeline_size,
            "new_corr": new_corr_count,
            "new_alerts": new_alert_count,
        }
    }
