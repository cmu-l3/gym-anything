#!/usr/bin/env python3
"""Verifier for search_security_events task.

STRICT REQUIREMENTS:
- Must search in security_logs index specifically
- Must search for "Failed password" events
- Must produce actual results with meaningful event counts
- Search must complete successfully
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

UI_VERIFICATION_PROMPT = """You are verifying if a computer agent used the Splunk web interface to perform a search task.

TASK: Search for failed SSH login attempts in Splunk using the web interface.

Look at these screenshots from the agent's trajectory and determine:

1. Is Splunk's web interface visible (not just a terminal or REST API)?
   - Look for Splunk's green/black UI, search bar, app navigation
   - The "Search & Reporting" app or similar Splunk UI elements

2. Did the agent interact with the search interface?
   - Search bar visible with a query entered
   - Search results displayed in the UI
   - Events timeline or statistics visible

3. Are search results visible that show security/authentication events?
   - Look for event listings with timestamps
   - "Failed" or "authentication" related text in results
   - Event count or statistics displayed

Note: The agent should have used the web UI, not just the REST API or CLI.

Respond in JSON format:
{
    "splunk_web_visible": true/false,
    "search_interface_used": true/false,
    "results_visible_in_ui": true/false,
    "security_events_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


def verify_search_security_events(traj, env_info, task_info):
    """Verify that the agent successfully searched for failed SSH login events in Splunk."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_index = metadata.get('search_index', 'security_logs')
    expected_keyword = metadata.get('search_keyword', 'Failed password')
    min_event_count = metadata.get('min_event_count', 10)

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

    search_analysis = result.get('search_analysis', {})
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Criterion 1: New search jobs were created (agent interacted with Splunk)
    new_jobs = result.get('new_jobs_created', 0)
    if new_jobs > 0:
        criteria_met += 1
        feedback_parts.append(f"New search jobs created: {new_jobs}")
    else:
        feedback_parts.append("FAIL: No new search jobs detected - agent did not run any searches")

    # Criterion 2: Search query MUST reference security_logs index specifically (STRICT)
    search_query = search_analysis.get('search_query', '').lower()
    found_security_search = search_analysis.get('found_security_search', False)

    # STRICT: Must contain "security_logs" index reference
    has_security_logs_index = 'security_logs' in search_query or 'index=security_logs' in search_query

    if has_security_logs_index and found_security_search:
        criteria_met += 1
        feedback_parts.append(f"Correct index: search queries security_logs")
    else:
        feedback_parts.append(f"FAIL: Search must query 'security_logs' index (got: {search_query[:80]})")

    # Criterion 3: Search MUST contain "Failed" keyword and produce meaningful results (STRICT)
    has_failed_keyword = 'failed' in search_query
    result_count = search_analysis.get('result_count', 0)
    event_count = search_analysis.get('event_count', 0)

    # STRICT: Must have "failed" keyword AND produce results above minimum threshold
    if has_failed_keyword and (result_count > 0 or event_count >= min_event_count):
        criteria_met += 1
        feedback_parts.append(f"Valid search: 'Failed' keyword found, {event_count} events returned")
    elif has_failed_keyword:
        feedback_parts.append(f"FAIL: Search has 'Failed' keyword but returned too few events ({event_count} < {min_event_count})")
    elif result_count > 0 or event_count > 0:
        feedback_parts.append(f"FAIL: Search returned events but missing 'Failed' keyword in query")
    else:
        feedback_parts.append(f"FAIL: Search must include 'Failed' keyword and return events")

    # Criterion 4: The search completed successfully
    search_status = search_analysis.get('search_status', '').upper()
    if search_status in ('DONE', 'FINALIZED', 'COMPLETED'):
        criteria_met += 1
        feedback_parts.append(f"Search completed: status={search_status}")
    elif search_status == 'PAUSED':
        feedback_parts.append(f"PARTIAL: Search paused, not fully completed")
    else:
        feedback_parts.append(f"FAIL: Search did not complete (status={search_status})")

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
                    search_interface_used = parsed.get("search_interface_used", False)
                    results_visible = parsed.get("results_visible_in_ui", False)

                    # UI verification passes if agent used web interface
                    if splunk_web_visible and search_interface_used:
                        vlm_ui_verified = True
                        if results_visible:
                            feedback_parts.append("VLM: Web UI used, results visible")
                        else:
                            feedback_parts.append("VLM: Web UI used (results may be scrolled/hidden)")
                    else:
                        feedback_parts.append("VLM WARNING: Web UI usage not confirmed")
                        logger.warning(f"VLM UI verification: splunk_web={splunk_web_visible}, search_used={search_interface_used}")
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

    # STRICT: All 4 programmatic criteria required to pass
    # VLM criterion is additional verification (not blocking, but reported)
    programmatic_passed = (
        new_jobs > 0 and
        has_security_logs_index and
        has_failed_keyword and (result_count > 0 or event_count >= min_event_count) and
        search_status in ('DONE', 'FINALIZED', 'COMPLETED')
    )
    passed = programmatic_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "new_jobs_created": new_jobs > 0,
            "correct_index": has_security_logs_index,
            "failed_keyword_and_results": has_failed_keyword and (result_count > 0 or event_count >= min_event_count),
            "search_completed": search_status in ('DONE', 'FINALIZED', 'COMPLETED'),
            "vlm_ui_verified": vlm_ui_verified,
        },
        "vlm_details": vlm_details,
    }
