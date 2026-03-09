#!/usr/bin/env python3
"""
Verifier for aortic cross-sectional area measurement task.

VERIFICATION STRATEGY (Multi-Signal):

Programmatic checks (85 points):
1. JSON file exists with required fields (15 points)
2. Slice location within tolerance of ground truth (25 points)
3. Area measurement within 15% of expected (30 points)
4. Sufficient control points used (10 points)
5. File created after task start - anti-gaming (5 points)

VLM verification (15 points):
6. Trajectory shows curve on aortic structure (15 points)

Pass threshold: 70 points with (file exists AND (slice correct OR area correct))
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_aortic_cross_sectional_area(traj, env_info, task_info):
    """
    Verify aortic cross-sectional area measurement task completion.
    
    Uses copy_from_env to read container files (NOT exec_in_env).
    Uses trajectory frames for VLM verification.
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
    expected_slice = metadata.get('expected_max_slice_index', 45)
    slice_tolerance = metadata.get('expected_slice_tolerance', 5)
    expected_area = metadata.get('expected_area_mm2', 855)
    area_tolerance_pct = metadata.get('area_tolerance_percent', 15)
    min_control_points = metadata.get('min_control_points', 6)
    
    weights = metadata.get('scoring_weights', {})
    w_json_exists = weights.get('json_file_exists', 15)
    w_slice_correct = weights.get('slice_location_correct', 25)
    w_area_correct = weights.get('area_within_tolerance', 30)
    w_points = weights.get('sufficient_control_points', 10)
    w_vlm = weights.get('vlm_aortic_location', 15)
    w_timestamp = weights.get('file_created_after_start', 5)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT FILE FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/aortic_area_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task"
        }
    
    details['slicer_running'] = True
    
    # ================================================================
    # CRITERION 1: JSON File Exists with Required Fields (15 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        # Try to read the actual report file for validation
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        report_data = {}
        report_valid = False
        try:
            copy_from_env("/home/ga/Documents/SlicerData/Exports/aortic_area_measurement.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_data = json.load(f)
            
            # Check required fields
            required_fields = ['slice_index', 'cross_sectional_area_mm2', 'num_control_points']
            has_fields = all(field in report_data for field in required_fields)
            
            if has_fields:
                score += w_json_exists
                feedback_parts.append("Output JSON valid")
                report_valid = True
                details['report_valid'] = True
            else:
                score += w_json_exists // 2
                missing = [f for f in required_fields if f not in report_data]
                feedback_parts.append(f"JSON missing fields: {missing}")
                details['report_valid'] = False
                details['missing_fields'] = missing
        except Exception as e:
            score += w_json_exists // 3
            feedback_parts.append(f"JSON exists but couldn't validate: {e}")
            details['report_error'] = str(e)
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback_parts.append("Output JSON NOT found")
        details['report_exists'] = False
    
    # ================================================================
    # CRITERION 2: File Created After Task Start (5 points) - Anti-gaming
    # ================================================================
    file_created_during_task = result.get('report_created_during_task', False)
    
    if file_created_during_task:
        score += w_timestamp
        feedback_parts.append("File created during task")
        details['created_during_task'] = True
    else:
        feedback_parts.append("File timestamp suspicious")
        details['created_during_task'] = False
    
    # ================================================================
    # Get measurements from result
    # ================================================================
    # Prefer agent's reported values, fall back to Slicer-extracted
    agent_area_str = result.get('extracted_area_mm2', '')
    agent_slice_str = result.get('extracted_slice_index', '')
    agent_points_str = result.get('extracted_num_control_points', '')
    
    slicer_area_str = result.get('slicer_curve_area_mm2', '')
    slicer_points_str = result.get('slicer_curve_num_points', '')
    
    # Parse values
    measured_area = 0.0
    measured_slice = -1
    measured_points = 0
    
    # Try agent's values first
    try:
        if agent_area_str:
            measured_area = float(agent_area_str)
    except (ValueError, TypeError):
        pass
    
    try:
        if agent_slice_str:
            measured_slice = int(agent_slice_str)
    except (ValueError, TypeError):
        pass
    
    try:
        if agent_points_str:
            measured_points = int(agent_points_str)
    except (ValueError, TypeError):
        pass
    
    # Fall back to Slicer-extracted if agent values missing
    if measured_area <= 0 and slicer_area_str:
        try:
            measured_area = float(slicer_area_str)
        except (ValueError, TypeError):
            pass
    
    if measured_points <= 0 and slicer_points_str:
        try:
            measured_points = int(slicer_points_str)
        except (ValueError, TypeError):
            pass
    
    details['measured_area_mm2'] = measured_area
    details['measured_slice'] = measured_slice
    details['measured_points'] = measured_points
    
    # Get ground truth values
    gt_slice_str = result.get('gt_max_slice_index', '')
    gt_area_str = result.get('gt_expected_area_mm2', '')
    
    gt_slice = expected_slice  # Default from metadata
    gt_area = expected_area    # Default from metadata
    
    try:
        if gt_slice_str:
            gt_slice = int(gt_slice_str)
    except (ValueError, TypeError):
        pass
    
    try:
        if gt_area_str:
            gt_area = float(gt_area_str)
    except (ValueError, TypeError):
        pass
    
    details['gt_slice'] = gt_slice
    details['gt_area'] = gt_area
    
    # ================================================================
    # CRITERION 3: Slice Location Correct (25 points)
    # ================================================================
    slice_correct = False
    
    if measured_slice >= 0:
        slice_diff = abs(measured_slice - gt_slice)
        details['slice_difference'] = slice_diff
        
        if slice_diff <= slice_tolerance:
            score += w_slice_correct
            feedback_parts.append(f"Slice correct (±{slice_diff})")
            slice_correct = True
        elif slice_diff <= slice_tolerance * 2:
            score += w_slice_correct // 2
            feedback_parts.append(f"Slice close (±{slice_diff})")
        else:
            feedback_parts.append(f"Slice incorrect (expected ~{gt_slice}, got {measured_slice})")
    else:
        feedback_parts.append("No slice index reported")
    
    # ================================================================
    # CRITERION 4: Area Within Tolerance (30 points)
    # ================================================================
    area_correct = False
    
    if measured_area > 0:
        area_diff_pct = abs(measured_area - gt_area) / gt_area * 100 if gt_area > 0 else 100
        details['area_difference_percent'] = area_diff_pct
        
        if area_diff_pct <= area_tolerance_pct:
            score += w_area_correct
            feedback_parts.append(f"Area accurate ({measured_area:.1f} mm², {area_diff_pct:.1f}% diff)")
            area_correct = True
        elif area_diff_pct <= area_tolerance_pct * 1.5:
            score += w_area_correct * 2 // 3
            feedback_parts.append(f"Area close ({measured_area:.1f} mm², {area_diff_pct:.1f}% diff)")
        elif area_diff_pct <= area_tolerance_pct * 2:
            score += w_area_correct // 3
            feedback_parts.append(f"Area rough ({measured_area:.1f} mm², {area_diff_pct:.1f}% diff)")
        else:
            feedback_parts.append(f"Area incorrect ({measured_area:.1f} mm², expected ~{gt_area:.1f} mm²)")
    else:
        # Check if curve exists even without area
        curve_exists = result.get('curve_exists_in_scene', False)
        if curve_exists:
            score += w_area_correct // 4
            feedback_parts.append("Curve exists but area not extracted")
        else:
            feedback_parts.append("No area measurement found")
    
    # ================================================================
    # CRITERION 5: Sufficient Control Points (10 points)
    # ================================================================
    if measured_points >= min_control_points:
        score += w_points
        feedback_parts.append(f"Good curve detail ({measured_points} points)")
        details['sufficient_points'] = True
    elif measured_points > 0:
        score += w_points // 2
        feedback_parts.append(f"Few control points ({measured_points})")
        details['sufficient_points'] = False
    else:
        feedback_parts.append("Control points unknown")
    
    # ================================================================
    # CRITERION 6: VLM Verification (15 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory (NOT just final screenshot)
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) > 0:
            vlm_prompt = """You are analyzing screenshots from a medical imaging task in 3D Slicer.

The task was to measure the cross-sectional area of the abdominal aorta by:
1. Navigating to the axial slice showing maximum aortic diameter
2. Creating a closed curve markup tracing the aortic lumen perimeter

Examine these trajectory frames and assess:
1. Is there a closed curve (polygon) visible on any axial slice view?
2. If yes, is the curve positioned on or near a circular structure in the CENTER of the image (this would be the aorta)?
3. Does the curve appear to trace a vessel boundary (not drawn randomly)?

The aorta should appear as:
- A roughly circular/oval bright structure
- Located ANTERIOR to the spine (the spine is the bright structure at the back)
- In the midline of the body (center of the image)

Respond in JSON format:
{
    "closed_curve_visible": true/false,
    "curve_on_central_structure": true/false,
    "appears_to_trace_vessel": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_response'] = parsed
                
                curve_visible = parsed.get('closed_curve_visible', False)
                on_aorta = parsed.get('curve_on_central_structure', False)
                traces_vessel = parsed.get('appears_to_trace_vessel', False)
                confidence = parsed.get('confidence', 'low')
                
                if curve_visible and on_aorta and traces_vessel:
                    if confidence in ['medium', 'high']:
                        vlm_score = w_vlm
                        vlm_feedback = "VLM: Curve correctly placed on aorta"
                    else:
                        vlm_score = w_vlm * 2 // 3
                        vlm_feedback = "VLM: Curve likely on aorta (low confidence)"
                elif curve_visible and (on_aorta or traces_vessel):
                    vlm_score = w_vlm // 2
                    vlm_feedback = "VLM: Curve visible, possibly on aorta"
                elif curve_visible:
                    vlm_score = w_vlm // 3
                    vlm_feedback = "VLM: Curve visible but location unclear"
                else:
                    vlm_feedback = "VLM: No curve visible"
            else:
                vlm_feedback = "VLM: Query failed"
                details['vlm_error'] = vlm_result.get('error', 'unknown') if vlm_result else 'no result'
        else:
            vlm_feedback = "VLM: No trajectory frames available"
    except ImportError:
        vlm_feedback = "VLM: Module not available"
    except Exception as e:
        vlm_feedback = f"VLM: Error - {str(e)[:50]}"
        details['vlm_exception'] = str(e)
    
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)
    
    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    # Pass requires: file exists AND (slice correct OR area correct)
    key_criteria_met = report_exists and (slice_correct or area_correct or measured_area > 0)
    passed = score >= 70 and key_criteria_met
    
    # Build feedback string
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }