#!/usr/bin/env python3
"""
Verifier for measure_tumor_diameter task.

VERIFICATION CRITERIA (Total: 100 points):
1. Markup Created (20 pts) - A line markup node exists in the MRML scene
2. Measurement Recorded (15 pts) - The line has a valid length value > 0
3. Reasonable Range (15 pts) - Measurement is between 10-150mm
4. Accuracy (25 pts) - Measured value matches ground truth ±20%
5. Screenshot Saved (15 pts) - Valid screenshot exists with measurement visible
6. VLM Visual Confirmation (10 pts) - VLM confirms line is placed on tumor region

Pass threshold: 55 points (Markup Created + Measurement Recorded + Reasonable Range)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measure_tumor_diameter(traj, env_info, task_info):
    """
    Verify the tumor diameter measurement task completion.
    
    Uses multi-criteria scoring with:
    - Programmatic checks for markup existence and measurement values
    - Ground truth comparison for accuracy
    - VLM trajectory analysis for visual verification
    
    Returns:
        dict with 'passed', 'score', 'feedback', and 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    min_plausible = metadata.get('min_plausible_diameter_mm', 10)
    max_plausible = metadata.get('max_plausible_diameter_mm', 150)
    accuracy_tolerance = metadata.get('accuracy_tolerance_percent', 20)
    min_screenshot_kb = metadata.get('min_screenshot_size_kb', 50)
    pass_threshold = metadata.get('pass_threshold', 55)
    
    weights = metadata.get('scoring_weights', {})
    w_markup = weights.get('markup_created', 20)
    w_measurement = weights.get('measurement_recorded', 15)
    w_range = weights.get('reasonable_range', 15)
    w_accuracy = weights.get('accuracy', 25)
    w_screenshot = weights.get('screenshot_saved', 15)
    w_vlm = weights.get('visual_confirmation', 10)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tumor_measurement_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check basic requirements
    if not result.get('slicer_running', False):
        feedback_parts.append("✗ Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 1: Markup Created (20 points)
    # ================================================================
    markup_exists = result.get('markup_exists', False)
    num_line_nodes = result.get('num_line_nodes', 0)
    
    if markup_exists:
        score += w_markup
        feedback_parts.append(f"✓ Line markup created ({num_line_nodes} node(s)) [{w_markup} pts]")
        details['markup_created'] = True
    else:
        feedback_parts.append(f"✗ No line markup found [0/{w_markup} pts]")
        details['markup_created'] = False
        # Without markup, limited verification possible
        feedback_parts.append("\nNo measurement markup was created - cannot verify measurement accuracy.")
        return {
            "passed": False,
            "score": score,
            "feedback": "\n".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Measurement Recorded (15 points)
    # ================================================================
    measurement_mm = float(result.get('measurement_mm', 0))
    details['measurement_mm'] = measurement_mm
    
    if measurement_mm > 0:
        score += w_measurement
        feedback_parts.append(f"✓ Measurement recorded: {measurement_mm:.1f} mm [{w_measurement} pts]")
        details['measurement_recorded'] = True
    else:
        feedback_parts.append(f"✗ No valid measurement value [0/{w_measurement} pts]")
        details['measurement_recorded'] = False
    
    # ================================================================
    # CRITERION 3: Reasonable Range (15 points)
    # ================================================================
    in_range = min_plausible <= measurement_mm <= max_plausible
    details['in_plausible_range'] = in_range
    details['plausible_range'] = [min_plausible, max_plausible]
    
    if in_range:
        score += w_range
        feedback_parts.append(f"✓ Measurement in plausible range [{min_plausible}-{max_plausible}mm] [{w_range} pts]")
    elif measurement_mm > 0:
        feedback_parts.append(f"✗ Measurement {measurement_mm:.1f}mm outside plausible range [0/{w_range} pts]")
    else:
        feedback_parts.append(f"✗ No measurement to check range [0/{w_range} pts]")
    
    # ================================================================
    # CRITERION 4: Accuracy within tolerance of ground truth (25 points)
    # ================================================================
    gt_diameter = float(result.get('ground_truth_diameter_mm', 0))
    gt_min = float(result.get('acceptable_min_mm', 0))
    gt_max = float(result.get('acceptable_max_mm', 0))
    gt_available = result.get('ground_truth_available', False)
    
    details['ground_truth'] = {
        'diameter_mm': gt_diameter,
        'min_acceptable_mm': gt_min,
        'max_acceptable_mm': gt_max,
        'available': gt_available
    }
    
    accuracy_score = 0
    if gt_available and gt_diameter > 0 and measurement_mm > 0:
        if gt_min <= measurement_mm <= gt_max:
            accuracy_score = w_accuracy
            error_pct = abs(measurement_mm - gt_diameter) / gt_diameter * 100 if gt_diameter > 0 else 0
            feedback_parts.append(
                f"✓ Measurement accurate: {measurement_mm:.1f}mm vs GT {gt_diameter:.1f}mm "
                f"({error_pct:.0f}% error, within ±{accuracy_tolerance}%) [{w_accuracy} pts]"
            )
            details['accuracy_check'] = 'passed'
        else:
            error_pct = abs(measurement_mm - gt_diameter) / gt_diameter * 100 if gt_diameter > 0 else 100
            feedback_parts.append(
                f"✗ Measurement inaccurate: {measurement_mm:.1f}mm vs GT {gt_diameter:.1f}mm "
                f"({error_pct:.0f}% error, need ≤{accuracy_tolerance}%) [0/{w_accuracy} pts]"
            )
            details['accuracy_check'] = 'failed'
            details['error_percent'] = error_pct
            
            # Partial credit for being close (within 30%)
            if error_pct <= 30:
                partial = int(w_accuracy * 0.4)
                accuracy_score = partial
                feedback_parts.append(f"  (Partial credit for being within 30%: +{partial} pts)")
    else:
        feedback_parts.append(f"△ Ground truth not available for accuracy check [0/{w_accuracy} pts]")
        details['accuracy_check'] = 'skipped'
        # Give benefit of doubt if measurement is in range
        if in_range and measurement_mm > 0:
            partial = int(w_accuracy * 0.3)
            accuracy_score = partial
            feedback_parts.append(f"  (Partial credit for plausible measurement: +{partial} pts)")
    
    score += accuracy_score
    
    # ================================================================
    # CRITERION 5: Screenshot Saved (15 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_bytes', 0) / 1024  # Convert to KB
    screenshot_during_task = result.get('screenshot_created_during_task', False)
    
    details['screenshot'] = {
        'exists': screenshot_exists,
        'size_kb': screenshot_size,
        'created_during_task': screenshot_during_task
    }
    
    screenshot_score = 0
    if screenshot_exists and screenshot_during_task and screenshot_size >= min_screenshot_kb:
        screenshot_score = w_screenshot
        feedback_parts.append(f"✓ Screenshot saved ({screenshot_size:.0f} KB) [{w_screenshot} pts]")
    elif screenshot_exists and screenshot_size >= min_screenshot_kb / 2:
        screenshot_score = int(w_screenshot * 0.5)
        if not screenshot_during_task:
            feedback_parts.append(f"△ Screenshot exists but may be pre-existing [{screenshot_score}/{w_screenshot} pts]")
        else:
            feedback_parts.append(f"△ Screenshot small ({screenshot_size:.0f} KB) [{screenshot_score}/{w_screenshot} pts]")
    elif screenshot_exists:
        screenshot_score = int(w_screenshot * 0.3)
        feedback_parts.append(f"△ Screenshot exists but too small ({screenshot_size:.0f} KB) [{screenshot_score}/{w_screenshot} pts]")
    else:
        feedback_parts.append(f"✗ No screenshot saved [0/{w_screenshot} pts]")
    
    score += screenshot_score
    
    # ================================================================
    # CRITERION 6: VLM Visual Confirmation (10 points)
    # ================================================================
    vlm_score = 0
    
    # Try to get trajectory frames for VLM verification
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Import VLM utilities if available
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.

The task was to measure the maximum diameter of a brain tumor on FLAIR MRI.

Look for:
1. Is there a brain MRI scan visible (grayscale brain image)?
2. Is there a LINE or RULER annotation visible (measurement tool)?
3. Does the line appear to span a BRIGHT WHITE region (the tumor on FLAIR)?
4. Are measurement values visible anywhere?

Respond in JSON:
{
    "brain_mri_visible": true/false,
    "measurement_line_visible": true/false,
    "line_on_bright_region": true/false,
    "measurement_value_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_analysis'] = parsed
                    
                    brain_visible = parsed.get('brain_mri_visible', False)
                    line_visible = parsed.get('measurement_line_visible', False)
                    line_on_tumor = parsed.get('line_on_bright_region', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    if line_visible and line_on_tumor:
                        vlm_score = w_vlm
                        feedback_parts.append(f"✓ VLM confirms measurement on tumor [{w_vlm} pts]")
                    elif line_visible:
                        vlm_score = int(w_vlm * 0.5)
                        feedback_parts.append(f"△ VLM sees line but unclear if on tumor [{vlm_score}/{w_vlm} pts]")
                    elif brain_visible:
                        vlm_score = int(w_vlm * 0.2)
                        feedback_parts.append(f"△ VLM sees brain but no clear measurement [{vlm_score}/{w_vlm} pts]")
                    else:
                        feedback_parts.append(f"✗ VLM could not verify measurement [0/{w_vlm} pts]")
                else:
                    feedback_parts.append(f"△ VLM verification inconclusive [0/{w_vlm} pts]")
                    
        except ImportError:
            # VLM utilities not available, use heuristic
            logger.info("VLM utilities not available, using heuristic check")
            if markup_exists and measurement_mm > 0 and in_range:
                vlm_score = int(w_vlm * 0.5)
                feedback_parts.append(f"△ VLM not available, heuristic check [{vlm_score}/{w_vlm} pts]")
            else:
                feedback_parts.append(f"△ VLM not available [0/{w_vlm} pts]")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"△ VLM verification error [0/{w_vlm} pts]")
    else:
        # No VLM available - use heuristic based on other criteria
        if markup_exists and measurement_mm > 0 and in_range:
            vlm_score = int(w_vlm * 0.5)
            feedback_parts.append(f"△ VLM not available, heuristic pass [{vlm_score}/{w_vlm} pts]")
        else:
            feedback_parts.append(f"△ VLM not available [0/{w_vlm} pts]")
    
    score += vlm_score
    
    # ================================================================
    # Final evaluation
    # ================================================================
    details['final_score'] = score
    details['max_score'] = w_markup + w_measurement + w_range + w_accuracy + w_screenshot + w_vlm
    details['pass_threshold'] = pass_threshold
    
    # Key criteria for passing
    key_criteria_met = (
        details.get('markup_created', False) and
        details.get('measurement_recorded', False) and
        details.get('in_plausible_range', False)
    )
    
    passed = score >= pass_threshold and key_criteria_met
    
    feedback_parts.append("")
    feedback_parts.append(f"{'='*50}")
    feedback_parts.append(f"Total Score: {score}/100")
    feedback_parts.append(f"Pass Threshold: {pass_threshold}")
    feedback_parts.append(f"Key Criteria Met: {key_criteria_met}")
    
    if passed:
        feedback_parts.append(f"\n✓ TASK PASSED")
    else:
        if not key_criteria_met:
            feedback_parts.append(f"\n✗ TASK FAILED - Key criteria not met (need markup + measurement + valid range)")
        else:
            feedback_parts.append(f"\n✗ TASK FAILED - Score below threshold")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }