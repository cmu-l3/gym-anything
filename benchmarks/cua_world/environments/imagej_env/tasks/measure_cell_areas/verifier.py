#!/usr/bin/env python3
"""
Verifier for Measure Cell Areas task in ImageJ/Fiji.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON:
  1. Results file exists with measurements (20 pts)
  2. Cell count within reasonable range (15 pts)
  3. Average area measured correctly (15 pts)
  4. Circularity measured (10 pts)
  5. Size range recorded (10 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  6. Process verification (15 pts): Agent progressed through workflow
     (image opened → blur/threshold → watershed → analyze particles → results)
  7. Content verification (10 pts): Final frame shows results with circularity
  8. Cross-validation (5 pts): Counts agree

Anti-gaming measures:
  - Require VLM confirmation for full points (no VLM = max 70 points)
  - Validate that results came from actual Fiji workflow
  - Check that windows_list shows expected state
  - Verify timestamp is reasonable

Pass threshold: 60 points AND cell count > 5
"""

import json
import tempfile
import os
import logging
from datetime import datetime, timedelta

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
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent performing cell area measurement in Fiji (ImageJ).

The images are sampled chronologically from the workflow.

For successful cell measurement, the agent should progress through:
1. FIJI OPEN — ImageJ toolbar visible
2. IMAGE LOADED — A fluorescence microscopy image (cells on dark background) visible
3. IMAGE PROCESSED — Gaussian blur applied, or threshold dialog visible
4. BINARY/WATERSHED — Image converted to binary, watershed applied (cells appear as separate white regions)
5. ANALYZE PARTICLES — Dialog for particle analysis visible
6. RESULTS — Results table with measurements visible

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress from image to results?
2. IMAGE_PROCESSED: Was image processing (blur, threshold) visible?
3. BINARY_VISIBLE: Was a binary (black and white) image visible at any point?
4. RESULTS_TABLE_VISIBLE: Is a Results table visible in later frames?
5. MEANINGFUL_PROGRESSION: Do frames show state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "image_processed": true/false,
    "binary_visible": true/false,
    "results_table_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe progression"
}
"""

RESULTS_CONTENT_PROMPT = """You are analyzing the final state of a cell measurement task in Fiji (ImageJ).

After cell analysis, the Results window should show:
- Multiple rows (one per cell)
- Columns including Area, possibly Circularity/Circ., Perimeter, etc.
- Numerical values in each cell

Assess:
1. RESULTS_VISIBLE: Is a Results table with data rows visible?
2. HAS_AREA_COLUMN: Can you see an "Area" column or area values?
3. HAS_CIRCULARITY: Can you see "Circ." or "Circularity" column?
4. ROW_COUNT: Estimate - "none"/"few" (<10)/"moderate" (10-50)/"many" (>50)
5. DATA_QUALITY: Rate completeness 0-10

