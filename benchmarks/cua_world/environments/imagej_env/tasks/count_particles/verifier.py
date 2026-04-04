#!/usr/bin/env python3
"""
Verifier for Particle Counting task in ImageJ/Fiji.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON:
  1. Results file exists with measurements (25 pts)
  2. Particle count within expected range (20 pts)
  3. Average area measured correctly (15 pts)
  4. Size range (min/max) recorded (10 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  5. Process verification (15 pts): Agent progressed through expected workflow
     (image opened → threshold applied → particle analysis → results visible)
  6. Content verification (10 pts): Final frame shows results table with data
  7. Cross-validation (5 pts): Programmatic count agrees with visible results

Anti-gaming measures:
  - Require VLM confirmation for full points (no VLM = max 70 points)
  - Validate that results came from actual Fiji workflow
  - Check that windows_list shows expected state
  - Verify timestamp is reasonable

Pass threshold: 60 points AND particle count is reasonable
"""

import json
import tempfile
import os
import logging
from datetime import datetime, timedelta

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


# VLM Prompts
TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent performing particle analysis in Fiji (ImageJ).

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful particle analysis, the agent should progress through these stages:
1. FIJI OPEN — The ImageJ/Fiji toolbar window is visible
2. IMAGE LOADED — A grayscale microscopy image (blobs) is visible in an image window
3. THRESHOLD APPLIED — Image converted to binary (black and white), may show Threshold dialog
4. PARTICLE ANALYSIS — Analyze Particles dialog may be visible
5. RESULTS — A Results table window with rows of measurements is visible

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress from image loading to results?
2. IMAGE_VISIBLE: At any point, is a grayscale or binary image visible?
3. RESULTS_TABLE_VISIBLE: Is a Results table window with numerical data visible?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "image_visible": true/false,
    "results_table_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression you see"
}
"""

RESULTS_CONTENT_PROMPT = """You are analyzing the final state of a particle counting task in Fiji (ImageJ).

This is a desktop screenshot. After running Analyze Particles, the Results window
should show a table with columns like "Area", "Mean", etc., and multiple rows.

Focus on any visible Results or Summary window and assess:

1. RESULTS_VISIBLE: Is there a Results table window with numerical data rows?
2. PARTICLE_COUNT_VISIBLE: Can you see a count or number of particles listed?
3. MEASUREMENTS_PRESENT: Are there measurement values (Area, Mean, etc.) visible?
4. DATA_QUALITY: Rate the completeness (0-10).
   Good: Multiple rows, visible column headers, numeric values.
   Bad: Empty table, no results, just dialog windows.

