#!/usr/bin/env python3
"""
Verifier for Measure Star Photometry task.

Hybrid verification (programmatic + VLM on trajectory).

Programmatic checks (from export script's AIJ macro + wmctrl):
  1. AIJ macro state query — images loaded
  2. Measurements in AIJ state
  3. FITS window visible (wmctrl)
  4. Results/Measurements window (wmctrl)
  5. Evidence of FITS file interaction (negative check)

VLM checks — using TRAJECTORY frames (framework-captured):
  6. Process verification: sampled trajectory frames show the agent
     progressing through FITS loading → aperture placement → results.
     Uses multiple images across the episode.
  7. Photometry content quality: final frame shows genuine photometry work
  8. Error/state check: no crashes, no welcome-screen-only

The trajectory frames are captured by the framework at every step and
cannot be tampered with by the agent. This makes them an independent
verification channel from the programmatic checks (which rely on
container data).

Environment state at screenshot time:
  - After aperture photometry, the Results window is typically the LAST
    window opened and therefore ON TOP of the FITS image window
  - The FITS image with aperture circles may be partially visible behind
    the Results window, or fully hidden
  - Trajectory frames from earlier steps capture the FITS image, aperture
    circles, and other states that are hidden in the final screenshot
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM HELPERS
# ================================================================

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


# ================================================================
# VLM PROMPTS
# ================================================================

# Process verification: uses MULTIPLE trajectory frames
TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent performing aperture photometry in AstroImageJ.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful aperture photometry, the agent should progress through these stages:
1. AstroImageJ open — the application toolbar/interface is visible
2. FITS image loaded — a grayscale astronomical image (star field with point sources) is open
3. Aperture placement — aperture circles placed on one or more stars in the image
4. Photometry results — a Results/Measurements table appears with numeric data (flux, coordinates, etc.)

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through at least stages 1, 2, and 4? (App open, image loaded, results visible)
2. FITS_IMAGE_VISIBLE: At any point, is a FITS astronomical image (star field) visible?
3. APERTURES_VISIBLE: At any point, are aperture circles visible on stars?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes (not the same screen repeated)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "fits_image_visible": true/false,
    "apertures_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression you see across the frames"
}
"""

# Content quality: uses the FINAL trajectory frame
PHOTOMETRY_QUALITY_PROMPT = """You are verifying that aperture photometry was performed in AstroImageJ.

This is a desktop screenshot. After performing aperture photometry, the typical
desktop state is:
- A Results/Measurements table window ON TOP (showing rows of numeric data)
- A FITS astronomical image (grayscale star field) partially or fully BEHIND the table
- Possibly aperture circles visible on stars in the image (if not fully covered)
- The AstroImageJ toolbar bar at the top

Assess the following (answer based on whatever IS visible — not everything will be):

1. GENUINE_PHOTOMETRY_WORK: Does this screenshot show evidence that aperture photometry
   was actually performed? Look for ANY of these indicators:
   - A Results/Measurements table with rows of numeric flux/brightness values
   - Aperture circles overlaid on stars in a FITS image
   - An astronomical grayscale image (star field) with point sources visible
   ANY ONE of these is sufficient evidence.

2. DATA_LOOKS_REAL: Does the visible data look like real astronomical photometry results
   (not fabricated)? Real photometry data has varying flux values across rows,
   coordinate columns, etc.

3. APPLICATION_IN_USE: Is AstroImageJ clearly in an active working state
   (not just the welcome screen, not crashed, not showing an error)?

Respond in JSON format:
{
    "genuine_photometry_work": true/false,
    "data_looks_real": true/false,
    "application_in_use": true/false,
    "visible_elements": ["list", "of", "what", "you", "can", "see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the screenshot"
}
"""

# Error detection: uses the FINAL trajectory frame
ERROR_CHECK_PROMPT = """Look at this AstroImageJ desktop screenshot.

Check ONLY for these problems:
1. ERROR_DIALOG: Any error popup, exception dialog, or Java exception blocking the view?
2. APPLICATION_CRASH: Does AstroImageJ appear crashed (gray window, no content, frozen)?
3. NO_WORK_DONE: Is this just the AstroImageJ welcome/startup screen with no images
   or results — meaning the agent never opened a FITS file or did any work?

Note: Overlapping windows and cluttered desktop are NORMAL for this application.
A Results table covering the FITS image is expected behavior, NOT a problem.

Respond in JSON format:
{
    "error_dialog": true/false,
    "application_crash": true/false,
    "no_work_done": true/false,
    "all_clear": true/false,
    "observations": "brief description of any actual problems"
}
"""


