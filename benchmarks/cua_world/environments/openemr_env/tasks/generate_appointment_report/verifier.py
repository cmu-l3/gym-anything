#!/usr/bin/env python3
"""
Verifier for Generate Appointment Report task in OpenEMR

This task is primarily verified through VLM analysis of trajectory screenshots,
since report generation is a visual/navigation task without direct database changes.

Verification Strategy:
1. Trajectory Analysis: Check that agent navigated through reports workflow
2. Final State: Verify report results page is displayed
3. Anti-gaming: Ensure actual work was done (not just final screenshot)
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# VLM Prompts for trajectory verification
TRAJECTORY_PROMPT = """You are verifying if a computer agent successfully navigated through OpenEMR to generate an appointment report.

Look at these screenshots from the agent's workflow and determine:

1. LOGIN: Did the agent log into OpenEMR? (Look for: login form -> dashboard transition)
2. REPORTS MENU: Did the agent access the Reports menu? (Look for: "Reports" in navigation, dropdown menu visible)
3. REPORT SELECTION: Did the agent select an appointments-related report? (Look for: report configuration page, "Appointments" in title)
4. DATE CONFIGURATION: Did the agent appear to configure date parameters? (Look for: date fields, calendar widgets, form inputs)
5. REPORT GENERATED: Did the agent generate/submit the report? (Look for: report results, table data, "no results" message, report output)

Analyze the workflow progression across all screenshots.