Respond in JSON format:
{
    "results_visible": true/false,
    "particle_count_visible": true/false,
    "measurements_present": true/false,
    "data_quality": 0-10,
    "approximate_row_count": "none/few/many",
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the results"
}
"""


def verify_count_particles(traj, env_info, task_info):
    """
    Verify particle counting using hybrid programmatic + VLM checks.

    Scoring (100 points total):
    Programmatic (70 pts): results file, particle count, area stats
    VLM (30 pts): trajectory process (15), results content (10), cross-validation (5)

    Pass threshold: 60 points AND particle count is reasonable (>10)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    # Expected values from task metadata
    expected_count_min = metadata.get('expected_particle_count_min', 50)
    expected_count_max = metadata.get('expected_particle_count_max', 80)
    expected_avg_area_min = metadata.get('expected_avg_area_min', 100)
    expected_avg_area_max = metadata.get('expected_avg_area_max', 500)

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
    # ANTI-GAMING VALIDATION
    # ================================================================
    # Check that the result appears to be from legitimate export script execution

    gaming_penalty = 0
    gaming_warnings = []

    # Check 1: Result should have expected structure from export script
    required_fields = ['particle_count', 'has_measurements', 'timestamp', 'windows_list']
    missing_fields = [f for f in required_fields if f not in result]
    if missing_fields:
        gaming_penalty += 20
        gaming_warnings.append(f"Missing expected fields: {missing_fields}")

    # Check 2: Windows list should contain evidence of Fiji being used
    windows_list = result.get('windows_list', '')
    if not any(keyword in windows_list.lower() for keyword in ['fiji', 'imagej', 'results', 'summary', 'blobs']):
        gaming_penalty += 15
        gaming_warnings.append("No Fiji/ImageJ windows detected in window list")

    # Check 3: If results file found, the path should be reasonable
    results_path = result.get('results_file_path', '')
    summary_path = result.get('summary_file_path', '')
    if result.get('results_file_found') or result.get('summary_file_found'):
        valid_paths = ['/home/ga', '/tmp', 'ImageJ_Data', 'results']
        path_ok = any(vp in results_path or vp in summary_path for vp in valid_paths)
        if not path_ok and (results_path or summary_path):
            gaming_penalty += 10
            gaming_warnings.append(f"Unexpected results path: {results_path or summary_path}")

    # Check 4: Timestamp should be recent (within last hour)
    timestamp_str = result.get('timestamp', '')
    if timestamp_str:
        try:
            # Parse ISO format timestamp
            ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            now = datetime.now(ts.tzinfo) if ts.tzinfo else datetime.now()
            age = now - ts
            if age > timedelta(hours=1) or age < timedelta(seconds=-60):
                gaming_penalty += 10
                gaming_warnings.append(f"Suspicious timestamp age: {age}")
        except Exception:
            pass  # Don't penalize for timestamp parse errors

    if gaming_warnings:
        logger.warning(f"Anti-gaming checks triggered: {gaming_warnings}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: Results file exists with measurements (25 points)
    # Accept either Results file or Summary file as valid
    results_found = result.get('results_file_found', False) or result.get('summary_file_found', False)
    has_measurements = result.get('has_measurements', False)
    results_window = result.get('results_window_visible', False) or result.get('summary_window_visible', False)

    if results_found and has_measurements:
        score += 25
        feedback_parts.append("Results file found with measurements")
    elif results_window and not results_found:
        score += 15
        feedback_parts.append("Results window visible but file not saved")
    elif results_window:
        score += 10
        feedback_parts.append("Results window visible")
    else:
        feedback_parts.append("No results found")

    # Criterion 2: Particle count within expected range (20 points)
    particle_count = result.get('particle_count', 0)
    count_correct = False

    if particle_count > 0:
        if expected_count_min <= particle_count <= expected_count_max:
            score += 20
            feedback_parts.append(f"Particle count correct: {particle_count} (expected {expected_count_min}-{expected_count_max})")
            count_correct = True
        elif particle_count > 10:
            # Some particles found but not exact range
            error_margin = min(
                abs(particle_count - expected_count_min),
                abs(particle_count - expected_count_max)
            )
            if error_margin <= 20:
                score += 12
                feedback_parts.append(f"Particle count close: {particle_count} (expected {expected_count_min}-{expected_count_max})")
                count_correct = True
            else:
                score += 6
                feedback_parts.append(f"Particle count off: {particle_count} (expected {expected_count_min}-{expected_count_max})")
        else:
            feedback_parts.append(f"Too few particles: {particle_count}")
    else:
        feedback_parts.append("No particles counted")

    # Criterion 3: Average area measured correctly (15 points)
    avg_area = result.get('avg_area', 0)
    area_correct = False

    if avg_area > 0:
        if expected_avg_area_min <= avg_area <= expected_avg_area_max:
            score += 15
            feedback_parts.append(f"Average area correct: {avg_area:.1f} px²")
            area_correct = True
        elif avg_area > 10:
            # Some area measured
            score += 8
            feedback_parts.append(f"Average area: {avg_area:.1f} px² (expected {expected_avg_area_min}-{expected_avg_area_max})")
        else:
            feedback_parts.append(f"Average area too small: {avg_area}")
    else:
        feedback_parts.append("No average area measured")

    # Criterion 4: Size range recorded (10 points)
    min_area = result.get('min_area', 0)
    max_area = result.get('max_area', 0)

    if min_area > 0 and max_area > 0 and max_area > min_area:
        score += 10
        feedback_parts.append(f"Size range: {min_area:.1f} - {max_area:.1f} px²")
    elif min_area > 0 or max_area > 0:
        score += 5
        feedback_parts.append("Partial size range recorded")
    else:
        feedback_parts.append("No size range recorded")

    # ================================================================
    # VLM CHECKS (30 points total)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_results_visible = False

    sampled_frames = sample_frames(traj, num_samples=5) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):

        # VLM Check A: Process Verification (15 points)
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                results_vis = process_result.get('results_table_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    feedback_parts.append("VLM process: Full workflow confirmed")
                elif workflow_ok:
                    score += 10
                    feedback_parts.append("VLM process: Workflow completed")
                elif results_vis:
                    score += 7
                    feedback_parts.append("VLM process: Results visible but workflow unclear")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient trajectory frames")

        # VLM Check B: Results Content (10 points)
        if has_final:
            content_result = _vlm_query(
                query_vlm, RESULTS_CONTENT_PROMPT, image=final_frame
            )
            details['vlm_results'] = content_result

            if content_result:
                if content_result.get('results_visible'):
                    vlm_results_visible = True
                    score += 5
                    feedback_parts.append("VLM content: Results table visible")
                else:
                    feedback_parts.append("VLM content: No results table visible")

                if content_result.get('measurements_present'):
                    score += 3
                    feedback_parts.append("VLM content: Measurements visible")

                data_quality = content_result.get('data_quality', 0)
                if isinstance(data_quality, (int, float)) and data_quality >= 5:
                    score += 2
                    feedback_parts.append(f"VLM content: Data quality {data_quality}/10")
            else:
                feedback_parts.append("VLM content check failed")
        else:
            feedback_parts.append("VLM content: No final frame available")

        # VLM Check C: Cross-validation (5 points)
        if count_correct and vlm_results_visible:
            score += 5
            feedback_parts.append("Cross-validated: programmatic count + VLM results agree")
            details['cross_validation'] = 'pass'
        elif count_correct and not vlm_results_visible:
            feedback_parts.append("Cross-validation mismatch: count OK but VLM sees no results")
            details['cross_validation'] = 'mismatch'
        elif vlm_results_visible and not count_correct:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees results but count incorrect")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        # VLM not available
        feedback_parts.append("VLM checks skipped (unavailable)")
        if has_measurements and particle_count > 10:
            score += 15
            feedback_parts.append("Partial VLM credit (programmatic checks passed)")

    # ================================================================
    # APPLY GAMING PENALTY
    # ================================================================
    if gaming_penalty > 0:
        score = max(0, score - gaming_penalty)
        feedback_parts.append(f"Gaming penalty: -{gaming_penalty} ({', '.join(gaming_warnings)})")
        details['gaming_penalty'] = gaming_penalty
        details['gaming_warnings'] = gaming_warnings

    # ================================================================
    # PASS CRITERIA
    # ================================================================

    key_work_done = particle_count > 10 and has_measurements
    passed = score >= 60 and key_work_done

    if passed and score >= 85:
        feedback_parts.append("Excellent particle analysis")
    elif passed:
        feedback_parts.append("Particle analysis successful")
    else:
        if not key_work_done:
            feedback_parts.append("FAIL: Particle analysis not completed")
        else:
            feedback_parts.append(f"FAIL: Score {score}/100 below threshold")

    details.update({
        "results_file_found": results_found,
        "has_measurements": has_measurements,
        "particle_count": particle_count,
        "avg_area": avg_area,
        "min_area": min_area,
        "max_area": max_area,
        "count_correct": count_correct,
        "area_correct": area_correct,
        "vlm_results_visible": vlm_results_visible,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
