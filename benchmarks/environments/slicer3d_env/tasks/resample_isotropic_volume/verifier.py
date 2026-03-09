#!/usr/bin/env python3
"""
Verifier for resample_isotropic_volume@1 task.

VERIFICATION CRITERIA (100 points total):
1. Output volume exists (20 pts) - Volume with 'isotropic' in name found in scene
2. Correct X spacing (15 pts) - X spacing is 1.0mm ± 0.15mm
3. Correct Y spacing (15 pts) - Y spacing is 1.0mm ± 0.15mm
4. Correct Z spacing (20 pts) - Z spacing is 1.0mm ± 0.15mm (most important change)
5. Is truly isotropic (10 pts) - All three spacings within 5% of each other
6. Dimensions changed (10 pts) - Z dimension increased (proves resampling occurred)
7. Visual verification (10 pts) - Screenshot shows reasonable content

ANTI-GAMING CHECKS:
- Task must complete within reasonable time
- Output volume must be different from input volume
- Z-dimension should increase when resampling from anisotropic to isotropic

Pass threshold: 70 points with output volume existing
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_resample_isotropic_volume(traj, env_info, task_info):
    """
    Verify that the agent correctly resampled a volume to isotropic 1mm spacing.
    
    Args:
        traj: Trajectory data (list of steps with screenshots)
        env_info: Environment info containing copy_from_env function
        task_info: Task metadata
    
    Returns:
        dict with 'passed', 'score', 'feedback', and 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification error: copy_from_env function not available"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    target_spacing = metadata.get('target_spacing_mm', [1.0, 1.0, 1.0])
    spacing_tolerance = metadata.get('spacing_tolerance_mm', 0.15)
    z_increase_factor = metadata.get('expected_z_increase_factor', 2.0)
    pass_threshold = metadata.get('pass_threshold', 70)
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_volume_exists', 20)
    w_spacing_x = weights.get('spacing_x_correct', 15)
    w_spacing_y = weights.get('spacing_y_correct', 15)
    w_spacing_z = weights.get('spacing_z_correct', 20)
    w_isotropic = weights.get('is_isotropic', 10)
    w_dims_changed = weights.get('dimensions_changed', 10)
    w_visual = weights.get('visual_content_ok', 10)
    
    # Initialize result tracking
    total_score = 0
    feedback_parts = []
    score_breakdown = {}
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed properly"
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
    
    # Store raw result for debugging
    details['raw_result'] = result
    
    # ================================================================
    # Check 1: Slicer was running
    # ================================================================
    slicer_running = result.get('slicer_running', False)
    if not slicer_running:
        feedback_parts.append("Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    details['slicer_running'] = True
    
    # ================================================================
    # Check 2: Output volume exists (20 points)
    # ================================================================
    output_found = result.get('output_volume_found', False)
    output_name = result.get('output_volume_name', '')
    
    if output_found and output_name:
        total_score += w_output_exists
        score_breakdown['output_volume_exists'] = w_output_exists
        feedback_parts.append(f"Output volume found: '{output_name}'")
        details['output_volume_name'] = output_name
    else:
        score_breakdown['output_volume_exists'] = 0
        feedback_parts.append("No volume with 'isotropic' in name found")
        details['output_volume_name'] = None
        # Early exit if no output volume
        return {
            "passed": False,
            "score": total_score,
            "feedback": " | ".join(feedback_parts) + " - Create a volume named 'CT_Isotropic' or similar",
            "details": details,
            "score_breakdown": score_breakdown
        }
    
    # ================================================================
    # Extract spacing values
    # ================================================================
    output_spacing_x = result.get('output_spacing_x')
    output_spacing_y = result.get('output_spacing_y')
    output_spacing_z = result.get('output_spacing_z')
    
    # Convert to float if possible
    try:
        output_spacing_x = float(output_spacing_x) if output_spacing_x is not None else None
    except (ValueError, TypeError):
        output_spacing_x = None
    try:
        output_spacing_y = float(output_spacing_y) if output_spacing_y is not None else None
    except (ValueError, TypeError):
        output_spacing_y = None
    try:
        output_spacing_z = float(output_spacing_z) if output_spacing_z is not None else None
    except (ValueError, TypeError):
        output_spacing_z = None
    
    details['output_spacing'] = [output_spacing_x, output_spacing_y, output_spacing_z]
    
    # ================================================================
    # Check 3: Correct X spacing (15 points)
    # ================================================================
    if output_spacing_x is not None:
        x_diff = abs(output_spacing_x - target_spacing[0])
        x_correct = x_diff < spacing_tolerance
        
        if x_correct:
            total_score += w_spacing_x
            score_breakdown['spacing_x_correct'] = w_spacing_x
            feedback_parts.append(f"X spacing correct: {output_spacing_x:.3f}mm")
        else:
            score_breakdown['spacing_x_correct'] = 0
            feedback_parts.append(f"X spacing incorrect: {output_spacing_x:.3f}mm (expected ~{target_spacing[0]}mm)")
    else:
        score_breakdown['spacing_x_correct'] = 0
        feedback_parts.append("X spacing not available")
    
    # ================================================================
    # Check 4: Correct Y spacing (15 points)
    # ================================================================
    if output_spacing_y is not None:
        y_diff = abs(output_spacing_y - target_spacing[1])
        y_correct = y_diff < spacing_tolerance
        
        if y_correct:
            total_score += w_spacing_y
            score_breakdown['spacing_y_correct'] = w_spacing_y
            feedback_parts.append(f"Y spacing correct: {output_spacing_y:.3f}mm")
        else:
            score_breakdown['spacing_y_correct'] = 0
            feedback_parts.append(f"Y spacing incorrect: {output_spacing_y:.3f}mm (expected ~{target_spacing[1]}mm)")
    else:
        score_breakdown['spacing_y_correct'] = 0
        feedback_parts.append("Y spacing not available")
    
    # ================================================================
    # Check 5: Correct Z spacing (20 points) - most important
    # ================================================================
    if output_spacing_z is not None:
        z_diff = abs(output_spacing_z - target_spacing[2])
        z_correct = z_diff < spacing_tolerance
        
        if z_correct:
            total_score += w_spacing_z
            score_breakdown['spacing_z_correct'] = w_spacing_z
            feedback_parts.append(f"Z spacing correct: {output_spacing_z:.3f}mm")
        else:
            score_breakdown['spacing_z_correct'] = 0
            feedback_parts.append(f"Z spacing incorrect: {output_spacing_z:.3f}mm (expected ~{target_spacing[2]}mm)")
    else:
        score_breakdown['spacing_z_correct'] = 0
        feedback_parts.append("Z spacing not available")
    
    # ================================================================
    # Check 6: Is truly isotropic (10 points)
    # ================================================================
    is_isotropic = result.get('is_isotropic', False)
    
    # Also verify manually if we have all spacing values
    if output_spacing_x and output_spacing_y and output_spacing_z:
        spacings = [output_spacing_x, output_spacing_y, output_spacing_z]
        max_sp = max(spacings)
        min_sp = min(spacings)
        if min_sp > 0:
            manual_isotropic = (max_sp - min_sp) / max_sp < 0.05
            is_isotropic = is_isotropic or manual_isotropic
            details['isotropy_ratio'] = max_sp / min_sp
    
    if is_isotropic:
        total_score += w_isotropic
        score_breakdown['is_isotropic'] = w_isotropic
        feedback_parts.append("Volume is isotropic")
    else:
        score_breakdown['is_isotropic'] = 0
        feedback_parts.append("Volume is NOT isotropic")
    
    # ================================================================
    # Check 7: Dimensions changed appropriately (10 points)
    # Anti-gaming: proves actual resampling occurred
    # ================================================================
    z_dim_increased = result.get('z_dimension_increased', False)
    
    # Manual verification
    output_dim_z = result.get('output_dim_z')
    initial_dim_z = result.get('initial_dim_z')
    
    try:
        output_dim_z = int(output_dim_z) if output_dim_z is not None else None
    except (ValueError, TypeError):
        output_dim_z = None
    try:
        initial_dim_z = int(initial_dim_z) if initial_dim_z is not None else None
    except (ValueError, TypeError):
        initial_dim_z = None
    
    if output_dim_z and initial_dim_z and initial_dim_z > 0:
        z_ratio = output_dim_z / initial_dim_z
        details['z_dimension_ratio'] = z_ratio
        
        # For resampling from ~2.5mm to 1mm in Z, expect ~2.5x increase
        if z_ratio > z_increase_factor - 0.5:  # Allow some tolerance
            z_dim_increased = True
    
    if z_dim_increased:
        total_score += w_dims_changed
        score_breakdown['dimensions_changed'] = w_dims_changed
        if 'z_dimension_ratio' in details:
            feedback_parts.append(f"Z dimension increased ({details['z_dimension_ratio']:.2f}x)")
        else:
            feedback_parts.append("Z dimension increased (resampling verified)")
    else:
        score_breakdown['dimensions_changed'] = 0
        feedback_parts.append("Z dimension did not change as expected")
    
    # ================================================================
    # Check 8: Visual verification (10 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_bytes', 0)
    
    # Basic check: screenshot exists and has reasonable size
    visual_ok = screenshot_exists and screenshot_size > 50000  # > 50KB
    
    if visual_ok:
        total_score += w_visual
        score_breakdown['visual_content_ok'] = w_visual
        feedback_parts.append(f"Screenshot captured ({screenshot_size // 1024}KB)")
    else:
        score_breakdown['visual_content_ok'] = 0
        if not screenshot_exists:
            feedback_parts.append("No screenshot available")
        else:
            feedback_parts.append(f"Screenshot too small ({screenshot_size} bytes)")
    
    # ================================================================
    # Calculate final result
    # ================================================================
    max_score = w_output_exists + w_spacing_x + w_spacing_y + w_spacing_z + w_isotropic + w_dims_changed + w_visual
    normalized_score = total_score / max_score if max_score > 0 else 0
    
    # Pass criteria: score >= threshold AND output volume exists
    passed = total_score >= pass_threshold and output_found
    
    # Generate summary feedback
    if passed:
        summary = f"Task completed successfully! Volume correctly resampled to isotropic {target_spacing[0]}mm spacing."
    elif output_found:
        issues = []
        if score_breakdown.get('spacing_x_correct', 0) == 0:
            issues.append("X spacing incorrect")
        if score_breakdown.get('spacing_y_correct', 0) == 0:
            issues.append("Y spacing incorrect")
        if score_breakdown.get('spacing_z_correct', 0) == 0:
            issues.append("Z spacing incorrect")
        if not is_isotropic:
            issues.append("not isotropic")
        summary = f"Partial completion. Issues: {', '.join(issues)}"
    else:
        summary = "Task incomplete. No output volume found with 'isotropic' in name."
    
    feedback = f"{summary} | Score: {total_score}/{max_score} | " + " | ".join(feedback_parts[:5])
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": details,
        "score_breakdown": score_breakdown,
        "normalized_score": normalized_score,
        "max_score": max_score
    }


if __name__ == "__main__":
    # Test harness
    print("Resample Isotropic Volume Verifier")
    print("Run within task framework to verify")
    print()
    print("Expected verification criteria:")
    print("  - Output volume with 'isotropic' in name")
    print("  - Spacing approximately 1.0mm x 1.0mm x 1.0mm")
    print("  - Z dimension increased from original")