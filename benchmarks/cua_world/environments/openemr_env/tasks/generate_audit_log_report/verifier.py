#!/usr/bin/env python3
"""
Verifier for Generate HIPAA Audit Log Report task in OpenEMR

This task tests the agent's ability to:
1. Navigate to administrative/reporting features
2. Find the Audit Log functionality
3. Apply patient-specific filters
4. Configure date ranges
5. Generate/view a compliance report

Verification Strategy:
- Primary: VLM analysis of trajectory screenshots to verify navigation and filter application
- Secondary: Database checks for any audit log access indicators
- Anti-gaming: Timestamp checks, trajectory analysis (not just final screenshot)

Scoring (100 points):
- Logged in successfully: 10 points
- Navigated to Reports section: 15 points
- Found Audit Log feature: 20 points
- Applied patient filter (Rosa Bayer): 25 points
- Set date range: 15 points
- Report displayed: 15 points

Pass threshold: 70 points with "Found Audit Log" and "Patient Filter Applied" both met
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_audit_log_report(traj, env_info, task_info):
    """
    Verify that the agent successfully generated an audit log report for the specified patient.
    
    Uses VLM trajectory analysis as primary verification since this is a navigation/UI task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 2)
    expected_fname = metadata.get('patient_fname', 'Rosa')
    expected_lname = metadata.get('patient_lname', 'Bayer')
    date_range_days = metadata.get('date_range_days', 30)

    score = 0
    feedback_parts = []
    subscores = {
        "logged_in": False,
        "navigated_reports": False,
        "found_audit_log": False,
        "patient_filter_applied": False,
        "date_range_set": False,
        "report_displayed": False
    }

    # Load exported result data
    result_data = {}
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/audit_log_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result_data = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Could not load result data: {e}")
        result_data = {}

    logger.info(f"Result data: {result_data}")

    # Anti-gaming: Check task duration
    task_start = result_data.get('task_start_timestamp', 0)
    task_end = result_data.get('task_end_timestamp', 0)
    task_duration = task_end - task_start if task_end > task_start else 0
    
    if task_duration < 10:
        feedback_parts.append("WARNING: Task completed suspiciously fast")

    # Check for database-level indicators of audit log access
    log_counts = result_data.get('log_counts', {})
    new_entries = log_counts.get('new_entries', 0)
    audit_view_events = result_data.get('audit_view_events', 0)

    # VLM-based trajectory verification (PRIMARY METHOD)
    vlm_result = None
    if query_vlm:
        try:
            vlm_result = verify_via_vlm(traj, query_vlm, expected_fname, expected_lname)
            logger.info(f"VLM verification result: {vlm_result}")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            vlm_result = None

    # Score based on VLM results (primary) and database indicators (secondary)
    
    # CRITERION 1: Logged in successfully (10 points)
    logged_in = False
    if vlm_result and vlm_result.get('logged_in', False):
        logged_in = True
    elif new_entries > 0:  # Activity indicates login
        logged_in = True
    
    if logged_in:
        score += 10
        subscores["logged_in"] = True
        feedback_parts.append("✅ Logged in to OpenEMR")
    else:
        feedback_parts.append("❌ Could not confirm login")

    # CRITERION 2: Navigated to Reports section (15 points)
    navigated_reports = False
    if vlm_result and vlm_result.get('reports_menu_accessed', False):
        navigated_reports = True
    
    if navigated_reports:
        score += 15
        subscores["navigated_reports"] = True
        feedback_parts.append("✅ Navigated to Reports section")
    else:
        feedback_parts.append("❌ Reports section navigation not confirmed")

    # CRITERION 3: Found Audit Log feature (20 points)
    found_audit_log = False
    if vlm_result and vlm_result.get('audit_log_visible', False):
        found_audit_log = True
    elif audit_view_events > 0:  # Database shows audit log was accessed
        found_audit_log = True
    
    if found_audit_log:
        score += 20
        subscores["found_audit_log"] = True
        feedback_parts.append("✅ Found Audit Log feature")
    else:
        feedback_parts.append("❌ Audit Log feature not found")

    # CRITERION 4: Applied patient filter (25 points) - CRITICAL
    patient_filter_applied = False
    if vlm_result and vlm_result.get('patient_filter_set', False):
        patient_filter_applied = True
    
    if patient_filter_applied:
        score += 25
        subscores["patient_filter_applied"] = True
        feedback_parts.append(f"✅ Patient filter applied for {expected_fname} {expected_lname}")
    else:
        feedback_parts.append(f"❌ Patient filter for {expected_fname} {expected_lname} not confirmed")

    # CRITERION 5: Set date range (15 points)
    date_range_set = False
    if vlm_result and vlm_result.get('date_range_visible', False):
        date_range_set = True
    
    if date_range_set:
        score += 15
        subscores["date_range_set"] = True
        feedback_parts.append("✅ Date range configured")
    else:
        feedback_parts.append("❌ Date range configuration not confirmed")

    # CRITERION 6: Report displayed (15 points)
    report_displayed = False
    if vlm_result and vlm_result.get('report_results_visible', False):
        report_displayed = True
    
    if report_displayed:
        score += 15
        subscores["report_displayed"] = True
        feedback_parts.append("✅ Audit log report displayed")
    else:
        feedback_parts.append("❌ Report results not visible")

    # Determine pass/fail
    # Must have found audit log AND applied patient filter to pass
    key_criteria_met = subscores["found_audit_log"] and subscores["patient_filter_applied"]
    passed = score >= 70 and key_criteria_met

    # If VLM wasn't available, provide partial credit based on database evidence
    if not query_vlm and not vlm_result:
        feedback_parts.append("Note: VLM verification unavailable, using database evidence only")
        # Give partial credit if there's evidence of activity
        if new_entries > 5:
            score = min(score + 20, 50)
            feedback_parts.append(f"Database shows {new_entries} new log entries (agent activity detected)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "vlm_result": vlm_result,
            "result_data": result_data,
            "task_duration_seconds": task_duration
        }
    }


