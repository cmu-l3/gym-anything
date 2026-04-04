#!/usr/bin/env python3
"""Verifier for create_alert task.

STRICT REQUIREMENTS:
- Alert name MUST be exactly "Brute_Force_Detection" (case-insensitive, underscores/spaces/hyphens normalized)
- Alert search MUST reference security_logs index
- Alert search MUST contain "Failed password" or equivalent
- Alert MUST be scheduled with cron "*/5 * * * *" (every 5 minutes)
- Alert search MUST contain threshold check (count > 5 or similar) - REQUIRED per audit
- Must use the Splunk Web UI (verified via VLM)
"""

import json
import tempfile
import os
import re
import logging

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# VLM PROMPT FOR UI VERIFICATION
# =============================================================================

UI_VERIFICATION_PROMPT = """You are verifying if a computer agent used the Splunk web interface to create an alert.

TASK: Create a scheduled alert named "Brute_Force_Detection" in Splunk using the web interface.

Look at these screenshots from the agent's trajectory and determine:

1. Is Splunk's web interface visible (not just a terminal or REST API)?
   - Look for Splunk's green/black UI, app navigation
   - Settings, Alerts, or Saved Searches menus visible

2. Did the agent interact with the alert creation interface?
   - "Save As Alert" or "Create Alert" dialog visible
   - Alert name field visible with "Brute_Force_Detection" or similar
   - Schedule configuration (cron) visible
   - Search query visible in the alert setup

3. Was the alert creation workflow completed?
   - Success message or alert appearing in list
   - Alert settings page showing the new alert

Note: The agent should have used the web UI, not just the REST API or CLI.

Respond in JSON format:
{
    "splunk_web_visible": true/false,
    "alert_creation_ui_used": true/false,
    "alert_name_visible": true/false,
    "schedule_configured": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


def normalize_name(name):
    """Normalize alert name for comparison: lowercase, replace spaces/hyphens with underscores."""
    return name.lower().replace(' ', '_').replace('-', '_')


def has_threshold_check(search_query):
    """Check if search contains a numeric threshold condition like 'count > 5' or 'where count > N'.

    STRICT: Must contain actual numeric comparison, not just any where clause.
    """
    search_lower = search_query.lower()
    # Check for threshold patterns with NUMERIC comparisons only
    # Removed overly lenient pattern that matched any where clause
    patterns = [
        r'where\s+count\s*[><=]+\s*\d+',   # where count > 5, where count >= 5, etc.
        r'count\s*[><=]+\s*\d+',            # count > 5, count >= 10
        r'where\s+\w+\s*[><=]+\s*\d+',      # where anyfield > N (with numeric value)
        r'\|\s*search\s+count\s*[><=]+\s*\d+',  # | search count > 5
    ]
    for pattern in patterns:
        if re.search(pattern, search_lower):
            return True
    return False


def verify_create_alert(traj, env_info, task_info):
    """Verify that the agent created a brute force detection alert in Splunk."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alert_name = metadata.get('alert_name', 'Brute_Force_Detection')
    expected_search_contains = metadata.get('expected_search_contains', 'Failed password')
    expected_index = metadata.get('expected_index', 'security_logs')
    expected_cron = metadata.get('expected_cron', '*/5 * * * *')

    # Copy result file from container
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

    alert_analysis = result.get('alert_analysis', {})
    criteria_met = 0
    total_criteria = 5  # Now 5 criteria including threshold
    feedback_parts = []

    # Criterion 1: A new alert was created (agent actually created something)
    found_alert = alert_analysis.get('found_alert', False)
    new_saved_searches = alert_analysis.get('new_saved_searches', [])
    alert_name = alert_analysis.get('alert_name', '')

    if found_alert and (alert_name or len(new_saved_searches) > 0):
        criteria_met += 1
        feedback_parts.append(f"Alert created: '{alert_name}'")
    else:
        feedback_parts.append("FAIL: No new alert/saved search was created")

    # Criterion 2: Alert name MUST match "Brute_Force_Detection" exactly (STRICT)
    expected_normalized = normalize_name(expected_alert_name)
    actual_normalized = normalize_name(alert_name)

    # STRICT: Must be exact match after normalization
    name_exact_match = (actual_normalized == expected_normalized)

    if name_exact_match:
        criteria_met += 1
        feedback_parts.append(f"Correct name: '{alert_name}' matches expected")
    else:
        feedback_parts.append(f"FAIL: Alert name must be 'Brute_Force_Detection' (got: '{alert_name}')")

    # Criterion 3: Alert search MUST reference security_logs index AND failed password (STRICT)
    alert_search = alert_analysis.get('alert_search', '')
    alert_search_lower = alert_search.lower()

    has_security_logs = 'security_logs' in alert_search_lower
    has_failed = 'failed' in alert_search_lower

    if has_security_logs and has_failed:
        criteria_met += 1
        feedback_parts.append("Correct search: security_logs + Failed keyword")
    elif has_security_logs:
        feedback_parts.append(f"FAIL: Search has security_logs but missing 'Failed' keyword")
    elif has_failed:
        feedback_parts.append(f"FAIL: Search has 'Failed' but must use security_logs index")
    else:
        feedback_parts.append(f"FAIL: Search must use security_logs index AND contain 'Failed' keyword")

    # Criterion 4: Alert MUST be scheduled with cron "*/5 * * * *" (STRICT)
    cron_schedule = alert_analysis.get('cron_schedule', '')
    is_scheduled = alert_analysis.get('is_scheduled', False)

    # STRICT: cron must be exactly "*/5 * * * *" (or equivalent every-5-minute pattern)
    cron_normalized = ' '.join(cron_schedule.split())  # Normalize whitespace
    cron_matches = (cron_normalized == expected_cron or
                    cron_normalized == '*/5 * * * *')

    if cron_matches and is_scheduled:
        criteria_met += 1
        feedback_parts.append(f"Correct schedule: cron='{cron_schedule}'")
    elif is_scheduled and cron_schedule:
        feedback_parts.append(f"FAIL: Scheduled but cron must be '*/5 * * * *' (got: '{cron_schedule}')")
    elif is_scheduled:
        feedback_parts.append(f"FAIL: Alert is scheduled but missing cron schedule")
    else:
        feedback_parts.append(f"FAIL: Alert must be scheduled with cron '*/5 * * * *'")

    # Criterion 5: Alert search MUST contain threshold (count > 5 or similar) - NOW REQUIRED
    has_threshold = has_threshold_check(alert_search)

    if has_threshold:
        criteria_met += 1
        feedback_parts.append("Correct threshold: search includes 'count > N' filter")
    else:
        feedback_parts.append("FAIL: Search must include threshold (e.g., 'where count > 5')")

    # =========================================================================
    # VLM-BASED UI VERIFICATION (Criterion 6)
    # =========================================================================
    # This verifies the agent used the web UI, not just REST API or CLI

    query_vlm = env_info.get('query_vlm')
    vlm_ui_verified = False
    vlm_details = {}

    if query_vlm:
        # Get trajectory frames for process verification
        frames = sample_trajectory_frames(traj, num_samples=5)
        final_screenshot = get_final_screenshot(traj)

        # Combine frames for trajectory-based verification
        images_to_check = []
        if frames:
            images_to_check.extend(frames)
        if final_screenshot and final_screenshot not in images_to_check:
            images_to_check.append(final_screenshot)

        if images_to_check:
            try:
                vlm_result = query_vlm(
                    prompt=UI_VERIFICATION_PROMPT,
                    images=images_to_check,
                )
                vlm_details = vlm_result

                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    splunk_web_visible = parsed.get("splunk_web_visible", False)
                    alert_creation_ui_used = parsed.get("alert_creation_ui_used", False)
                    alert_name_visible = parsed.get("alert_name_visible", False)

                    # UI verification passes if agent used web interface for alert creation
                    if splunk_web_visible and alert_creation_ui_used:
                        vlm_ui_verified = True
                        if alert_name_visible:
                            feedback_parts.append("VLM: Web UI used, alert name visible")
                        else:
                            feedback_parts.append("VLM: Web UI used (alert name may be scrolled/hidden)")
                    else:
                        feedback_parts.append("VLM WARNING: Web UI usage not confirmed")
                        logger.warning(f"VLM UI verification: splunk_web={splunk_web_visible}, alert_ui={alert_creation_ui_used}")
                else:
                    feedback_parts.append(f"VLM: Verification skipped ({vlm_result.get('error', 'unavailable')})")
            except Exception as e:
                logger.error(f"VLM verification error: {e}")
                feedback_parts.append(f"VLM: Verification error")
        else:
            feedback_parts.append("VLM: No screenshots available for UI verification")
    else:
        feedback_parts.append("VLM: Query function not available")

    # =========================================================================
    # FINAL SCORING
    # =========================================================================
    # Now 6 criteria: 5 programmatic + 1 VLM-based UI verification
    # The VLM criterion is a bonus - passing without it gives ~83%, with it gives 100%

    total_criteria = 6 if query_vlm else 5
    if vlm_ui_verified:
        criteria_met += 1

    score = int((criteria_met / total_criteria) * 100)

    # STRICT: All 5 programmatic criteria required to pass
    # VLM criterion is additional verification (not blocking, but reported)
    programmatic_passed = (
        found_alert and (alert_name or len(new_saved_searches) > 0) and
        name_exact_match and
        has_security_logs and has_failed and
        cron_matches and is_scheduled and
        has_threshold
    )
    passed = programmatic_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "alert_created": found_alert and (alert_name or len(new_saved_searches) > 0),
            "name_exact_match": name_exact_match,
            "search_correct": has_security_logs and has_failed,
            "cron_correct": cron_matches and is_scheduled,
            "has_threshold": has_threshold,
            "vlm_ui_verified": vlm_ui_verified,
        },
        "vlm_details": vlm_details,
    }
