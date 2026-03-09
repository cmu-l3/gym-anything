#!/usr/bin/env python3
"""
Verifier for Import USLCI Database task.

Hybrid verification (programmatic + VLM on trajectory).

Programmatic checks:
  1. New database created in workspace
  2. Database has expected name
  3. Database size indicates imported data
  4. Derby database structure present
  5. Evidence of USLCI data import

VLM checks (trajectory frames):
  6. Process verification: agent progresses through database creation -> import -> verification
  7. Content quality: final frame shows database with processes/flows
  8. Error check: no crashes or error dialogs
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images. Returns parsed dict or None."""
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent working in openLCA, a Life Cycle Assessment software.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful database creation and import, the agent should progress through these stages:
1. openLCA application open - the main window with Navigation panel visible
2. New database dialog - creating a new database (possibly named USLCI_Analysis)
3. Import dialog - importing JSON-LD data from a zip file
4. Database populated - the navigation tree showing expanded categories with Processes, Flows, etc.

Assess:
1. WORKFLOW_COMPLETED: Did the agent create a database and import data?
2. DATABASE_VISIBLE: Is a database visible in the navigation panel at any point?
3. IMPORT_DIALOG_SEEN: Was an import dialog or file selection dialog visible?
4. DATA_POPULATED: Does the navigation tree show categories with data (Processes, Flows)?
5. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "database_visible": true/false,
    "import_dialog_seen": true/false,
    "data_populated": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression"
}
"""

CONTENT_QUALITY_PROMPT = """You are verifying that a USLCI database was imported into openLCA.

This is a desktop screenshot of openLCA. After importing USLCI data, the typical state is:
- The Navigation panel on the left shows a database with expanded categories
- Categories include: Processes, Flows, Flow properties, Unit groups, etc.
- The Processes folder should contain real U.S. LCI processes (e.g., electricity, transport, materials)
- The main content area may show process details or be empty

Assess:
1. DATABASE_WITH_DATA: Does the navigation panel show a database with populated categories?
2. PROCESSES_VISIBLE: Can you see process entries (not just empty folders)?
3. APPLICATION_IN_USE: Is openLCA in an active working state (not startup, not crashed)?