def verify_via_vlm(traj, query_vlm, expected_fname, expected_lname):
    """
    Use VLM to analyze trajectory screenshots for evidence of task completion.
    
    Examines multiple frames from the trajectory to verify the workflow was followed.
    """
    # Import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("Could not import gym_anything.vlm utilities")
        # Fallback to basic trajectory access
        sample_trajectory_frames = None
        get_final_screenshot = None

    result = {
        "logged_in": False,
        "reports_menu_accessed": False,
        "audit_log_visible": False,
        "patient_filter_set": False,
        "date_range_visible": False,
        "report_results_visible": False,
        "confidence": "low",
        "reasoning": ""
    }

    # Get trajectory frames
    frames = []
    final_screenshot = None
    
    if sample_trajectory_frames and get_final_screenshot:
        try:
            frames = sample_trajectory_frames(traj, n=5)  # Sample 5 frames across trajectory
            final_screenshot = get_final_screenshot(traj)
        except Exception as e:
            logger.warning(f"Error getting trajectory frames: {e}")
    
    # Fallback: try to get frames from traj dict
    if not frames and isinstance(traj, dict):
        traj_frames = traj.get('frames', [])
        if traj_frames:
            # Sample evenly across trajectory
            n_frames = min(5, len(traj_frames))
            step = max(1, len(traj_frames) // n_frames)
            frames = [traj_frames[i] for i in range(0, len(traj_frames), step)][:n_frames]
        
        if not final_screenshot and traj_frames:
            final_screenshot = traj_frames[-1]

    if not frames and not final_screenshot:
        logger.warning("No trajectory frames available for VLM verification")
        return result

    # Prepare images for VLM
    images_to_analyze = frames + ([final_screenshot] if final_screenshot else [])
    
    if not images_to_analyze:
        return result

    # VLM prompt for trajectory analysis
    vlm_prompt = f"""You are verifying if a computer agent successfully completed a HIPAA audit log report task in OpenEMR (Electronic Health Records system).

TASK: Generate an audit log report showing access history for patient {expected_fname} {expected_lname}.

Analyze these screenshots from the agent's workflow (in chronological order) and determine:

1. **logged_in**: Did the agent successfully log in? (Look for dashboard, patient menus, logged-in user interface)

2. **reports_menu_accessed**: Did the agent navigate to Reports menu or Administration menu? (Look for "Reports" dropdown, report listings)

3. **audit_log_visible**: Is an Audit Log interface visible in any screenshot? Look for:
   - Page titled "Audit Log" or "Access Log" or "Activity Log"
   - Log viewer interface with columns like Date, User, Event, Patient
   - Filter controls for log viewing

4. **patient_filter_set**: Is there evidence the patient filter was set to "{expected_fname} {expected_lname}"? Look for:
   - Patient name "{expected_fname}" or "{expected_lname}" in a filter field
   - Patient ID "2" in a search/filter
   - Dropdown or text field showing patient selection

5. **date_range_visible**: Are date range filters visible? Look for:
   - Date picker fields (From/To dates)
   - Date range selector
   - Any date filtering controls

6. **report_results_visible**: Are audit log results displayed? Look for:
   - Table/list showing log entries
   - Columns with dates, users, actions
   - Any tabular data representing access logs

Respond in JSON format:
{{
    "logged_in": true/false,
    "reports_menu_accessed": true/false,
    "audit_log_visible": true/false,
    "patient_filter_set": true/false,
    "date_range_visible": true/false,
    "report_results_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation of what you observed across the trajectory"
}}
"""

    try:
        vlm_response = query_vlm(
            prompt=vlm_prompt,
            images=images_to_analyze
        )
        
        if vlm_response and vlm_response.get('success'):
            parsed = vlm_response.get('parsed', {})
            result.update({
                "logged_in": parsed.get('logged_in', False),
                "reports_menu_accessed": parsed.get('reports_menu_accessed', False),
                "audit_log_visible": parsed.get('audit_log_visible', False),
                "patient_filter_set": parsed.get('patient_filter_set', False),
                "date_range_visible": parsed.get('date_range_visible', False),
                "report_results_visible": parsed.get('report_results_visible', False),
                "confidence": parsed.get('confidence', 'low'),
                "reasoning": parsed.get('reasoning', '')
            })
        else:
            logger.warning(f"VLM query failed: {vlm_response.get('error', 'Unknown error')}")
            
    except Exception as e:
        logger.error(f"VLM verification exception: {e}")

    return result