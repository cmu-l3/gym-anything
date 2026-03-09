#!/usr/bin/env python3
"""
Verifier for WASP-12b Exoplanet Transit Detection task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. Measurement file exists with data (25 pts)
  2. Differential photometry with comparison stars (12 pts)
  3. Transit depth within expected range (15 pts)
  4. Transit duration within expected range (10 pts)
  5. Mid-transit time reported (3 pts)
  6. Planet radius calculated (5 pts)

VLM checks (30 points) — using TRAJECTORY frames (framework-captured):
  7. Process verification (15 pts): Sampled trajectory frames show the agent
     progressing through the expected workflow (image loaded → aperture setup →
     photometry → light curve visible). Uses multiple images.
  8. Light curve content analysis (10 pts): Final trajectory frame shows a valid
     light curve with transit dip.
  9. Cross-validation (5 pts): Programmatic transit depth agrees with VLM
     transit detection.

The trajectory frames are captured by the framework at every step and cannot
be tampered with by the agent. This makes them the most trustworthy source
for VLM verification. Programmatic checks rely on container data (export
script JSON), which is a different trust domain.

Pass threshold: 60 points AND key work done
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
TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent performing exoplanet transit detection in AstroImageJ.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful transit detection, the agent should progress through these stages:
1. FITS image stack loaded — a grayscale astronomical star field image visible in AstroImageJ
2. Multi-aperture photometry setup — aperture circles placed on stars (target + comparison stars), possibly a multi-aperture settings dialog
3. Photometry execution completed
4. Results — a Multi-plot window showing a light curve (plot of brightness/flux vs time/frame), and/or a Measurements table with numeric data

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through at least stages 1 and 4? (Data loaded AND results visible in later frames)
2. PHOTOMETRY_SETUP_VISIBLE: At any point, is there evidence of photometry setup? (aperture circles on stars, multi-aperture dialog)
3. LIGHT_CURVE_VISIBLE: In the later frames, is a light curve plot visible?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes (not the same screen repeated)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "photometry_setup_visible": true/false,
    "light_curve_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression you see across the frames"
}
"""

# Content analysis: uses the FINAL trajectory frame
LIGHTCURVE_CONTENT_PROMPT = """You are analyzing the final state of an exoplanet transit detection task in AstroImageJ.

This is a desktop screenshot. After multi-aperture photometry, the Multi-plot window
(showing the light curve) is typically the topmost window, with the star field image
behind it.

Focus on the plot/graph window and assess:

1. TRANSIT_DIP: Is there a transit signal visible — a clear U-shaped or flat-bottomed
   brightness decrease followed by recovery to baseline?

2. DATA_QUALITY: Rate the photometry data quality (0-10).
   Good: consistent baseline, moderate scatter, clear in-transit points.
   Bad: extreme scatter, gaps, obvious systematics, very few points.

3. VALID_PLOT: Is this actually a light curve (flux/brightness vs time)?
   Not a histogram, not a blank window.

Respond in JSON format:
{
    "transit_dip_visible": true/false,
    "data_quality": 0-10,
    "valid_lightcurve_plot": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe the plot shape, transit feature, data scatter"
}
"""