Respond in JSON format:
{
    "database_with_data": true/false,
    "processes_visible": true/false,
    "application_in_use": true/false,
    "visible_elements": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

ERROR_CHECK_PROMPT = """Look at this openLCA desktop screenshot.

Check ONLY for these problems:
1. ERROR_DIALOG: Any error popup, Java exception, or import failure dialog?
2. APPLICATION_CRASH: Does openLCA appear crashed or frozen?
3. NO_WORK_DONE: Is this just the openLCA welcome/startup screen with no database created?

Respond in JSON format:
{
    "error_dialog": true/false,
    "application_crash": true/false,
    "no_work_done": true/false,
    "all_clear": true/false,
    "observations": "brief description of any problems"
}
"""


def verify_import_uslci_database(traj, env_info, task_info):
    """
    Verify USLCI database was created and imported.

    Criteria (8 total, pass requires >= 60%):
    Programmatic (5): new DB, name match, size, Derby structure, import evidence
    VLM (3): trajectory process, content quality, error check
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_db_name = metadata.get('database_name', 'USLCI_Analysis')

    feedback_parts = []
    criteria_met = 0
    total_criteria = 0

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

    # ================================================================
    # PROGRAMMATIC CHECKS (5 criteria)
    # ================================================================

    # Check 1: New database was created
    total_criteria += 1
    if result.get('database_found') and result.get('current_db_count', 0) > result.get('initial_db_count', 0):
        criteria_met += 1
        feedback_parts.append(f"New database created: {result.get('database_name', 'unknown')}")
    elif result.get('database_found'):
        criteria_met += 0.5
        feedback_parts.append(f"Database found: {result.get('database_name', 'unknown')}")
    else:
        feedback_parts.append("No new database detected")

    # Check 2: Database has expected name
    total_criteria += 1
    actual_name = result.get('database_name', '').lower()
    if expected_db_name.lower() in actual_name or 'uslci' in actual_name or 'lci' in actual_name:
        criteria_met += 1
        feedback_parts.append(f"Database name matches: {result.get('database_name')}")
    elif result.get('database_found'):
        criteria_met += 0.5
        feedback_parts.append(f"Database exists but name differs: {result.get('database_name')}")
    else:
        feedback_parts.append(f"Expected database '{expected_db_name}' not found")

    # Check 3: Database has processes (Derby count or size heuristic)
    total_criteria += 1
    process_count = result.get('process_count', 0)
    db_size = result.get('database_size_mb', 0)
    if process_count > 10:
        criteria_met += 1
        feedback_parts.append(f"Database has {process_count} processes (Derby query)")
    elif result.get('has_processes') or db_size > 20:
        criteria_met += 1
        feedback_parts.append(f"Database size ({db_size}MB) indicates imported data")
    elif db_size > 5:
        criteria_met += 0.5
        feedback_parts.append(f"Database size ({db_size}MB) suggests partial import")
    else:
        feedback_parts.append(f"Database size ({db_size}MB) too small for USLCI import")

    # Check 4: Database has flows (Derby count or size heuristic)
    total_criteria += 1
    flow_count = result.get('flow_count', 0)
    if flow_count > 10:
        criteria_met += 1
        feedback_parts.append(f"Database has {flow_count} flows (Derby query)")
    elif result.get('has_flows'):
        criteria_met += 1
        feedback_parts.append("Database contains flows")
    elif result.get('has_categories'):
        criteria_met += 0.5
        feedback_parts.append("Database has categories but flow data uncertain")
    else:
        feedback_parts.append("No flow data detected")

    # Check 5: Evidence of USLCI import
    total_criteria += 1
    if result.get('uslci_markers_found') or result.get('import_evidence'):
        criteria_met += 1
        feedback_parts.append("Evidence of USLCI import activity")
    elif process_count > 5 or (result.get('database_found') and db_size > 10):
        criteria_met += 0.5
        feedback_parts.append("Database exists with some content")
    else:
        feedback_parts.append("No import activity evidence")

    # ================================================================
    # VLM CHECKS (3 criteria)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    sampled_frames = sample_frames(traj, num_samples=5) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None
    vlm_available = query_vlm is not None and (has_trajectory or has_final)

    if vlm_available:
        # VLM Check 6: Process Verification (trajectory)
        total_criteria += 1
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                if workflow_ok and progression_ok:
                    criteria_met += 1
                    feedback_parts.append("VLM process: Full workflow confirmed")
                elif workflow_ok or process_result.get('database_visible', False):
                    criteria_met += 0.5
                    feedback_parts.append("VLM process: Partial workflow confirmed")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient trajectory frames")

        # VLM Check 7: Content Quality (final frame)
        total_criteria += 1
        if has_final:
            quality = _vlm_query(
                query_vlm, CONTENT_QUALITY_PROMPT, image=final_frame
            )
            if quality:
                if quality.get('database_with_data'):
                    criteria_met += 1
                    feedback_parts.append("VLM content: Database with data confirmed")
                elif quality.get('application_in_use'):
                    criteria_met += 0.5
                    feedback_parts.append("VLM content: App active but data unclear")
                else:
                    feedback_parts.append("VLM content: No database data visible")
            else:
                feedback_parts.append("VLM content check failed")
        else:
            feedback_parts.append("VLM content: No final frame")

        # VLM Check 8: Error Check (final frame)
        total_criteria += 1
        if has_final:
            err_result = _vlm_query(
                query_vlm, ERROR_CHECK_PROMPT, image=final_frame
            )
            if err_result:
                if err_result.get('all_clear', False):
                    criteria_met += 1
                    feedback_parts.append("VLM error: No errors detected")
                else:
                    issues = []
                    if err_result.get('error_dialog'):
                        issues.append("error dialog")
                    if err_result.get('no_work_done'):
                        issues.append("no work done")
                    if issues:
                        feedback_parts.append(f"VLM error: {', '.join(issues)}")
                    else:
                        criteria_met += 0.5
                        feedback_parts.append("VLM error: Unclear state")
            else:
                feedback_parts.append("VLM error check failed")
        else:
            feedback_parts.append("VLM error: No final frame")
    else:
        feedback_parts.append("VLM checks not available")
        total_criteria += 3
        if criteria_met >= 3:
            criteria_met += 1

    # ================================================================
    # CALCULATE FINAL SCORE
    # ================================================================

    score = int((criteria_met / total_criteria) * 100) if total_criteria > 0 else 0

    key_criteria_met = result.get('database_found') and result.get('current_db_count', 0) > result.get('initial_db_count', 0)
    passed = score >= 60 and key_criteria_met

    if passed and score >= 90:
        feedback_parts.append("Excellent task completion")
    elif passed:
        feedback_parts.append("Task completed successfully")
    else:
        feedback_parts.append("Task not completed - need database created and data imported")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "database_found": result.get('database_found'),
            "database_name": result.get('database_name'),
            "database_size_mb": result.get('database_size_mb'),
            "vlm_available": vlm_available,
        }
    }
