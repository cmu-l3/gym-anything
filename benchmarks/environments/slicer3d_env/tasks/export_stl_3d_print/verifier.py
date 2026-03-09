#!/usr/bin/env python3
"""
Verifier for Export STL for 3D Printing task.

VERIFICATION CRITERIA (Multi-signal approach):
1. STL file exists at expected path (25 points)
2. File was created during task execution (15 points) - anti-gaming
3. Valid STL format (ASCII or binary) (20 points)
4. Sufficient mesh complexity - 500+ triangles (20 points)
5. Reasonable mesh dimensions - 5-150mm bounding box (10 points)
6. VLM trajectory verification (10 points)

Pass threshold: 70 points with key criteria (file exists + valid format) met
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_stl_3d_print(traj, env_info, task_info):
    """
    Verify that STL export was completed successfully.
    
    Uses multiple independent signals to prevent gaming:
    - File existence and timestamps
    - STL format validation
    - Mesh geometry validation
    - VLM trajectory analysis
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
    expected_output_path = metadata.get('expected_output_path', 
        '/home/ga/Documents/SlicerData/Exports/tumor_model.stl')
    min_file_size_kb = metadata.get('min_file_size_kb', 10)
    min_triangle_count = metadata.get('min_triangle_count', 500)
    min_bbox_mm = metadata.get('min_bbox_mm', 5)
    max_bbox_mm = metadata.get('max_bbox_mm', 150)
    
    weights = metadata.get('scoring_weights', {})
    w_stl_exists = weights.get('stl_exists', 25)
    w_created_during = weights.get('created_during_task', 15)
    w_valid_format = weights.get('valid_stl_format', 20)
    w_mesh_complexity = weights.get('sufficient_mesh_complexity', 20)
    w_dimensions = weights.get('reasonable_dimensions', 10)
    w_vlm = weights.get('vlm_verification', 10)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/stl_export_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info("Successfully loaded result JSON")
    except FileNotFoundError:
        logger.error("Result file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        logger.error(f"Error reading result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['result_data'] = result
    
    # ================================================================
    # Check if Slicer was running (basic sanity check)
    # ================================================================
    slicer_running = result.get('slicer_was_running', False)
    if not slicer_running:
        feedback_parts.append("⚠ Slicer was not running")
        details['slicer_running'] = False
    else:
        details['slicer_running'] = True
    
    # ================================================================
    # CRITERION 1: STL file exists (25 points)
    # ================================================================
    stl_exists = result.get('stl_file_exists', False)
    if stl_exists == 'true' or stl_exists == True:
        score += w_stl_exists
        stl_path = result.get('stl_file_path', expected_output_path)
        feedback_parts.append(f"✓ STL file exists (+{w_stl_exists})")
        details['stl_exists'] = True
        details['stl_path'] = stl_path
    else:
        feedback_parts.append("✗ STL file NOT found at expected path")
        details['stl_exists'] = False
        # Early exit - can't proceed without file
        return {
            'score': score,
            'max_score': max_score,
            'passed': False,
            'feedback': '\n'.join(feedback_parts) + f"\n\nTotal Score: {score}/{max_score}",
            'details': details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (15 points) - Anti-gaming
    # ================================================================
    created_during_task = result.get('stl_created_during_task', False)
    if created_during_task == 'true' or created_during_task == True:
        score += w_created_during
        feedback_parts.append(f"✓ File created during task execution (+{w_created_during})")
        details['created_during_task'] = True
    else:
        feedback_parts.append("⚠ File may have existed before task (timestamp check failed)")
        details['created_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Valid STL format (20 points)
    # ================================================================
    stl_valid = result.get('stl_valid_format', False)
    stl_format = result.get('stl_format', 'unknown')
    
    if stl_valid == 'true' or stl_valid == True:
        score += w_valid_format
        feedback_parts.append(f"✓ Valid {stl_format} STL format (+{w_valid_format})")
        details['valid_format'] = True
        details['stl_format'] = stl_format
    else:
        parse_error = result.get('stl_parse_error', '')
        if parse_error:
            feedback_parts.append(f"✗ Invalid STL format: {parse_error}")
        else:
            feedback_parts.append("✗ Could not validate STL format")
        details['valid_format'] = False
    
    # ================================================================
    # CRITERION 4: Sufficient mesh complexity (20 points)
    # ================================================================
    triangle_count = int(result.get('stl_triangle_count', 0))
    details['triangle_count'] = triangle_count
    
    if triangle_count >= min_triangle_count:
        score += w_mesh_complexity
        feedback_parts.append(f"✓ Mesh has {triangle_count:,} triangles (≥{min_triangle_count}) (+{w_mesh_complexity})")
    elif triangle_count >= min_triangle_count // 2:
        partial_score = w_mesh_complexity // 2
        score += partial_score
        feedback_parts.append(f"~ Mesh has {triangle_count:,} triangles (partial) (+{partial_score})")
    elif triangle_count > 0:
        partial_score = w_mesh_complexity // 4
        score += partial_score
        feedback_parts.append(f"⚠ Mesh has only {triangle_count} triangles (+{partial_score})")
    else:
        feedback_parts.append(f"✗ No valid mesh triangles found")
    
    # ================================================================
    # CRITERION 5: Reasonable mesh dimensions (10 points)
    # ================================================================
    try:
        bbox_x = float(result.get('stl_bbox_x_mm', 0))
        bbox_y = float(result.get('stl_bbox_y_mm', 0))
        bbox_z = float(result.get('stl_bbox_z_mm', 0))
        max_dim = max(bbox_x, bbox_y, bbox_z)
        min_dim = min(bbox_x, bbox_y, bbox_z) if min(bbox_x, bbox_y, bbox_z) > 0 else max_dim
        
        details['bounding_box'] = {
            'x_mm': bbox_x,
            'y_mm': bbox_y, 
            'z_mm': bbox_z,
            'max_dim': max_dim
        }
        
        # Check if dimensions are reasonable for a brain tumor (5-150mm)
        if min_bbox_mm <= max_dim <= max_bbox_mm and max_dim > 0:
            score += w_dimensions
            feedback_parts.append(f"✓ Mesh dimensions reasonable ({max_dim:.1f}mm max) (+{w_dimensions})")
        elif max_dim > 0:
            # Partial credit for non-zero dimensions outside expected range
            partial_score = w_dimensions // 2
            score += partial_score
            feedback_parts.append(f"~ Mesh dimensions outside expected range ({max_dim:.1f}mm) (+{partial_score})")
        else:
            feedback_parts.append("✗ Could not determine mesh dimensions")
    except (ValueError, TypeError) as e:
        feedback_parts.append(f"✗ Error parsing mesh dimensions: {e}")
        details['bounding_box'] = {'error': str(e)}
    
    # ================================================================
    # CRITERION 6: VLM Trajectory Verification (10 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = "VLM verification not performed"
    
    # Check if we have trajectory data
    if traj and isinstance(traj, list) and len(traj) > 0:
        # Basic trajectory presence check
        vlm_score = w_vlm
        vlm_feedback = f"Task trajectory recorded ({len(traj)} steps)"
        
        # Try to use VLM if available
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            try:
                # Sample frames from trajectory for VLM analysis
                sample_trajectory_frames = env_info.get('sample_trajectory_frames')
                get_final_screenshot = env_info.get('get_final_screenshot')
                
                frames = []
                if sample_trajectory_frames:
                    frames = sample_trajectory_frames(traj, n=3)
                elif get_final_screenshot:
                    final = get_final_screenshot(traj)
                    if final:
                        frames = [final]
                
                if frames:
                    vlm_prompt = """Analyze these screenshots from a 3D Slicer session.
                    
The task was to export a brain tumor segmentation as an STL file for 3D printing.

Look for evidence of:
1. A segmentation visible (colored regions on brain scan)
2. Export dialogs or file save dialogs
3. Segmentations module or Data module usage
4. Any indication that an export operation was performed

Respond in JSON:
{
    "segmentation_visible": true/false,
    "export_activity_detected": true/false,
    "slicer_interface_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see"
}"""
                    
                    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if isinstance(parsed, dict):
                            export_detected = parsed.get('export_activity_detected', False)
                            seg_visible = parsed.get('segmentation_visible', False)
                            confidence = parsed.get('confidence', 'low')
                            
                            if export_detected and seg_visible and confidence in ['medium', 'high']:
                                vlm_score = w_vlm
                                vlm_feedback = f"VLM confirms export workflow (confidence: {confidence})"
                            elif export_detected or seg_visible:
                                vlm_score = w_vlm // 2
                                vlm_feedback = f"VLM partial confirmation: seg={seg_visible}, export={export_detected}"
                            else:
                                vlm_score = w_vlm // 4
                                vlm_feedback = "VLM could not confirm export workflow"
                            
                            details['vlm_result'] = parsed
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                vlm_feedback = f"VLM error: {str(e)[:50]}"
    
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"✓ {vlm_feedback} (+{vlm_score})")
    else:
        feedback_parts.append(f"~ {vlm_feedback}")
    
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: file must exist AND be valid format
    key_criteria_met = (
        details.get('stl_exists', False) and 
        details.get('valid_format', False)
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback_parts.append(f"\n{'='*40}")
    feedback_parts.append(f"Total Score: {score}/{max_score}")
    
    if passed:
        feedback_parts.append("✓ PASSED - STL export completed successfully")
    else:
        if not key_criteria_met:
            feedback_parts.append("✗ FAILED - Key criteria not met (need: file exists + valid format)")
        else:
            feedback_parts.append(f"✗ FAILED - Score {score} below threshold (70)")
    
    return {
        'score': score,
        'max_score': max_score,
        'passed': passed,
        'feedback': '\n'.join(feedback_parts),
        'details': details
    }