Respond in JSON format:
{
    "results_visible": true/false,
    "has_area_column": true/false,
    "has_circularity": true/false,
    "row_count": "none/few/moderate/many",
    "data_quality": 0-10,
    "confidence": "low"/"medium"/"high",
    "observations": "describe visible results"
}
"""


def verify_measure_cell_areas(traj, env_info, task_info):
    """
    Verify cell area measurement using hybrid programmatic + VLM checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    # Expected values
    expected_count_min = metadata.get('expected_cell_count_min', 10)
    expected_count_max = metadata.get('expected_cell_count_max', 200)
    expected_avg_area_min = metadata.get('expected_avg_area_min', 200)
    expected_avg_area_max = metadata.get('expected_avg_area_max', 3000)
    expected_circ_min = metadata.get('expected_circularity_min', 0.5)
    expected_circ_max = metadata.get('expected_circularity_max', 1.0)

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
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
    gaming_penalty = 0
    gaming_warnings = []

    # Check 1: Result should have expected structure
    required_fields = ['cell_count', 'has_measurements', 'timestamp', 'windows_list']
    missing_fields = [f for f in required_fields if f not in result]
    if missing_fields:
        gaming_penalty += 20
        gaming_warnings.append(f"Missing expected fields: {missing_fields}")

    # Check 2: Windows list should contain evidence of Fiji being used
    windows_list = result.get('windows_list', '')
    if not any(keyword in windows_list.lower() for keyword in ['fiji', 'imagej', 'results', 'summary', '.tif', 'bbbc']):
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
            ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            now = datetime.now(ts.tzinfo) if ts.tzinfo else datetime.now()
            age = now - ts
            if age > timedelta(hours=1) or age < timedelta(seconds=-60):
                gaming_penalty += 10
                gaming_warnings.append(f"Suspicious timestamp age: {age}")
        except Exception:
            pass

    if gaming_warnings:
        logger.warning(f"Anti-gaming checks triggered: {gaming_warnings}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: Results file exists (20 points)
    results_found = result.get('results_file_found', False)
    has_measurements = result.get('has_measurements', False)
    results_window = result.get('results_window_visible', False)

    if results_found and has_measurements:
        score += 20
        feedback_parts.append("Results file found with measurements")
    elif results_window and not results_found:
        score += 12
        feedback_parts.append("Results window visible but file not saved")
    elif results_window:
        score += 8
        feedback_parts.append("Results window visible")
    else:
        feedback_parts.append("No results found")

    # Criterion 2: Cell count (15 points)
    cell_count = result.get('cell_count', 0)
    count_correct = False

    if cell_count > 0:
        if expected_count_min <= cell_count <= expected_count_max:
            score += 15
            feedback_parts.append(f"Cell count reasonable: {cell_count}")
            count_correct = True
        elif cell_count > 5:
            score += 8
            feedback_parts.append(f"Cell count: {cell_count} (expected {expected_count_min}-{expected_count_max})")
            count_correct = True
        else:
            feedback_parts.append(f"Too few cells: {cell_count}")
    else:
        feedback_parts.append("No cells counted")

    # Criterion 3: Average area (15 points)
    avg_area = result.get('avg_area', 0)
    area_correct = False

    if avg_area > 0:
        if expected_avg_area_min <= avg_area <= expected_avg_area_max:
            score += 15
            feedback_parts.append(f"Average area correct: {avg_area:.1f} px²")
            area_correct = True
        elif avg_area > 50:
            score += 8
            feedback_parts.append(f"Average area: {avg_area:.1f} px²")
        else:
            feedback_parts.append(f"Average area too small: {avg_area}")
    else:
        feedback_parts.append("No average area measured")

    # Criterion 4: Circularity measured (10 points)
    has_circularity = result.get('has_circularity', False)
    avg_circularity = result.get('avg_circularity', 0)

    if has_circularity and avg_circularity > 0:
        if expected_circ_min <= avg_circularity <= expected_circ_max:
            score += 10
            feedback_parts.append(f"Circularity measured: {avg_circularity:.3f}")
        else:
            score += 5
            feedback_parts.append(f"Circularity: {avg_circularity:.3f} (expected {expected_circ_min}-{expected_circ_max})")
    else:
        feedback_parts.append("Circularity not measured")

    # Criterion 5: Size range (10 points)
    min_area = result.get('min_area', 0)
    max_area = result.get('max_area', 0)

    if min_area > 0 and max_area > 0 and max_area > min_area:
        score += 10
        feedback_parts.append(f"Size range: {min_area:.1f} - {max_area:.1f} px²")
    elif min_area > 0 or max_area > 0:
        score += 5
        feedback_parts.append("Partial size range")
    else:
        feedback_parts.append("No size range")

    # ================================================================
    # VLM CHECKS (30 points)
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

        # Process verification (15 pts)
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                binary_vis = process_result.get('binary_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    feedback_parts.append("VLM process: Full workflow confirmed")
                elif workflow_ok:
                    score += 10
                    feedback_parts.append("VLM process: Workflow completed")
                elif binary_vis:
                    score += 7
                    feedback_parts.append("VLM process: Processing visible")
                else:
                    feedback_parts.append("VLM process: Workflow unclear")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

        # Content verification (10 pts)
        if has_final:
            content_result = _vlm_query(
                query_vlm, RESULTS_CONTENT_PROMPT, image=final_frame
            )
            details['vlm_results'] = content_result

            if content_result:
                if content_result.get('results_visible'):
                    vlm_results_visible = True
                    score += 4
                    feedback_parts.append("VLM content: Results visible")

                if content_result.get('has_area_column'):
                    score += 3
                    feedback_parts.append("VLM content: Area column visible")

                if content_result.get('has_circularity'):
                    score += 3
                    feedback_parts.append("VLM content: Circularity visible")
            else:
                feedback_parts.append("VLM content check failed")
        else:
            feedback_parts.append("VLM content: No final frame")

        # Cross-validation (5 pts)
        if count_correct and vlm_results_visible:
            score += 5
            feedback_parts.append("Cross-validated")
            details['cross_validation'] = 'pass'
        elif count_correct and not vlm_results_visible:
            details['cross_validation'] = 'mismatch'
        elif vlm_results_visible and not count_correct:
            score += 2
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        feedback_parts.append("VLM checks skipped")
        if has_measurements and cell_count > 5:
            score += 15
            feedback_parts.append("Partial VLM credit")

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

    key_work_done = cell_count > 5 and has_measurements
    passed = score >= 60 and key_work_done

    if passed and score >= 85:
        feedback_parts.append("Excellent cell analysis")
    elif passed:
        feedback_parts.append("Cell analysis successful")
    else:
        if not key_work_done:
            feedback_parts.append("FAIL: Cell analysis not completed")
        else:
            feedback_parts.append(f"FAIL: Score {score}/100")

    details.update({
        "results_file_found": results_found,
        "has_measurements": has_measurements,
        "cell_count": cell_count,
        "avg_area": avg_area,
        "min_area": min_area,
        "max_area": max_area,
        "avg_circularity": avg_circularity,
        "has_circularity": has_circularity,
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
