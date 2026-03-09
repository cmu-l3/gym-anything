#!/usr/bin/env python3
"""
Verifier for Create Product System task.

Hybrid verification (programmatic + VLM on trajectory).

Programmatic checks:
  1. Database exists and has content
  2. Database was recently modified (product system creation)
  3. Product system window or log evidence
  4. OpenLCA was actively used

VLM checks (trajectory frames):
  5. Process verification: agent navigates to process -> creates product system -> views model graph
  6. Content quality: final frame shows product system with model graph
  7. Error check: no crashes or error dialogs
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query. Returns parsed dict or None."""
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent working in openLCA to create a product system.

The images are sampled chronologically (earliest to latest).

For successful product system creation, the agent should progress through:
1. openLCA with a database open - navigation panel with Processes folder visible
2. Finding/opening a process - an electricity generation process open
3. Creating product system - right-click menu or dialog for product system creation
4. Product system visible - model graph showing connected processes (boxes and arrows)

Assess:
1. WORKFLOW_COMPLETED: Did the agent navigate through process finding and product system creation?
2. PROCESS_FOUND: Was a process editor or process details visible at any point?
3. PRODUCT_SYSTEM_DIALOG: Was a product system creation dialog visible?
4. MODEL_GRAPH_VISIBLE: Was a model graph with connected process boxes visible?
5. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "process_found": true/false,
    "product_system_dialog": true/false,
    "model_graph_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe progression"
}
"""

CONTENT_QUALITY_PROMPT = """You are verifying that a product system was created in openLCA.

This is a desktop screenshot. After creating a product system, the typical state shows:
- A model graph view with process boxes connected by arrows (flow connections)
- The navigation panel may show a Product systems folder with an entry
- Process boxes in the graph typically show names like "Electricity, at grid" etc.
- There may be a tab/editor labeled "Product system: <name>"

Assess:
1. PRODUCT_SYSTEM_VISIBLE: Is a product system model graph visible (boxes connected by arrows)?
2. ELECTRICITY_RELATED: Does it appear to involve electricity/energy processes?
3. APPLICATION_IN_USE: Is openLCA actively showing content (not startup or empty)?

Respond in JSON format:
{
    "product_system_visible": true/false,
    "electricity_related": true/false,
    "application_in_use": true/false,
    "visible_elements": ["list"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

ERROR_CHECK_PROMPT = """Look at this openLCA desktop screenshot.

Check ONLY for these problems:
1. ERROR_DIALOG: Any error popup, Java exception, or failure dialog?
2. APPLICATION_CRASH: Does openLCA appear crashed or frozen?
3. NO_WORK_DONE: Is this just the openLCA welcome screen with no product system created?

Respond in JSON format:
{
    "error_dialog": true/false,
    "application_crash": true/false,
    "no_work_done": true/false,
    "all_clear": true/false,
    "observations": "brief description"
}
"""


def verify_create_product_system(traj, env_info, task_info):
    """
    Verify product system was created from USLCI electricity process.

    Criteria (7 total, pass requires >= 60%):
    Programmatic (4): DB exists, DB modified, PS evidence, app used
    VLM (3): trajectory, content, errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    feedback_parts = []
    criteria_met = 0
    total_criteria = 0

    # Copy result file
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
    # PROGRAMMATIC CHECKS (4 criteria)
    # ================================================================

    # Check 1: Database exists and has content
    total_criteria += 1
    if result.get('database_found') and result.get('database_size_mb', 0) > 10:
        criteria_met += 1
        feedback_parts.append(f"Database active: {result.get('database_name')}")
    else:
        feedback_parts.append("No active database with content")

    # Check 2: Product system exists in Derby database (strong check)
    total_criteria += 1
    ps_count = result.get('ps_count', 0)
    ps_evidence = False
    if ps_count > 0:
        criteria_met += 1
        ps_evidence = True
        ps_name = result.get('product_system_name', '')
        feedback_parts.append(f"Product system found in DB (count={ps_count}): {ps_name}")
    elif result.get('ps_created_in_log') or result.get('product_system_window') or result.get('model_graph_visible'):
        criteria_met += 1
        ps_evidence = True
        ps_name = result.get('product_system_name', '')
        feedback_parts.append(f"Product system evidence (log/window): {ps_name}")
    else:
        feedback_parts.append("No product system found in database")

    # Check 3: Database was recently modified
    total_criteria += 1
    if result.get('db_recently_modified'):
        criteria_met += 1
        feedback_parts.append("Database modified during task")
    elif ps_evidence:
        criteria_met += 0.5
        feedback_parts.append("Product system exists but modification time unclear")
    else:
        feedback_parts.append("Database not recently modified")

    # Check 4: OpenLCA was actively used
    total_criteria += 1
    if result.get('openlca_running'):
        criteria_met += 1
        feedback_parts.append("OpenLCA was running")
    else:
        feedback_parts.append("OpenLCA was not running")

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
    vlm_ps_confirmed = False

    if vlm_available:
        # VLM Check 5: Process Verification (trajectory)
        total_criteria += 1
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                graph_ok = process_result.get('model_graph_visible', False)
                if workflow_ok and graph_ok:
                    criteria_met += 1
                    vlm_ps_confirmed = True
                    feedback_parts.append("VLM process: Full workflow with model graph confirmed")
                elif workflow_ok or process_result.get('process_found', False):
                    criteria_met += 0.5
                    feedback_parts.append("VLM process: Partial workflow confirmed")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

        # VLM Check 6: Content Quality (final frame)
        total_criteria += 1
        if has_final:
            quality = _vlm_query(
                query_vlm, CONTENT_QUALITY_PROMPT, image=final_frame
            )
            if quality:
                if quality.get('product_system_visible'):
                    criteria_met += 1
                    vlm_ps_confirmed = True
                    feedback_parts.append("VLM content: Product system graph visible")
                elif quality.get('application_in_use'):
                    criteria_met += 0.5
                    feedback_parts.append("VLM content: App active but graph unclear")
                else:
                    feedback_parts.append("VLM content: No product system visible")
            else:
                feedback_parts.append("VLM content check failed")
        else:
            feedback_parts.append("VLM content: No final frame")

        # VLM Check 7: Error Check
        total_criteria += 1
        if has_final:
            err_result = _vlm_query(
                query_vlm, ERROR_CHECK_PROMPT, image=final_frame
            )
            if err_result:
                if err_result.get('all_clear', False):
                    criteria_met += 1
                    feedback_parts.append("VLM error: No errors")
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
                        feedback_parts.append("VLM error: Unclear")
            else:
                feedback_parts.append("VLM error check failed")
        else:
            feedback_parts.append("VLM error: No final frame")
    else:
        feedback_parts.append("VLM checks not available")
        total_criteria += 3
        if criteria_met >= 2:
            criteria_met += 1

    # ================================================================
    # CALCULATE FINAL SCORE
    # ================================================================

    score = int((criteria_met / total_criteria) * 100) if total_criteria > 0 else 0

    key_criteria = ps_evidence or vlm_ps_confirmed
    passed = score >= 60 and key_criteria

    if passed and score >= 85:
        feedback_parts.append("Excellent task completion")
    elif passed:
        feedback_parts.append("Task completed successfully")
    else:
        feedback_parts.append("Task not completed - need product system created from USLCI process")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "product_system_evidence": ps_evidence,
            "vlm_ps_confirmed": vlm_ps_confirmed,
            "vlm_available": vlm_available,
        }
    }
