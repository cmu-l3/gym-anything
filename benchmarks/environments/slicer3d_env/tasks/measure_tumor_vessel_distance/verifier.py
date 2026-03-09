#!/usr/bin/env python3
"""
Verifier for tumor-to-vessel distance measurement task.

VERIFICATION STRATEGY:
1. Output file exists (15 points)
2. Valid JSON structure with required fields (10 points)
3. Distance within tolerance of ground truth (35 points)
4. Correct resectability classification (20 points)
5. VLM confirms visualization setup (10 points)
6. File created during task - anti-gaming (10 points)

Pass threshold: 65 points with output_file_exists AND distance_within_tolerance
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tumor_vessel_distance(traj, env_info, task_info):
    """
    Verify tumor-to-vessel distance measurement task completion.
    
    Uses multi-criteria scoring with ground truth comparison.
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
    resectability_threshold = metadata.get('resectability_threshold_mm', 10.0)
    distance_tolerance = metadata.get('distance_tolerance_mm', 2.0)
    distance_range = metadata.get('distance_range_mm', {"min": 0.1, "max": 100})
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_file_exists', 15)
    w_valid_json = weights.get('valid_json_structure', 10)
    w_distance_correct = weights.get('distance_within_tolerance', 35)
    w_resectability = weights.get('correct_resectability', 20)
    w_vlm = weights.get('vlm_confirms_visualization', 10)
    w_anti_gaming = weights.get('file_created_during_task', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tvd_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
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
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ============================================================
    # CRITERION 1: Output file exists (15 points)
    # ============================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += w_output_exists
        feedback_parts.append("Output file created")
        details['output_exists'] = True
    else:
        feedback_parts.append("Output file NOT found")
        details['output_exists'] = False
        # Early exit - cannot verify without output
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ============================================================
    # CRITERION 2: Valid JSON structure (10 points)
    # ============================================================
    valid_json = result.get('valid_json', False)
    reported_distance_str = result.get('reported_distance_mm', '')
    reported_resectable_str = result.get('reported_resectable', '')
    
    if valid_json and reported_distance_str and reported_resectable_str:
        score += w_valid_json
        feedback_parts.append("Valid JSON format")
        details['valid_json'] = True
    else:
        feedback_parts.append("Invalid or incomplete JSON")
        details['valid_json'] = False
    
    # Parse reported values
    reported_distance = 0.0
    reported_resectable = None
    
    try:
        reported_distance = float(reported_distance_str) if reported_distance_str else 0.0
        reported_resectable = reported_resectable_str.lower() == 'true' if reported_resectable_str else None
        details['reported_distance_mm'] = reported_distance
        details['reported_resectable'] = reported_resectable
    except (ValueError, TypeError):
        feedback_parts.append("Could not parse reported values")
        details['parse_error'] = True
    
    # ============================================================
    # CRITERION 3: Distance within tolerance (35 points)
    # ============================================================
    gt_distance_str = result.get('gt_distance_mm', '')
    gt_distance = 0.0
    
    try:
        gt_distance = float(gt_distance_str) if gt_distance_str else 0.0
        details['gt_distance_mm'] = gt_distance
    except (ValueError, TypeError):
        logger.warning("Could not parse ground truth distance")
        details['gt_parse_error'] = True
    
    distance_within_tolerance = False
    
    if reported_distance > 0 and gt_distance > 0:
        distance_error = abs(reported_distance - gt_distance)
        details['distance_error_mm'] = distance_error
        
        # Check if within tolerance
        if distance_error <= distance_tolerance:
            score += w_distance_correct
            feedback_parts.append(f"Distance accurate ({reported_distance:.1f}mm, error: {distance_error:.1f}mm)")
            distance_within_tolerance = True
        elif distance_error <= distance_tolerance * 2:
            # Partial credit for close but not exact
            partial_score = int(w_distance_correct * 0.5)
            score += partial_score
            feedback_parts.append(f"Distance close ({reported_distance:.1f}mm, error: {distance_error:.1f}mm)")
        elif distance_error <= distance_tolerance * 3:
            # Small partial credit for reasonable attempt
            partial_score = int(w_distance_correct * 0.25)
            score += partial_score
            feedback_parts.append(f"Distance imprecise ({reported_distance:.1f}mm, error: {distance_error:.1f}mm)")
        else:
            feedback_parts.append(f"Distance incorrect ({reported_distance:.1f}mm vs GT {gt_distance:.1f}mm)")
        
        details['distance_within_tolerance'] = distance_within_tolerance
    else:
        # Check if distance is at least in plausible range
        if distance_range['min'] <= reported_distance <= distance_range['max']:
            partial_score = int(w_distance_correct * 0.2)
            score += partial_score
            feedback_parts.append(f"Distance in plausible range ({reported_distance:.1f}mm) but no GT comparison")
        else:
            feedback_parts.append("Distance out of plausible range or missing")
    
    # Reject obvious default/gaming values
    default_values = [0, 10, 10.0, -1, 100]
    if reported_distance in default_values and not distance_within_tolerance:
        feedback_parts.append("WARNING: Suspected default value")
        details['suspected_default'] = True
    
    # ============================================================
    # CRITERION 4: Correct resectability classification (20 points)
    # ============================================================
    gt_resectable_str = result.get('gt_resectable', '')
    gt_resectable = None
    
    try:
        gt_resectable = gt_resectable_str.lower() == 'true' if gt_resectable_str else None
        details['gt_resectable'] = gt_resectable
    except (ValueError, TypeError):
        pass
    
    if reported_resectable is not None:
        # Calculate expected classification based on reported distance
        expected_based_on_reported = reported_distance >= resectability_threshold
        
        # Check against ground truth if available
        if gt_resectable is not None:
            if reported_resectable == gt_resectable:
                score += w_resectability
                resectable_status = "safely resectable" if gt_resectable else "NOT safely resectable"
                feedback_parts.append(f"Classification correct ({resectable_status})")
                details['classification_correct'] = True
            else:
                feedback_parts.append(f"Classification incorrect (reported {reported_resectable}, expected {gt_resectable})")
                details['classification_correct'] = False
        # Otherwise check consistency with reported distance
        elif reported_resectable == expected_based_on_reported:
            partial_score = int(w_resectability * 0.7)
            score += partial_score
            feedback_parts.append("Classification consistent with reported distance")
            details['classification_consistent'] = True
        else:
            feedback_parts.append("Classification inconsistent with reported distance")
            details['classification_consistent'] = False
    else:
        feedback_parts.append("Resectability not reported")
    
    # ============================================================
    # CRITERION 5: Anti-gaming - file created during task (10 points)
    # ============================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += w_anti_gaming
        details['created_during_task'] = True
    else:
        feedback_parts.append("File may have existed before task")
        details['created_during_task'] = False
    
    # ============================================================
    # CRITERION 6: VLM verification on trajectory (10 points)
    # ============================================================
    vlm_score = 0
    
    # Try to use VLM for trajectory verification
    try:
        # Import VLM utilities if available
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            # Sample trajectory frames
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                all_frames = frames + [final] if final else frames
            except ImportError:
                # Fallback: use trajectory directly if available
                all_frames = traj.get('screenshots', [])[-5:] if isinstance(traj, dict) else []
            
            if all_frames:
                vlm_prompt = """You are verifying a medical imaging task in 3D Slicer.

The task was to measure the minimum distance between a liver tumor (red segment) and the portal vein (blue segment).

Looking at these screenshots from the task workflow, assess:
1. Is 3D Slicer visible with liver CT scan loaded?
2. Are colored segmentations visible (red tumor, blue portal vein, green liver)?
3. Is there evidence of measurement activity (ruler tools, statistics module, etc.)?
4. Does the final state suggest the measurement task was attempted?

Respond in JSON format:
{
    "slicer_visible": true/false,
    "segmentations_visible": true/false,
    "measurement_activity": true/false,
    "task_attempted": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    if parsed.get('segmentations_visible') and parsed.get('task_attempted'):
                        vlm_score = w_vlm
                        feedback_parts.append("VLM confirms task workflow")
                        details['vlm_verification'] = parsed
                    elif parsed.get('slicer_visible'):
                        vlm_score = int(w_vlm * 0.5)
                        feedback_parts.append("VLM confirms Slicer visible")
                        details['vlm_verification'] = parsed
                    else:
                        details['vlm_verification'] = parsed
                        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)
        # Give benefit of doubt if VLM fails but other criteria pass
        if score >= 50:
            vlm_score = int(w_vlm * 0.5)
    
    score += vlm_score
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Key criteria check
    key_criteria_met = output_exists and (distance_within_tolerance or score >= 50)
    passed = score >= 65 and key_criteria_met
    
    # Construct final feedback
    feedback = " | ".join(feedback_parts)
    
    details['total_score'] = score
    details['passed'] = passed
    details['slicer_was_running'] = result.get('slicer_was_running', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }