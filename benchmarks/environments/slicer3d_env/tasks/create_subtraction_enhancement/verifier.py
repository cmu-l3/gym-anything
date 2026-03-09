#!/usr/bin/env python3
"""
Verifier for the Create Subtraction Enhancement task.

VERIFICATION STRATEGY:
1. Output file exists and has valid size (15 points)
2. Output dimensions match input volumes (15 points)
3. Valid subtraction performed - correlation with expected (20 points)
4. Enhancement detected in tumor region (25 points)
5. File created during task execution (10 points)
6. Visual/process confirmation (15 points)

Pass threshold: 70 points with output exists and valid subtraction
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_subtraction_enhancement(traj, env_info, task_info):
    """
    Verify the subtraction enhancement task completion.
    
    Args:
        traj: Trajectory data with screenshots
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available - framework error"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', 
                                         '/home/ga/Documents/SlicerData/Exports/enhancement_map.nii.gz')
    min_output_size_kb = metadata.get('min_output_size_kb', 100)
    correlation_threshold = metadata.get('expected_correlation_threshold', 0.8)
    enhancement_ratio_threshold = metadata.get('enhancement_ratio_threshold', 1.5)
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_exists', 15)
    w_dimensions = weights.get('correct_dimensions', 15)
    w_subtraction = weights.get('valid_subtraction', 20)
    w_enhancement = weights.get('enhancement_detected', 25)
    w_timestamp = weights.get('created_during_task', 10)
    w_visual = weights.get('visual_confirmation', 15)
    
    score = 0.0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/subtraction_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_loaded'] = True
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed",
            "details": {"result_loaded": False}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
            "details": {"json_error": str(e)}
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Store raw result data
    details['raw_result'] = result_data
    
    # Check for errors in export
    if result_data.get('error'):
        feedback_parts.append(f"Export error: {result_data['error']}")
    
    # ================================================================
    # Criterion 1: Output File Exists (15 points)
    # ================================================================
    output_exists = result_data.get('output_exists', False)
    output_size = result_data.get('output_size_bytes', 0)
    output_size_kb = output_size / 1024 if output_size else 0
    
    if output_exists and output_size_kb > min_output_size_kb:
        score += w_output_exists
        feedback_parts.append(f"✓ Output file exists ({output_size_kb:.1f} KB)")
        details['output_valid'] = True
    elif output_exists and output_size_kb > 10:
        score += w_output_exists * 0.5
        feedback_parts.append(f"○ Output file exists but small ({output_size_kb:.1f} KB)")
        details['output_valid'] = 'partial'
    elif output_exists:
        score += w_output_exists * 0.25
        feedback_parts.append(f"✗ Output file very small ({output_size_kb:.1f} KB)")
        details['output_valid'] = False
    else:
        feedback_parts.append("✗ Output file not found")
        details['output_valid'] = False
        # Early return if no output
        return {
            "passed": False,
            "score": int(score),
            "feedback": " | ".join(feedback_parts) + "\n\nTo pass: Save the enhancement map to ~/Documents/SlicerData/Exports/enhancement_map.nii.gz",
            "details": details
        }
    
    # ================================================================
    # Criterion 2: Correct Dimensions (15 points)
    # ================================================================
    dimensions_match = result_data.get('dimensions_match', False)
    output_shape = result_data.get('output_shape', [])
    input_shape = result_data.get('input_shape', [])
    
    if dimensions_match:
        score += w_dimensions
        feedback_parts.append(f"✓ Output dimensions correct: {output_shape}")
        details['dimensions_valid'] = True
    elif output_shape and input_shape:
        feedback_parts.append(f"✗ Dimension mismatch: output {output_shape} vs input {input_shape}")
        details['dimensions_valid'] = False
    else:
        feedback_parts.append("✗ Could not verify dimensions")
        details['dimensions_valid'] = False
    
    # ================================================================
    # Criterion 3: Valid Subtraction (20 points)
    # ================================================================
    subtraction_valid = result_data.get('subtraction_valid', False)
    correlation = result_data.get('correlation_with_expected', 0)
    subtraction_reversed = result_data.get('subtraction_reversed', False)
    is_copy_t1 = result_data.get('is_copy_of_t1', False)
    is_copy_t1ce = result_data.get('is_copy_of_t1ce', False)
    
    if is_copy_t1 or is_copy_t1ce:
        feedback_parts.append("✗ Output is a copy of input (no subtraction performed)")
        details['subtraction_valid'] = False
    elif subtraction_valid and correlation > 0.9:
        score += w_subtraction
        feedback_parts.append(f"✓ Subtraction is valid (correlation: {correlation:.3f})")
        details['subtraction_valid'] = True
    elif subtraction_valid or correlation > correlation_threshold:
        score += w_subtraction * 0.75
        feedback_parts.append(f"○ Subtraction appears mostly correct (correlation: {correlation:.3f})")
        details['subtraction_valid'] = 'partial'
    elif subtraction_reversed:
        score += w_subtraction * 0.25
        feedback_parts.append("✗ Subtraction performed in wrong order (T1 - T1ce instead of T1ce - T1)")
        details['subtraction_valid'] = 'reversed'
    elif correlation > 0.5:
        score += w_subtraction * 0.4
        feedback_parts.append(f"○ Subtraction partially matches expected (correlation: {correlation:.3f})")
        details['subtraction_valid'] = 'partial'
    else:
        feedback_parts.append(f"✗ Subtraction does not match expected result (correlation: {correlation:.3f})")
        details['subtraction_valid'] = False
    
    # ================================================================
    # Criterion 4: Enhancement Detected (25 points)
    # ================================================================
    enhancement_detected = result_data.get('enhancement_detected', False)
    enhancement_ratio = result_data.get('enhancement_ratio', 0)
    enhancing_mean = result_data.get('enhancing_region_mean', None)
    non_tumor_mean = result_data.get('non_tumor_mean', None)
    
    if enhancement_detected and enhancement_ratio > enhancement_ratio_threshold:
        score += w_enhancement
        feedback_parts.append(f"✓ Enhancement detected in tumor region (ratio: {enhancement_ratio:.2f})")
        details['enhancement_detected'] = True
    elif enhancement_ratio > 1.0:
        score += w_enhancement * 0.6
        feedback_parts.append(f"○ Some enhancement visible (ratio: {enhancement_ratio:.2f})")
        details['enhancement_detected'] = 'partial'
    elif enhancing_mean is not None and enhancing_mean > 0:
        score += w_enhancement * 0.3
        feedback_parts.append(f"○ Positive values in tumor region (mean: {enhancing_mean:.1f})")
        details['enhancement_detected'] = 'weak'
    else:
        if enhancing_mean is not None and non_tumor_mean is not None:
            feedback_parts.append(f"✗ Enhancement not detected (tumor: {enhancing_mean:.1f}, background: {non_tumor_mean:.1f})")
        else:
            feedback_parts.append("✗ Enhancement not clearly detected")
        details['enhancement_detected'] = False
    
    # ================================================================
    # Criterion 5: File Created During Task (10 points) - Anti-gaming
    # ================================================================
    created_after_start = result_data.get('output_created_after_start', False)
    
    if created_after_start:
        score += w_timestamp
        feedback_parts.append("✓ Output file created during task execution")
        details['timestamp_valid'] = True
    else:
        feedback_parts.append("✗ Output file timestamp suggests it was not created during this task")
        details['timestamp_valid'] = False
    
    # ================================================================
    # Criterion 6: Visual/Process Confirmation (15 points)
    # ================================================================
    visual_score = 0
    
    # Check if Slicer was running
    slicer_running = result_data.get('slicer_running', False)
    if slicer_running:
        visual_score += w_visual * 0.4
        feedback_parts.append("✓ 3D Slicer was running")
        details['slicer_running'] = True
    else:
        details['slicer_running'] = False
    
    # Check validation passed
    validation_passed = result_data.get('validation_passed', False)
    if validation_passed:
        visual_score += w_visual * 0.6
        feedback_parts.append("✓ Overall validation passed")
        details['validation_passed'] = True
    else:
        details['validation_passed'] = False
    
    score += visual_score
    
    # ================================================================
    # Final Assessment
    # ================================================================
    # Determine pass/fail
    key_criteria_met = (
        output_exists and 
        (subtraction_valid or correlation > 0.7) and
        dimensions_match
    )
    passed = score >= 70 and key_criteria_met
    
    # Round score to integer
    final_score = int(round(score))
    
    # Generate final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nFinal Score: {final_score}/100"
    feedback += f"\nStatus: {'PASSED' if passed else 'FAILED'}"
    
    if not passed:
        feedback += "\n\nTo improve:"
        if not output_exists:
            feedback += "\n- Save the enhancement map to ~/Documents/SlicerData/Exports/enhancement_map.nii.gz"
        if not (subtraction_valid or correlation > 0.7):
            feedback += "\n- Use Subtract Scalar Volumes module with T1ce as Input 1 and T1 as Input 2"
        if not dimensions_match:
            feedback += "\n- Ensure you're using the correct input volumes"
        if not created_after_start:
            feedback += "\n- Actually perform the subtraction (don't use a pre-existing file)"
    
    # Store detailed metrics
    details['final_score'] = final_score
    details['passed'] = passed
    details['correlation'] = correlation
    details['enhancement_ratio'] = enhancement_ratio
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback,
        "details": details
    }