def verify_exoplanet_transit(traj, env_info, task_info):
    """
    Verify exoplanet transit detection using hybrid programmatic + VLM checks.

    Scoring (100 points total):
    Programmatic (70 pts): measurement file, differential photometry, transit params
    VLM (30 pts): trajectory process (15), light curve content (10), cross-validation (5)

    Pass threshold: 60 points AND (measurement file exists OR transit params extracted)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    # Expected values
    expected_depth = metadata.get('expected_transit_depth_percent', 1.4)
    depth_tolerance = metadata.get('expected_transit_depth_tolerance_percent', 0.5)
    expected_duration = metadata.get('expected_duration_hours', 2.7)
    duration_tolerance = metadata.get('expected_duration_tolerance_hours', 1.0)
    expected_radius = metadata.get('expected_planet_radius_rjup', 1.79)
    radius_tolerance = metadata.get('expected_planet_radius_tolerance_rjup', 0.5)
    min_comparison_stars = metadata.get('minimum_comparison_stars', 2)

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Load result file from container
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
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: Measurement file exists with data (25 points)
    measurement_found = result.get('measurement_file_found', False)
    num_measurements = result.get('num_measurements', 0)
    has_time = result.get('has_time_column', False)
    has_flux = result.get('has_flux_column', False)

    if measurement_found and num_measurements >= 100 and has_time and has_flux:
        score += 25
        feedback_parts.append(f"Measurement file found ({num_measurements} data points)")
    elif measurement_found and num_measurements >= 50:
        score += 17
        feedback_parts.append(f"Measurement file incomplete ({num_measurements} points)")
    elif measurement_found and num_measurements > 0:
        score += 8
        feedback_parts.append(f"Measurement file sparse ({num_measurements} points)")
    elif num_measurements > 0:
        score += 4
        feedback_parts.append(f"Some measurements detected ({num_measurements})")
    else:
        feedback_parts.append("No measurement file found")

    # Criterion 2: Differential photometry with comparison stars (12 points)
    num_apertures = result.get('num_apertures', 0)
    num_comp_stars = result.get('num_comparison_stars', 0)

    if num_comp_stars >= min_comparison_stars:
        score += 12
        feedback_parts.append(f"Differential photometry with {num_comp_stars} comparison stars")
    elif num_comp_stars >= 1:
        score += 6
        feedback_parts.append(f"Only {num_comp_stars} comparison star (need {min_comparison_stars})")
    elif num_apertures >= 2:
        score += 4
        feedback_parts.append(f"{num_apertures} apertures but comparison stars not identified")
    else:
        feedback_parts.append("No differential photometry performed")

    # Criterion 3: Transit depth correct (15 points)
    depth_str = result.get('transit_depth_percent', '')
    depth_correct = False

    if depth_str:
        try:
            depth_val = float(depth_str)
            error = abs(depth_val - expected_depth)

            if error <= depth_tolerance:
                score += 15
                feedback_parts.append(f"Transit depth correct: {depth_val:.2f}%")
                depth_correct = True
            elif error <= depth_tolerance * 2:
                score += 9
                feedback_parts.append(f"Transit depth close: {depth_val:.2f}% (expected ~{expected_depth}%)")
                depth_correct = True
            elif error <= depth_tolerance * 3:
                score += 4
                feedback_parts.append(f"Transit depth approximate: {depth_val:.2f}%")
            else:
                feedback_parts.append(f"Transit depth wrong: {depth_val:.2f}% (expected ~{expected_depth}%)")
        except (ValueError, TypeError):
            feedback_parts.append("Transit depth could not be parsed")
    else:
        feedback_parts.append("Transit depth not measured")

    # Criterion 4: Transit duration correct (10 points)
    duration_str = result.get('duration_hours', '')
    duration_correct = False

    if duration_str:
        try:
            dur_val = float(duration_str)
            error = abs(dur_val - expected_duration)

            if error <= duration_tolerance:
                score += 10
                feedback_parts.append(f"Transit duration correct: {dur_val:.2f}h")
                duration_correct = True
            elif error <= duration_tolerance * 2:
                score += 5
                feedback_parts.append(f"Transit duration close: {dur_val:.2f}h (expected ~{expected_duration}h)")
                duration_correct = True
            else:
                feedback_parts.append(f"Transit duration wrong: {dur_val:.2f}h (expected ~{expected_duration}h)")
        except (ValueError, TypeError):
            feedback_parts.append("Transit duration could not be parsed")
    else:
        feedback_parts.append("Transit duration not measured")

    # Criterion 5: Mid-transit time reported (3 points)
    mid_str = result.get('mid_transit_bjd', '')

    if mid_str:
        try:
            mid_val = float(mid_str)
            if 2450000 < mid_val < 2470000:
                score += 3
                feedback_parts.append(f"Mid-transit time: BJD {mid_val:.4f}")
            else:
                feedback_parts.append(f"Mid-transit time unusual: {mid_val}")
        except (ValueError, TypeError):
            feedback_parts.append("Mid-transit time could not be parsed")
    else:
        feedback_parts.append("Mid-transit time not measured")

    # Criterion 6: Planet radius calculated (5 points)
    radius_str = result.get('planet_radius_rjup', '')

    if radius_str:
        try:
            radius_val = float(radius_str)
            error = abs(radius_val - expected_radius)

            if error <= radius_tolerance:
                score += 5
                feedback_parts.append(f"Planet radius correct: {radius_val:.2f} R_J")
            elif error <= radius_tolerance * 2:
                score += 3
                feedback_parts.append(f"Planet radius close: {radius_val:.2f} R_J (expected ~{expected_radius})")
            else:
                feedback_parts.append(f"Planet radius wrong: {radius_val:.2f} R_J")
        except (ValueError, TypeError):
            feedback_parts.append("Planet radius could not be parsed")
    else:
        feedback_parts.append("Planet radius not calculated")

    # ================================================================
    # VLM CHECKS (30 points total)
    #
    # Uses TRAJECTORY frames — captured by the framework, not from
    # inside the container. The trajectory is the independent record
    # of what actually happened on screen.
    #
    # Two checks:
    # A. Process verification (15 pts): sampled trajectory frames show
    #    the agent progressing through the workflow
    # B. Content verification (10 pts): final frame shows a valid
    #    light curve with transit dip
    # C. Cross-validation (5 pts): programmatic + visual agree
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_transit_visible = False

    # Get trajectory frames — these are framework-captured, not from container
    sampled_frames = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):

        # --- VLM Check A: Process Verification — 15 points ---
        # Send sampled trajectory frames to verify the agent went through
        # the expected workflow stages. This is the strongest VLM check
        # because it verifies the PROCESS, not just the end state.
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                lc_visible = process_result.get('light_curve_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    feedback_parts.append("VLM process: Full workflow progression confirmed")
                elif workflow_ok:
                    score += 10
                    feedback_parts.append("VLM process: Workflow completed (limited progression)")
                elif lc_visible:
                    score += 7
                    feedback_parts.append("VLM process: Light curve visible but workflow unclear")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient trajectory frames")

        # --- VLM Check B: Light Curve Content — 10 points ---
        # Analyze the final frame for transit dip and data quality.
        # This checks things programmatic checks cannot: visual shape
        # of the transit signal, data scatter, plot validity.
        if has_final:
            lc_result = _vlm_query(
                query_vlm, LIGHTCURVE_CONTENT_PROMPT, image=final_frame
            )
            details['vlm_lightcurve'] = lc_result

            if lc_result:
                if lc_result.get('transit_dip_visible'):
                    vlm_transit_visible = True
                    score += 5
                    feedback_parts.append("VLM content: Transit dip visible")
                else:
                    feedback_parts.append("VLM content: No transit dip visible")

                if lc_result.get('valid_lightcurve_plot'):
                    score += 3
                    feedback_parts.append("VLM content: Valid light curve plot")

                data_quality = lc_result.get('data_quality', 0)
                if isinstance(data_quality, (int, float)) and data_quality >= 5:
                    score += 2
                    feedback_parts.append(f"VLM content: Data quality {data_quality}/10")
            else:
                feedback_parts.append("VLM content check failed")
        else:
            feedback_parts.append("VLM content: No final frame available")

        # --- VLM Check C: Cross-validation — 5 points ---
        if depth_correct and vlm_transit_visible:
            score += 5
            feedback_parts.append("Cross-validated: programmatic depth + VLM transit agree")
            details['cross_validation'] = 'pass'
        elif depth_correct and not vlm_transit_visible:
            feedback_parts.append("Cross-validation mismatch: depth found but VLM sees no transit")
            details['cross_validation'] = 'mismatch'
        elif vlm_transit_visible and not depth_correct:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees transit but depth incorrect")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        # VLM not available — give partial credit if programmatic passed
        feedback_parts.append("VLM checks skipped (unavailable)")
        key_programmatic = (
            (measurement_found and num_measurements >= 50)
            or (depth_correct and duration_correct)
        )
        if key_programmatic:
            score += 15
            feedback_parts.append("Partial VLM credit (programmatic checks passed)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================

    key_work_done = (
        (measurement_found and num_measurements >= 50)
        or (depth_correct and duration_correct)
    )
    passed = score >= 60 and key_work_done

    if passed and score >= 85:
        feedback_parts.append("Excellent transit analysis")
    elif passed:
        feedback_parts.append("Transit detection successful")
    else:
        if not key_work_done:
            feedback_parts.append("FAIL: Photometry not completed or transit not detected")
        else:
            feedback_parts.append(f"FAIL: Score {score}/100 below threshold")

    details.update({
        "measurement_file_found": measurement_found,
        "num_measurements": num_measurements,
        "num_comparison_stars": num_comp_stars,
        "transit_depth": depth_str,
        "transit_duration": duration_str,
        "planet_radius": radius_str,
        "depth_correct": depth_correct,
        "duration_correct": duration_correct,
        "vlm_transit_visible": vlm_transit_visible,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
