#!/usr/bin/env python3
"""
Verifier for Calculate Carbon Footprint task.

Hybrid verification (programmatic + VLM on trajectory).

Programmatic checks:
  1. OpenLCA was actively used
  2. Database was modified (calculation ran)
  3. Results evidence (window, log, or exported files)
  4. Exported result files found

VLM checks (trajectory frames):
  5. Process: agent opens product system -> runs calculation -> views results
  6. Content: final frame shows LCIA results (impact categories, values)
  7. Error check
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent working in openLCA to calculate Life Cycle Impact Assessment (LCIA) results.

The images are sampled chronologically (earliest to latest).

For successful LCIA calculation, the agent should progress through:
1. openLCA with a product system open (model graph or editor view)
2. Calculation dialog - selecting an LCIA method (TRACI, ReCiPe, CML, etc.)
3. Calculation running - possibly a progress bar or loading indicator
4. LCIA results displayed - a table or chart showing impact categories and values
   (e.g., Global Warming Potential in kg CO2-eq, Acidification, Eutrophication)

Assess:
1. WORKFLOW_COMPLETED: Did the agent go through product system -> calculation -> results?
2. PRODUCT_SYSTEM_OPENED: Was a product system visible (model graph or editor)?
3. CALCULATION_DIALOG: Was a calculation setup dialog visible?
4. RESULTS_DISPLAYED: Were LCIA results (impact categories with numeric values) visible?
5. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "product_system_opened": true/false,
    "calculation_dialog": true/false,
    "results_displayed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe progression"
}
"""

CONTENT_QUALITY_PROMPT = """You are verifying that LCIA (Life Cycle Impact Assessment) results were calculated in openLCA.

This is a desktop screenshot. After calculating LCIA results, the typical state shows:
- A results view with a table of impact categories
- Categories may include: Global Warming (GWP), Acidification, Eutrophication, Ozone Depletion, etc.
- Each category has a numeric value and a unit (e.g., kg CO2-eq, kg SO2-eq)
- There may be bar charts or pie charts visualizing the results
- The results tab/editor is typically labeled "Result: <product system name>"

Assess:
1. LCIA_RESULTS_VISIBLE: Are LCIA results (impact categories with values) visible?
2. IMPACT_VALUES_SHOWN: Can you see numeric environmental impact values?
3. GLOBAL_WARMING_VISIBLE: Is Global Warming / GWP / Climate Change shown as a category?
4. APPLICATION_IN_USE: Is openLCA actively showing results (not startup or empty)?

Respond in JSON format:
{
    "lcia_results_visible": true/false,
    "impact_values_shown": true/false,
    "global_warming_visible": true/false,
    "application_in_use": true/false,
    "visible_elements": ["list"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

ERROR_CHECK_PROMPT = """Look at this openLCA desktop screenshot.

Check ONLY for these problems:
1. ERROR_DIALOG: Any error popup, calculation failure, or Java exception?
2. APPLICATION_CRASH: Does openLCA appear crashed or frozen?
3. NO_WORK_DONE: Is this just the product system editor with no calculation results?

Note: A results view with impact categories and values is the expected outcome.

Respond in JSON format:
{
    "error_dialog": true/false,
    "application_crash": true/false,
    "no_work_done": true/false,
    "all_clear": true/false,
    "observations": "brief description"
}
"""


def verify_calculate_carbon_footprint(traj, env_info, task_info):
    """
    Verify LCIA calculation was performed and results are visible.

    Criteria (7 total, pass requires >= 60%):
    Programmatic (4): app used, DB modified, results evidence, export files
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

    # Check 1: OpenLCA was actively used
    total_criteria += 1
    if result.get('openlca_running'):
        criteria_met += 1
        feedback_parts.append("OpenLCA was running")
    else:
        feedback_parts.append("OpenLCA was not running")

    # Check 2: Database was modified (calculation ran)
    total_criteria += 1
    if result.get('db_recently_modified'):
        criteria_met += 1
        feedback_parts.append("Database modified (calculation likely ran)")
    else:
        feedback_parts.append("Database not recently modified")

    # Check 3: Results evidence (window, log, or Derby impact categories)
    total_criteria += 1
    has_impact_categories = result.get('impact_category_count', 0) > 0
    results_evidence = (
        result.get('results_visible')
        or result.get('calculation_evidence')
        or result.get('calc_in_log')
        or has_impact_categories
    )
    if results_evidence:
        criteria_met += 1
        method = result.get('impact_method', '')
        extras = []
        if has_impact_categories:
            extras.append(f"impact categories in DB: {result.get('impact_category_count')}")
        if method:
            extras.append(f"method: {method}")
        feedback_parts.append(f"Calculation evidence found. {'; '.join(extras)}")
    else:
        feedback_parts.append("No calculation evidence")

    # Check 4: Exported result files
    total_criteria += 1
    if result.get('new_result_file'):
        criteria_met += 1
        feedback_parts.append(f"Result file exported: {os.path.basename(result.get('new_result_file', ''))}")
    elif result.get('current_result_count', 0) > result.get('initial_result_count', 0):
        criteria_met += 0.5
        feedback_parts.append("New result files detected")
    else:
        # Don't penalize too heavily - viewing results in GUI is also valid
        if results_evidence:
            criteria_met += 0.5
            feedback_parts.append("Results visible in GUI (no file export)")
        else:
            feedback_parts.append("No result files exported")

    # ================================================================
    # VLM CHECKS (3 criteria)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    sampled_frames = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None
    vlm_available = query_vlm is not None and (has_trajectory or has_final)
    vlm_results_confirmed = False

    if vlm_available:
        # VLM Check 5: Process Verification (trajectory)
        total_criteria += 1
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                results_shown = process_result.get('results_displayed', False)
                if workflow_ok and results_shown:
                    criteria_met += 1
                    vlm_results_confirmed = True
                    feedback_parts.append("VLM process: Full LCIA workflow confirmed")
                elif workflow_ok or process_result.get('calculation_dialog', False):
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
                if quality.get('lcia_results_visible') and quality.get('impact_values_shown'):
                    criteria_met += 1
                    vlm_results_confirmed = True
                    feedback_parts.append("VLM content: LCIA results with impact values confirmed")
                    if quality.get('global_warming_visible'):
                        feedback_parts.append("VLM content: GWP category visible")
                elif quality.get('application_in_use'):
                    criteria_met += 0.5
                    feedback_parts.append("VLM content: App active but results unclear")
                else:
                    feedback_parts.append("VLM content: No LCIA results visible")
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
                        issues.append("no calculation done")
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

    key_criteria = results_evidence or vlm_results_confirmed
    passed = score >= 60 and key_criteria

    if passed and score >= 85:
        feedback_parts.append("Excellent task completion")
    elif passed:
        feedback_parts.append("Task completed successfully")
    else:
        feedback_parts.append("Task not completed - need LCIA calculation performed and results visible")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "results_evidence": results_evidence,
            "vlm_results_confirmed": vlm_results_confirmed,
            "vlm_available": vlm_available,
            "result_file": result.get('new_result_file'),
        }
    }
