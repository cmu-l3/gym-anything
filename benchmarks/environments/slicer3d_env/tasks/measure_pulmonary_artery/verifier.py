#!/usr/bin/env python3
"""
Verifier for measure_pulmonary_artery@1 task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points):
  1. Measurement file exists (20 points)
  2. Valid measurement value in range 15-45mm (25 points)
  3. Markup line exists in Slicer scene (15 points)
  4. File created during task session (10 points)

VLM checks (30 points):
  5. Trajectory shows progression (15 points): Agent navigated slices and placed measurement
  6. Visual confirmation (15 points): Final state shows measurement on vascular structure

Pass threshold: 60 points AND (measurement file exists OR markup exists)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measure_pulmonary_artery(traj, env_info, task_info):
    """
    Verify pulmonary artery measurement task completion.
    
    Uses multiple independent signals to prevent gaming.
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
    valid_range = metadata.get('valid_range_mm', {"min": 15, "max": 45})
    normal_range = metadata.get('normal_range_mm', {"min": 20, "max": 29})
    enlarged_threshold = metadata.get('enlarged_threshold_mm', 29)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('measurement_file_exists', 20)
    w_valid_value = weights.get('valid_measurement_value', 25)
    w_markup = weights.get('markup_exists', 15)
    w_created_during = weights.get('file_created_during_task', 10)
    w_vlm_visual = weights.get('vlm_visual_confirmation', 15)
    w_clinical = weights.get('clinical_interpretation', 15)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/pa_measurement_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
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
    
    # ================================================================
    # Try to copy the actual measurement file for additional validation
    # ================================================================
    measurement_data = {}
    temp_measurement = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/home/ga/Documents/SlicerData/Exports/pa_measurement.json", temp_measurement.name)
        with open(temp_measurement.name, 'r') as f:
            measurement_data = json.load(f)
        details['measurement_file_content'] = measurement_data
    except Exception as e:
        logger.info(f"Could not read measurement file directly: {e}")
    finally:
        if os.path.exists(temp_measurement.name):
            os.unlink(temp_measurement.name)
    
    # ================================================================
    # CRITERION 1: Measurement file exists (20 points)
    # ================================================================
    file_exists = result.get('measurement_file_exists', False) or bool(measurement_data)
    
    if file_exists:
        score += w_file_exists
        feedback_parts.append(f"✓ Measurement file created (+{w_file_exists})")
    else:
        feedback_parts.append("✗ Measurement file not found")
    
    details['file_exists'] = file_exists
    
    # ================================================================
    # CRITERION 2: Valid measurement value (25 points)
    # ================================================================
    measurement_value = result.get('measurement_value_mm')
    
    # Also check direct measurement file
    if not measurement_value and measurement_data:
        for key in ['diameter_mm', 'diameter', 'value', 'measurement', 'pa_diameter']:
            if key in measurement_data and measurement_data[key] is not None:
                try:
                    measurement_value = float(measurement_data[key])
                    break
                except (ValueError, TypeError):
                    continue
    
    value_valid = False
    if measurement_value is not None:
        try:
            mv = float(measurement_value)
            min_val = valid_range.get('min', 15)
            max_val = valid_range.get('max', 45)
            
            if min_val <= mv <= max_val:
                value_valid = True
                score += w_valid_value
                feedback_parts.append(f"✓ Valid measurement: {mv:.1f}mm (+{w_valid_value})")
            else:
                feedback_parts.append(f"✗ Measurement {mv:.1f}mm outside valid range ({min_val}-{max_val}mm)")
        except (ValueError, TypeError):
            feedback_parts.append("✗ Invalid measurement value format")
    else:
        feedback_parts.append("✗ No measurement value found")
    
    details['measurement_value_mm'] = measurement_value
    details['value_valid'] = value_valid
    
    # ================================================================
    # CRITERION 3: Markup exists in Slicer (15 points)
    # ================================================================
    markup_exists = result.get('markup_exists', False)
    markup_length = result.get('markup_length_mm')
    
    if markup_exists:
        score += w_markup
        if markup_length:
            feedback_parts.append(f"✓ Ruler markup created ({markup_length:.1f}mm) (+{w_markup})")
        else:
            feedback_parts.append(f"✓ Ruler markup created (+{w_markup})")
    else:
        # Partial credit if file exists but no markup detected
        if file_exists and value_valid:
            partial = w_markup // 2
            score += partial
            feedback_parts.append(f"~ Markup not detected but measurement exists (+{partial})")
        else:
            feedback_parts.append("✗ No ruler markup found in scene")
    
    details['markup_exists'] = markup_exists
    details['markup_length_mm'] = markup_length
    
    # ================================================================
    # CRITERION 4: File created during task (10 points) - anti-gaming
    # ================================================================
    created_during = result.get('file_created_during_task', False)
    
    if created_during:
        score += w_created_during
        feedback_parts.append(f"✓ File created during task session (+{w_created_during})")
    elif file_exists:
        feedback_parts.append("⚠ File may have existed before task")
    
    details['created_during_task'] = created_during
    
    # ================================================================
    # CRITERION 5 & 6: VLM verification using trajectory (30 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    # Check if VLM judge is available
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            vlm_score, vlm_feedback = _verify_with_vlm(traj, copy_from_env, query_vlm)
            score += vlm_score
            feedback_parts.append(vlm_feedback)
            details['vlm_score'] = vlm_score
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"~ VLM verification skipped: {e}")
            details['vlm_error'] = str(e)
    else:
        # Award partial points if no VLM but other criteria passed
        if value_valid and (markup_exists or created_during):
            partial_vlm = (w_vlm_visual + w_clinical) // 2
            score += partial_vlm
            feedback_parts.append(f"~ VLM not available, partial credit (+{partial_vlm})")
            details['vlm_score'] = partial_vlm
        else:
            feedback_parts.append("~ VLM verification not available")
    
    # ================================================================
    # CRITERION 6: Clinical interpretation (bonus if correct)
    # ================================================================
    if value_valid and measurement_value:
        try:
            mv = float(measurement_value)
            reported_interp = result.get('clinical_interpretation', '')
            
            # Determine expected interpretation
            if mv <= 25:
                expected_interp = 'normal'
            elif mv <= 29:
                expected_interp = 'borderline'
            else:
                expected_interp = 'enlarged'
            
            # Check measurement file for interpretation
            file_interp = ''
            if measurement_data:
                file_interp = measurement_data.get('clinical_interpretation', '')
            
            # Award points if interpretation matches
            if reported_interp == expected_interp or file_interp == expected_interp:
                if vlm_score == 0:  # Only if not already scored via VLM
                    score += w_clinical // 2
                    feedback_parts.append(f"✓ Correct interpretation: {expected_interp} (+{w_clinical // 2})")
            
            details['expected_interpretation'] = expected_interp
            details['reported_interpretation'] = reported_interp or file_interp
            
        except (ValueError, TypeError):
            pass
    
    # ================================================================
    # Calculate final result
    # ================================================================
    max_score = w_file_exists + w_valid_value + w_markup + w_created_during + w_vlm_visual + w_clinical
    
    # Key criteria for passing
    key_criteria_met = file_exists and (value_valid or markup_exists)
    
    # Pass threshold
    pass_threshold = 60
    passed = (score >= pass_threshold) and key_criteria_met
    
    # Compile feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n--- Score: {score}/{max_score} (threshold: {pass_threshold}) ---"
    feedback += f"\n{'PASSED' if passed else 'FAILED'}"
    
    if not passed and not key_criteria_met:
        feedback += "\nReason: Key criteria not met (need valid measurement file OR markup)"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def _verify_with_vlm(traj, copy_from_env, query_vlm):
    """
    Use VLM to verify task completion using trajectory frames.
    
    Returns (score, feedback_string)
    """
    total_vlm_score = 0
    vlm_feedback_parts = []
    
    # ================================================================
    # Sample trajectory frames (NOT just final screenshot)
    # ================================================================
    trajectory_images = []
    
    # Get trajectory frames if available
    if isinstance(traj, dict):
        frames = traj.get('frames', [])
        screenshots = traj.get('screenshots', [])
        
        # Sample frames across the trajectory
        source = frames if frames else screenshots
        if source:
            n_frames = len(source)
            # Sample 5 frames evenly distributed
            if n_frames >= 5:
                indices = [0, n_frames // 4, n_frames // 2, 3 * n_frames // 4, n_frames - 1]
            else:
                indices = list(range(n_frames))
            
            for idx in indices:
                if idx < len(source):
                    frame = source[idx]
                    if isinstance(frame, str) and os.path.exists(frame):
                        trajectory_images.append(frame)
                    elif isinstance(frame, dict) and 'path' in frame:
                        if os.path.exists(frame['path']):
                            trajectory_images.append(frame['path'])
    
    # Also get final screenshot from container
    temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_final.png", temp_final.name)
        if os.path.getsize(temp_final.name) > 1000:  # Sanity check
            trajectory_images.append(temp_final.name)
    except Exception:
        pass
    
    if not trajectory_images:
        return 0, "~ No trajectory images available for VLM verification"
    
    # ================================================================
    # VLM: Process verification (15 points)
    # ================================================================
    process_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.
The task was to measure the pulmonary artery diameter on a chest CT scan.

Expected workflow:
1. CT scan visible in slice views (axial slices of chest)
2. Navigation through slices (different slice positions visible across frames)
3. Ruler/line measurement tool used (measurement line visible on image)
4. Measurement placed on a vascular structure (circular vessel in mediastinum)

Examine the progression across these frames and assess:
1. Is a chest CT visible in the interface?
2. Is there evidence of slice navigation (different views/slices)?
3. Is there a measurement line or ruler visible?
4. Does the measurement appear to be on a vascular structure?

Respond in JSON format:
{
    "ct_visible": true/false,
    "slice_navigation": true/false,
    "measurement_visible": true/false,
    "measurement_on_vessel": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
    
    try:
        # Query VLM with trajectory images
        if len(trajectory_images) > 1:
            vlm_result = query_vlm(prompt=process_prompt, images=trajectory_images)
        else:
            vlm_result = query_vlm(prompt=process_prompt, image=trajectory_images[0])
        
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            
            # Score based on VLM assessment
            ct_visible = parsed.get('ct_visible', False)
            measurement_visible = parsed.get('measurement_visible', False)
            on_vessel = parsed.get('measurement_on_vessel', False)
            navigation = parsed.get('slice_navigation', False)
            
            # Process verification (15 points)
            if ct_visible and measurement_visible:
                total_vlm_score += 10
                vlm_feedback_parts.append("✓ VLM: CT and measurement visible (+10)")
            elif ct_visible:
                total_vlm_score += 5
                vlm_feedback_parts.append("~ VLM: CT visible but measurement unclear (+5)")
            else:
                vlm_feedback_parts.append("✗ VLM: CT not clearly visible")
            
            # Visual confirmation (15 points)
            if measurement_visible and on_vessel:
                total_vlm_score += 15
                vlm_feedback_parts.append("✓ VLM: Measurement on vascular structure (+15)")
            elif measurement_visible:
                total_vlm_score += 8
                vlm_feedback_parts.append("~ VLM: Measurement visible, vessel unclear (+8)")
            
            # Bonus for workflow evidence
            if navigation:
                total_vlm_score += 5
                vlm_feedback_parts.append("✓ VLM: Slice navigation detected (+5)")
            
            observations = parsed.get('observations', '')
            if observations:
                vlm_feedback_parts.append(f"VLM notes: {observations}")
        else:
            vlm_feedback_parts.append("~ VLM query returned no result")
            
    except Exception as e:
        logger.warning(f"VLM query error: {e}")
        vlm_feedback_parts.append(f"~ VLM error: {str(e)[:50]}")
    
    finally:
        # Clean up temp file
        if os.path.exists(temp_final.name):
            os.unlink(temp_final.name)
    
    return total_vlm_score, "\n".join(vlm_feedback_parts)