Respond in JSON format:
{
    "login_completed": true/false,
    "reports_menu_accessed": true/false,
    "report_type_selected": true/false,
    "dates_configured": true/false,
    "report_generated": true/false,
    "workflow_progression_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of the workflow observed"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of an OpenEMR appointment report generation task.

Look at this screenshot and determine:

1. Is this OpenEMR (healthcare/EHR system interface)?
2. Does this appear to be a report output page? Look for:
   - Table/grid with data columns
   - "Report" in the page title or header
   - Date range indicators
   - "No results" or "No appointments" message (also valid)
   - Column headers like Date, Time, Patient, Provider, Status
3. Is this in the Reports section of OpenEMR?

Note: An empty report ("no results found") is a VALID successful outcome if the report was properly generated.

Respond in JSON format:
{
    "is_openemr": true/false,
    "is_report_output": true/false,
    "shows_report_data_or_no_results": true/false,
    "appears_to_be_reports_section": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "what you observe in the screenshot"
}
"""


def verify_generate_appointment_report(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent successfully generated an appointment report.

    Scoring (100 points total):
    - Reports menu accessed: 20 points
    - Report type selected: 20 points
    - Date parameters configured: 25 points
    - Report generated: 25 points
    - Results visible: 10 points

    Passing threshold: 70 points with report_generated criterion met
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    subscores = {
        "reports_accessed": False,
        "report_selected": False,
        "dates_configured": False,
        "report_generated": False,
        "results_visible": False
    }

    # Get metadata for scoring weights
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {
        "reports_accessed": 20,
        "report_selected": 20,
        "dates_configured": 25,
        "report_generated": 25,
        "results_visible": 10
    })

    # Step 1: Load exported result data
    result_data = {}
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/generate_report_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result_data = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
        result_data = {}

    logger.info(f"Loaded result data: {result_data}")

    # Anti-gaming: Check task duration
    task_duration = result_data.get('task_duration_seconds', 0)
    if task_duration < 10:
        feedback_parts.append(f"WARNING: Task completed suspiciously fast ({task_duration}s)")
        # Don't fail outright, but note it

    # Check basic state
    firefox_running = result_data.get('firefox_running', False)
    if not firefox_running:
        feedback_parts.append("Firefox was not running at task end")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Step 2: VLM Verification using trajectory frames
    trajectory_result = None
    final_result = None

    if query_vlm:
        # Import trajectory sampling utilities
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

            # Get trajectory frames (sample across the entire trajectory)
            trajectory_frames = sample_trajectory_frames(traj, n=6)
            final_screenshot = get_final_screenshot(traj)

            logger.info(f"Got {len(trajectory_frames)} trajectory frames")

            # Analyze trajectory progression
            if trajectory_frames and len(trajectory_frames) >= 2:
                trajectory_result = query_vlm(
                    prompt=TRAJECTORY_PROMPT,
                    images=trajectory_frames
                )
                logger.info(f"Trajectory VLM result: {trajectory_result}")

            # Analyze final state
            if final_screenshot:
                final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                logger.info(f"Final state VLM result: {final_result}")

        except ImportError as e:
            logger.warning(f"Could not import VLM utilities: {e}")
        except Exception as e:
            logger.warning(f"VLM analysis failed: {e}")

    # Step 3: Score based on VLM results
    
    # Parse trajectory analysis
    if trajectory_result and trajectory_result.get('success'):
        parsed_traj = trajectory_result.get('parsed', {})

        # Check login completed
        if parsed_traj.get('login_completed', False):
            feedback_parts.append("✓ Login completed")
        else:
            feedback_parts.append("Login not clearly observed")

        # Reports menu accessed (20 points)
        if parsed_traj.get('reports_menu_accessed', False):
            score += weights.get('reports_accessed', 20)
            subscores['reports_accessed'] = True
            feedback_parts.append("✓ Reports menu accessed")
        else:
            feedback_parts.append("✗ Reports menu not accessed")

        # Report type selected (20 points)
        if parsed_traj.get('report_type_selected', False):
            score += weights.get('report_selected', 20)
            subscores['report_selected'] = True
            feedback_parts.append("✓ Appointment report selected")
        else:
            feedback_parts.append("✗ Report type not selected")

        # Dates configured (25 points)
        if parsed_traj.get('dates_configured', False):
            score += weights.get('dates_configured', 25)
            subscores['dates_configured'] = True
            feedback_parts.append("✓ Date parameters configured")
        else:
            feedback_parts.append("✗ Date configuration not observed")

        # Report generated (25 points)
        if parsed_traj.get('report_generated', False):
            score += weights.get('report_generated', 25)
            subscores['report_generated'] = True
            feedback_parts.append("✓ Report generated")
        else:
            feedback_parts.append("✗ Report generation not confirmed")

        # Workflow progression (confidence boost)
        if parsed_traj.get('workflow_progression_visible', False):
            feedback_parts.append("✓ Clear workflow progression observed")
        
        traj_confidence = parsed_traj.get('confidence', 'low')
        traj_reasoning = parsed_traj.get('reasoning', '')
        if traj_reasoning:
            feedback_parts.append(f"Trajectory analysis: {traj_reasoning}")

    else:
        feedback_parts.append("Trajectory analysis unavailable or failed")
        # Try to give partial credit based on window title
        window_title = result_data.get('window_title', '').lower()
        if 'report' in window_title:
            score += 20  # Some credit for being on a reports page
            subscores['reports_accessed'] = True
            feedback_parts.append("Window title suggests reports page")

    # Parse final state analysis
    if final_result and final_result.get('success'):
        parsed_final = final_result.get('parsed', {})

        # Results visible (10 points)
        if parsed_final.get('is_report_output', False) or parsed_final.get('shows_report_data_or_no_results', False):
            score += weights.get('results_visible', 10)
            subscores['results_visible'] = True
            feedback_parts.append("✓ Report results page visible")

            # If trajectory didn't catch report generation but final state shows it, give credit
            if not subscores['report_generated'] and parsed_final.get('is_report_output', False):
                score += weights.get('report_generated', 25)
                subscores['report_generated'] = True
                feedback_parts.append("✓ Report output confirmed in final state")

        if parsed_final.get('is_openemr', False):
            feedback_parts.append("✓ OpenEMR interface confirmed")
        else:
            feedback_parts.append("? OpenEMR interface not clearly confirmed")

        final_confidence = parsed_final.get('confidence', 'low')
        final_reasoning = parsed_final.get('reasoning', '')
        if final_reasoning:
            feedback_parts.append(f"Final state: {final_reasoning}")

    else:
        feedback_parts.append("Final state analysis unavailable")
        # Check if window title indicates reports
        if result_data.get('appears_on_reports_page', False):
            score += 5
            feedback_parts.append("Window title indicates reports page")

    # Bonus: If a report file was exported
    if result_data.get('report_file_exported', False):
        score += 5  # Bonus points for file export
        feedback_parts.append(f"✓ Report file exported: {result_data.get('report_file_path', 'unknown')}")

    # Cap score at 100
    score = min(score, 100)

    # Determine pass/fail
    # Must have generated report (key criterion) and score >= 70
    key_criteria_met = subscores['report_generated']
    passed = score >= 70 and key_criteria_met

    # If we have strong final state confirmation, be more lenient
    if not passed and subscores['results_visible'] and score >= 60:
        passed = True
        feedback_parts.append("Passed on strong final state confirmation")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "task_duration": task_duration,
            "firefox_running": firefox_running,
            "report_file_exported": result_data.get('report_file_exported', False),
            "trajectory_analyzed": trajectory_result is not None,
            "final_state_analyzed": final_result is not None
        }
    }