def verify_measure_star_photometry(traj, env_info, task_info):
    """
    Verify aperture photometry was performed using MULTIPLE INDEPENDENT signals.

    Criteria (8 total, pass requires >= 70%):
    Programmatic (5): AIJ state, measurements, FITS window, results window, interaction
    VLM (3): trajectory process, content quality, error check

    Returns:
        dict: {passed, score, feedback} where passed requires score >= 70
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fits_file = metadata.get('fits_file', 'hst_wfpc2_sample.fits')

    feedback_parts = []
    criteria_met = 0
    total_criteria = 0

    # ================================================================
    # Copy result file from container
    # ================================================================
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

    # Check 1: AIJ macro state — images loaded
    total_criteria += 1
    if result.get('aij_macro_success') and result.get('num_images_loaded', 0) > 0:
        criteria_met += 1
        image_title = result.get('current_image_title', '')
        feedback_parts.append(f"AIJ reports image loaded: {image_title}")
    else:
        feedback_parts.append("AIJ macro: No image detected")

    # Check 2: Measurements in AIJ state
    total_criteria += 1
    num_measurements = result.get('num_measurements', 0)
    if num_measurements > 0:
        criteria_met += 1
        feedback_parts.append(f"AIJ reports {num_measurements} measurement(s)")
    else:
        feedback_parts.append("AIJ macro: No measurements recorded")

    # Check 3: FITS window visible (wmctrl)
    total_criteria += 1
    if result.get('fits_window_found'):
        criteria_met += 1
        window_title = result.get('fits_window_title', '')
        feedback_parts.append(f"FITS window detected: {window_title}")
    else:
        windows_list = result.get('windows_list', '')
        expected_name = expected_fits_file.replace('.fits', '')
        if expected_name.lower() in windows_list.lower():
            criteria_met += 1
            feedback_parts.append(f"FITS window for {expected_fits_file} detected")
        else:
            feedback_parts.append("No FITS image window detected")

    # Check 4: Results/Measurements window (wmctrl)
    total_criteria += 1
    if result.get('results_window_found'):
        criteria_met += 1
        feedback_parts.append("Results/Measurements window visible")
    else:
        feedback_parts.append("No Results window detected")

    # Check 5: Evidence of FITS file interaction (negative check)
    total_criteria += 1
    if result.get('num_images_loaded', 0) == 0 and not result.get('fits_window_found'):
        feedback_parts.append("NEGATIVE: No evidence of FITS file interaction")
    else:
        criteria_met += 1
        feedback_parts.append("Evidence of FITS file interaction found")

    # ================================================================
    # VLM CHECKS (3 criteria)
    #
    # Uses TRAJECTORY frames — captured by the framework, not from
    # inside the container. The trajectory captures the full episode
    # including states that are hidden in the final screenshot (e.g.,
    # FITS image with aperture circles before Results table covers it).
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    # Get trajectory frames — framework-captured
    sampled_frames = sample_frames(traj, num_samples=5) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None
    vlm_available = query_vlm is not None and (has_trajectory or has_final)
    vlm_work_verified = False

    if vlm_available:

        # --- VLM Check 6: Process Verification (trajectory) ---
        # The most important VLM check. Sends sampled frames across the
        # episode to verify the agent went through the photometry workflow.
        # This catches what a single final screenshot cannot: the FITS image
        # with apertures (now hidden behind the Results table).
        total_criteria += 1
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                fits_visible = process_result.get('fits_image_visible', False)

                if workflow_ok and progression_ok:
                    criteria_met += 1
                    feedback_parts.append("VLM process: Full workflow progression confirmed")
                elif workflow_ok or (fits_visible and progression_ok):
                    criteria_met += 0.5
                    feedback_parts.append("VLM process: Partial workflow confirmed")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient trajectory frames")

        # --- VLM Check 7: Content Quality (final frame) ---
        total_criteria += 1
        if has_final:
            quality = _vlm_query(
                query_vlm, PHOTOMETRY_QUALITY_PROMPT, image=final_frame
            )

            if quality:
                if quality.get('genuine_photometry_work'):
                    criteria_met += 1
                    vlm_work_verified = True
                    feedback_parts.append("VLM content: Genuine photometry work confirmed")
                    if quality.get('data_looks_real'):
                        feedback_parts.append("VLM content: Data appears authentic")
                else:
                    feedback_parts.append("VLM content: No evidence of photometry work")

                visible = quality.get('visible_elements', [])
                if visible:
                    feedback_parts.append(f"VLM sees: {', '.join(visible[:4])}")
            else:
                feedback_parts.append("VLM content check failed")
        else:
            feedback_parts.append("VLM content: No final frame available")

        # --- VLM Check 8: Error/State Check (final frame) ---
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
                    if err_result.get('application_crash'):
                        issues.append("crash")
                    if err_result.get('no_work_done'):
                        issues.append("no work done")
                    if issues:
                        feedback_parts.append(f"VLM error: {', '.join(issues)}")
                    else:
                        criteria_met += 0.5
                        feedback_parts.append("VLM error: Possible issues (unclear)")
            else:
                feedback_parts.append("VLM error check failed")
        else:
            feedback_parts.append("VLM error: No final frame available")

    else:
        # VLM not available — give partial credit if programmatic checks passed
        feedback_parts.append("VLM checks not available")
        total_criteria += 3  # Still count VLM criteria in denominator
        if criteria_met >= 3:
            criteria_met += 1  # Partial credit for VLM portion

    # ================================================================
    # CALCULATE FINAL SCORE
    # ================================================================

    score = int((criteria_met / total_criteria) * 100) if total_criteria > 0 else 0

    key_criteria_met = (
        result.get('fits_window_found')
        or result.get('num_images_loaded', 0) > 0
    )

    passed = score >= 70 and key_criteria_met

    if passed and score >= 90:
        feedback_parts.append("Excellent task completion")
    elif passed:
        feedback_parts.append("Task completed successfully")
    else:
        feedback_parts.append("Task not completed - need FITS image loaded and measurements taken")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "aij_macro_success": result.get('aij_macro_success'),
            "num_images": result.get('num_images_loaded'),
            "num_measurements": result.get('num_measurements'),
            "fits_window_found": result.get('fits_window_found'),
            "vlm_available": vlm_available,
            "vlm_work_verified": vlm_work_verified,
            "trajectory_frames_sampled": len(sampled_frames),
        }
    }
