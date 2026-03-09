#!/usr/bin/env python3
"""Verifier for add_data_source task.

STRICT REQUIREMENTS:
- Monitor path MUST be exactly "/var/log/kern.log"
- Monitor MUST be configured to use "system_logs" index (not "main")
- Monitor must be detected via REST API (not just config file grep)
- Monitor must be newly created (not pre-existing)
- Must use the Splunk Web UI (verified via VLM)
"""

import json
import tempfile
import os
import logging

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# VLM PROMPT FOR UI VERIFICATION
# =============================================================================

UI_VERIFICATION_PROMPT = """You are verifying if a computer agent used the Splunk web interface to add a data source.

TASK: Add a new data source (file monitor) for /var/log/kern.log in Splunk using the web interface.

Look at these screenshots from the agent's trajectory and determine:

1. Is Splunk's web interface visible (not just a terminal or REST API)?
   - Look for Splunk's green/black UI, app navigation
   - Settings or Data Inputs menus visible

2. Did the agent interact with the data input/monitor configuration interface?
   - "Add Data" or "Data Inputs" page visible
   - "Files & Directories" or "Monitor" option selected
   - File path input field visible showing "/var/log/kern.log" or similar
   - Index selection dropdown/field visible

3. Was the data source configuration completed?
   - Success message or monitor appearing in inputs list
   - Settings showing the new monitor configuration

Note: The agent should have used the web UI, not just the REST API or CLI.

Respond in JSON format:
{
    "splunk_web_visible": true/false,
    "data_input_ui_used": true/false,
    "file_path_visible": true/false,
    "index_configured": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


def verify_add_data_source(traj, env_info, task_info):
    """Verify that the agent added a new data source (monitor input) in Splunk."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('monitor_path', '/var/log/kern.log')
    expected_index = metadata.get('expected_index', 'system_logs')
    expected_sourcetype = metadata.get('expected_sourcetype', 'syslog')

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

    monitor_analysis = result.get('monitor_analysis', {})
    inputs_conf_has_kern = result.get('inputs_conf_has_kern', False)
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Criterion 1: A new monitor was added and detected via REST API (STRICT)
    found_kern_monitor = monitor_analysis.get('found_kern_monitor', False)
    new_monitors = monitor_analysis.get('new_monitors', [])
    monitor_path = monitor_analysis.get('monitor_path', '')

    # STRICT: Must be detected via REST API, not just config file grep
    if found_kern_monitor and monitor_path:
        criteria_met += 1
        feedback_parts.append(f"Monitor detected via REST API: {monitor_path}")
    elif len(new_monitors) > 0:
        feedback_parts.append(f"New monitors found but not kern.log: {new_monitors[:3]}")
    elif inputs_conf_has_kern:
        feedback_parts.append(f"FAIL: kern.log in config file but not detected via REST API (may need Splunk restart)")
    else:
        feedback_parts.append("FAIL: No new monitor input detected")

    # Criterion 2: Monitor path MUST be exactly "/var/log/kern.log" (STRICT)
    # STRICT: Exact path match required
    path_exact_match = (monitor_path == expected_path)

    if path_exact_match:
        criteria_met += 1
        feedback_parts.append(f"Correct path: {monitor_path}")
    elif 'kern.log' in monitor_path:
        feedback_parts.append(f"FAIL: Path contains kern.log but must be exactly '{expected_path}' (got: '{monitor_path}')")
    else:
        feedback_parts.append(f"FAIL: Monitor path must be '{expected_path}' (got: '{monitor_path}')")

    # Criterion 3: Monitor MUST use "system_logs" index, NOT "main" (STRICT)
    monitor_index = monitor_analysis.get('monitor_index', '').lower()

    # STRICT: Must be "system_logs" specifically, "main" is NOT acceptable
    index_exact_match = (monitor_index == expected_index.lower())

    if index_exact_match:
        criteria_met += 1
        feedback_parts.append(f"Correct index: {monitor_analysis.get('monitor_index', '')}")
    elif monitor_index == 'main':
        feedback_parts.append(f"FAIL: Index is 'main' but must be 'system_logs'")
    elif monitor_index:
        feedback_parts.append(f"FAIL: Index must be 'system_logs' (got: '{monitor_index}')")
    else:
        feedback_parts.append(f"FAIL: Monitor must specify index='system_logs'")

    # Criterion 4: Sourcetype should be appropriate (syslog/kern/linux)
    monitor_sourcetype = monitor_analysis.get('monitor_sourcetype', '').lower()
    sourcetype_valid = (monitor_sourcetype and (
        'syslog' in monitor_sourcetype or
        'kern' in monitor_sourcetype or
        'linux' in monitor_sourcetype or
        'log' in monitor_sourcetype
    ))

    if sourcetype_valid:
        criteria_met += 1
        feedback_parts.append(f"Valid sourcetype: {monitor_analysis.get('monitor_sourcetype', '')}")
    elif monitor_sourcetype:
        # If they set a sourcetype, it should be valid
        feedback_parts.append(f"Sourcetype '{monitor_sourcetype}' is non-standard but accepted")
        criteria_met += 1  # Be lenient on sourcetype if they set something
    elif found_kern_monitor:
        # Auto-detection is acceptable
        feedback_parts.append(f"Sourcetype: auto-detected (acceptable)")
        criteria_met += 1
    else:
        feedback_parts.append("Cannot verify sourcetype - monitor not found")

    # =========================================================================
    # VLM-BASED UI VERIFICATION (Criterion 5)
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
                    data_input_ui_used = parsed.get("data_input_ui_used", False)
                    file_path_visible = parsed.get("file_path_visible", False)

                    # UI verification passes if agent used web interface for data input
                    if splunk_web_visible and data_input_ui_used:
                        vlm_ui_verified = True
                        if file_path_visible:
                            feedback_parts.append("VLM: Web UI used, file path visible")
                        else:
                            feedback_parts.append("VLM: Web UI used (path may be scrolled/hidden)")
                    else:
                        feedback_parts.append("VLM WARNING: Web UI usage not confirmed")
                        logger.warning(f"VLM UI verification: splunk_web={splunk_web_visible}, data_input_ui={data_input_ui_used}")
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
    # Now 5 criteria: 4 programmatic + 1 VLM-based UI verification
    # The VLM criterion is a bonus - passing without it gives 80%, with it gives 100%

    total_criteria = 5 if query_vlm else 4
    if vlm_ui_verified:
        criteria_met += 1

    score = int((criteria_met / total_criteria) * 100)

    # STRICT: Path and index must be exact, monitor must be detected
    # VLM criterion is additional verification (not blocking, but reported)
    programmatic_passed = (found_kern_monitor and path_exact_match and index_exact_match)
    passed = programmatic_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "monitor_detected": found_kern_monitor and bool(monitor_path),
            "path_exact_match": path_exact_match,
            "index_exact_match": index_exact_match,
            "sourcetype_valid": sourcetype_valid or found_kern_monitor,
            "vlm_ui_verified": vlm_ui_verified,
        },
        "vlm_details": vlm_details,
    }
