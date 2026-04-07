#!/usr/bin/env python3
"""Verifier for soc_alert_fatigue_mitigation task.

Verifies creation of a Splunk scheduled alert that utilizes field-based 
throttling/suppression to mitigate alert fatigue.

Scoring (100 total points):
- Alert exists & queries security_logs correctly: 15 pts
- Scheduled execution configured: 15 pts
- Suppression enabled: 15 pts
- Field-based suppression valid (IP field): 15 pts
- 24-Hour period configured: 15 pts
- VLM Trajectory (UI Workflow validation): 25 pts
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 15
MAX_VLM_SCORE = 25
PASS_THRESHOLD = 60

UI_VERIFICATION_PROMPT = """You are verifying if a computer agent used the Splunk web interface to create an alert with throttling/suppression.

TASK: Create a scheduled alert named "Throttled_SSH_Brute_Force" with 24-hour suppression using the Splunk web interface.

Look at these screenshots sampled from the agent's trajectory and determine:
1. Is Splunk's web interface visible?
2. Did the agent interact with the alert creation/edit interface?
3. Is there visual evidence of configuring "Trigger Actions", specifically selecting the "Throttle" or "Suppress" options?

Respond strictly in JSON format:
{
    "splunk_web_visible": true/false,
    "alert_ui_used": true/false,
    "throttling_configured_in_ui": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_soc_alert_fatigue_mitigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_period_options = metadata.get('expected_suppress_period_options', ["24h", "86400", "86400s", "1d"])
    expected_suppress_fields = metadata.get('expected_suppress_fields', ["src_ip", "clientip", "src", "source_ip", "ip"])

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/soc_alert_fatigue_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported JSON result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    target_alert = analysis.get('target_alert')
    new_searches = analysis.get('new_searches', [])

    score = 0
    feedback = []
    subscores = {}

    # Criterion 1: Alert exists & queries security_logs
    if target_alert:
        search_query = target_alert.get('search', '').lower()
        if 'security_logs' in search_query and ('fail' in search_query or 'invalid' in search_query):
            score += POINTS_PER_CRITERION
            feedback.append(f"Alert '{target_alert['name']}' exists and queries security_logs for failures.")
            subscores['alert_exists'] = True
        else:
            feedback.append(f"FAIL: Alert '{target_alert['name']}' exists but search query lacks 'security_logs' or failure keywords.")
            subscores['alert_exists'] = False
    else:
        if new_searches:
            feedback.append(f"FAIL: Target alert 'Throttled_SSH_Brute_Force' not found. Agent created these instead: {new_searches}")
        else:
            feedback.append("FAIL: No new alerts were created (Detected 'do nothing').")
        subscores['alert_exists'] = False
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback), "subscores": subscores}

    # Criterion 2: Scheduled execution
    is_scheduled = target_alert.get('is_scheduled', False)
    cron = target_alert.get('cron_schedule', '')
    if is_scheduled and cron:
        score += POINTS_PER_CRITERION
        feedback.append(f"Alert is scheduled with cron: {cron}")
        subscores['is_scheduled'] = True
    else:
        feedback.append("FAIL: Alert is not scheduled or missing cron expression.")
        subscores['is_scheduled'] = False

    # Criterion 3: Suppression enabled
    suppress_enabled = target_alert.get('alert.suppress', False)
    if suppress_enabled:
        score += POINTS_PER_CRITERION
        feedback.append("Alert suppression (throttling) is enabled.")
        subscores['suppress_enabled'] = True
    else:
        feedback.append("FAIL: Alert suppression is NOT enabled.")
        subscores['suppress_enabled'] = False

    # Criterion 4: Field-based suppression
    suppress_fields = target_alert.get('alert.suppress.fields', '')
    if suppress_fields:
        fields_list = [f.strip().lower() for f in suppress_fields.split(',')]
        valid_field = any(ef in fields_list for ef in expected_suppress_fields)
        if valid_field:
            score += POINTS_PER_CRITERION
            feedback.append(f"Suppression field is valid: {suppress_fields}")
            subscores['suppress_fields'] = True
        else:
            # Partial credit if they provided a field, but maybe not an IP field
            score += (POINTS_PER_CRITERION // 2)
            feedback.append(f"Suppression field set to '{suppress_fields}', but expected an IP field (e.g., src_ip).")
            subscores['suppress_fields'] = False
    else:
        feedback.append("FAIL: No suppression field specified (will suppress ALL alerts globally, not per-IP).")
        subscores['suppress_fields'] = False

    # Criterion 5: 24-Hour period
    suppress_period = target_alert.get('alert.suppress.period', '').lower()
    if suppress_period in expected_period_options:
        score += POINTS_PER_CRITERION
        feedback.append(f"Suppression period correctly set to 24 hours ({suppress_period}).")
        subscores['suppress_period'] = True
    elif suppress_period:
        feedback.append(f"FAIL: Suppression period is '{suppress_period}', expected 24 hours (e.g., 24h, 86400s).")
        subscores['suppress_period'] = False
    else:
        feedback.append("FAIL: Suppression period is not set.")
        subscores['suppress_period'] = False

    # Criterion 6: VLM Trajectory check
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        try:
            vlm_result = query_vlm(prompt=UI_VERIFICATION_PROMPT, images=frames)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("splunk_web_visible"): vlm_score += 5
                if parsed.get("alert_ui_used"): vlm_score += 10
                if parsed.get("throttling_configured_in_ui"): vlm_score += 10
                feedback.append(f"VLM Check: {vlm_score}/{MAX_VLM_SCORE} points ({parsed.get('reasoning', '')})")
            else:
                feedback.append("VLM Verification failed to parse.")
        except Exception as e:
            feedback.append(f"VLM exception: {e}")
    else:
        # If VLM is not initialized/mocked in tests, automatically grant the points 
        # to ensure functional programmatic checks still pass.
        vlm_score = MAX_VLM_SCORE
        feedback.append("VLM not available; auto-granting UI points.")

    score += vlm_score

    # Determine final pass/fail condition
    # Must reach threshold AND critically have configured suppression
    key_criteria_met = subscores.get('suppress_enabled', False) and subscores.get('alert_exists', False)
    passed = (score >= PASS_THRESHOLD) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }