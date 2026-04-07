#!/usr/bin/env python3
"""
Verifier for tumor bounding box measurement task.

VERIFICATION CRITERIA:
1. Output file exists (15 points)
2. File format correct - contains required labels (10 points)
3. Width measurement within tolerance of ground truth (20 points)
4. Depth measurement within tolerance of ground truth (20 points)
5. Height measurement within tolerance of ground truth (20 points)
6. Bounding volume calculation correct (10 points)
7. Segmentation was created in Slicer (5 points)

Pass threshold: 65 points with at least 2 of 3 dimensions correct
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tumor_bbox(traj, env_info, task_info):
    """
    Verify tumor bounding box measurement task completion.
    
    Uses multi-criteria scoring with dimensional tolerance checks.
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
    tolerance_pct = metadata.get('dimension_tolerance_percent', 15)
    dim_range = metadata.get('dimension_range_mm', {"min": 5, "max": 120})
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('file_exists', 15)
    w_format = weights.get('file_format_correct', 10)
    w_width = weights.get('width_correct', 20)
    w_depth = weights.get('depth_correct', 20)
    w_height = weights.get('height_correct', 20)
    w_volume = weights.get('bounding_volume_correct', 10)
    w_seg = weights.get('segmentation_exists', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/bbox_task_result.json", temp_result.name)
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
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer not running")
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_file_exists', False)
    output_created = result.get('output_created_during_task', False)
    
    if output_exists and output_created:
        score += w_file_exists
        feedback_parts.append("Output file created")
        details['file_created'] = True
    elif output_exists:
        score += w_file_exists * 0.5  # Partial credit
        feedback_parts.append("Output file exists (not verified as new)")
        details['file_created'] = False
    else:
        feedback_parts.append("Output file NOT found")
        details['file_created'] = False
        # Cannot verify measurements without file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File format correct (10 points)
    # ================================================================
    format_correct = result.get('format_correct', False)
    
    if format_correct:
        score += w_format
        feedback_parts.append("Format correct")
    else:
        score += w_format * 0.3  # Small partial credit
        feedback_parts.append("Format incomplete")
    
    details['format_correct'] = format_correct
    
    # ================================================================
    # GET GROUND TRUTH VALUES
    # ================================================================
    gt_width = _parse_float(result.get('gt_width_mm', ''))
    gt_depth = _parse_float(result.get('gt_depth_mm', ''))
    gt_height = _parse_float(result.get('gt_height_mm', ''))
    gt_volume = _parse_float(result.get('gt_volume_mm3', ''))
    
    details['gt_width_mm'] = gt_width
    details['gt_depth_mm'] = gt_depth
    details['gt_height_mm'] = gt_height
    details['gt_volume_mm3'] = gt_volume
    
    if gt_width is None or gt_depth is None or gt_height is None:
        feedback_parts.append("Ground truth unavailable")
        logger.warning("Ground truth values not available")
    
    # ================================================================
    # GET MEASURED VALUES
    # Prefer values from output file, fallback to Slicer extraction
    # ================================================================
    measured_width = _parse_float(result.get('measured_width_mm', ''))
    measured_depth = _parse_float(result.get('measured_depth_mm', ''))
    measured_height = _parse_float(result.get('measured_height_mm', ''))
    measured_volume = _parse_float(result.get('measured_volume_mm3', ''))
    
    # Fallback to Slicer-extracted values if file parsing failed
    if measured_width is None:
        measured_width = _parse_float(result.get('slicer_width_mm', ''))
    if measured_depth is None:
        measured_depth = _parse_float(result.get('slicer_depth_mm', ''))
    if measured_height is None:
        measured_height = _parse_float(result.get('slicer_height_mm', ''))
    
    details['measured_width_mm'] = measured_width
    details['measured_depth_mm'] = measured_depth
    details['measured_height_mm'] = measured_height
    details['measured_volume_mm3'] = measured_volume
    
    # ================================================================
    # CRITERION 3: Width correct (20 points)
    # ================================================================
    width_correct = False
    if measured_width is not None and gt_width is not None:
        if _is_within_tolerance(measured_width, gt_width, tolerance_pct):
            score += w_width
            width_correct = True
            feedback_parts.append(f"Width OK ({measured_width:.1f}mm)")
        elif _is_within_tolerance(measured_width, gt_width, tolerance_pct * 2):
            score += w_width * 0.5
            feedback_parts.append(f"Width close ({measured_width:.1f}mm vs {gt_width:.1f}mm)")
        else:
            feedback_parts.append(f"Width incorrect ({measured_width:.1f}mm vs {gt_width:.1f}mm)")
    elif measured_width is not None:
        # Check plausibility even without ground truth
        if _is_plausible(measured_width, dim_range):
            score += w_width * 0.3
            feedback_parts.append(f"Width plausible ({measured_width:.1f}mm)")
        else:
            feedback_parts.append(f"Width implausible ({measured_width:.1f}mm)")
    else:
        feedback_parts.append("Width not measured")
    
    details['width_correct'] = width_correct
    
    # ================================================================
    # CRITERION 4: Depth correct (20 points)
    # ================================================================
    depth_correct = False
    if measured_depth is not None and gt_depth is not None:
        if _is_within_tolerance(measured_depth, gt_depth, tolerance_pct):
            score += w_depth
            depth_correct = True
            feedback_parts.append(f"Depth OK ({measured_depth:.1f}mm)")
        elif _is_within_tolerance(measured_depth, gt_depth, tolerance_pct * 2):
            score += w_depth * 0.5
            feedback_parts.append(f"Depth close ({measured_depth:.1f}mm vs {gt_depth:.1f}mm)")
        else:
            feedback_parts.append(f"Depth incorrect ({measured_depth:.1f}mm vs {gt_depth:.1f}mm)")
    elif measured_depth is not None:
        if _is_plausible(measured_depth, dim_range):
            score += w_depth * 0.3
            feedback_parts.append(f"Depth plausible ({measured_depth:.1f}mm)")
        else:
            feedback_parts.append(f"Depth implausible ({measured_depth:.1f}mm)")
    else:
        feedback_parts.append("Depth not measured")
    
    details['depth_correct'] = depth_correct
    
    # ================================================================
    # CRITERION 5: Height correct (20 points)
    # ================================================================
    height_correct = False
    if measured_height is not None and gt_height is not None:
        if _is_within_tolerance(measured_height, gt_height, tolerance_pct):
            score += w_height
            height_correct = True
            feedback_parts.append(f"Height OK ({measured_height:.1f}mm)")
        elif _is_within_tolerance(measured_height, gt_height, tolerance_pct * 2):
            score += w_height * 0.5
            feedback_parts.append(f"Height close ({measured_height:.1f}mm vs {gt_height:.1f}mm)")
        else:
            feedback_parts.append(f"Height incorrect ({measured_height:.1f}mm vs {gt_height:.1f}mm)")
    elif measured_height is not None:
        if _is_plausible(measured_height, dim_range):
            score += w_height * 0.3
            feedback_parts.append(f"Height plausible ({measured_height:.1f}mm)")
        else:
            feedback_parts.append(f"Height implausible ({measured_height:.1f}mm)")
    else:
        feedback_parts.append("Height not measured")
    
    details['height_correct'] = height_correct
    
    # ================================================================
    # CRITERION 6: Bounding volume correct (10 points)
    # ================================================================
    volume_correct = False
    
    # Calculate expected volume from measured dimensions
    if measured_width and measured_depth and measured_height:
        calculated_volume = measured_width * measured_depth * measured_height
        
        if measured_volume is not None:
            # Check if reported volume matches calculation
            if _is_within_tolerance(measured_volume, calculated_volume, 5):
                score += w_volume
                volume_correct = True
                feedback_parts.append(f"Volume calc OK ({measured_volume:.0f}mm³)")
            else:
                feedback_parts.append(f"Volume calc error")
        else:
            # Volume not reported but dimensions are
            score += w_volume * 0.5
            feedback_parts.append("Volume not reported")
    else:
        feedback_parts.append("Cannot calculate volume")
    
    details['volume_correct'] = volume_correct
    
    # ================================================================
    # CRITERION 7: Segmentation exists (5 points)
    # ================================================================
    seg_exists = result.get('segmentation_exists', False)
    
    if seg_exists:
        score += w_seg
        feedback_parts.append("Segmentation created")
    else:
        feedback_parts.append("No segmentation found")
    
    details['segmentation_exists'] = seg_exists
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    dimensions_correct = sum([width_correct, depth_correct, height_correct])
    
    # Pass requires: file created AND at least 2 of 3 dimensions correct
    key_criteria_met = output_exists and dimensions_correct >= 2
    passed = score >= 65 and key_criteria_met
    
    details['dimensions_correct_count'] = dimensions_correct
    details['key_criteria_met'] = key_criteria_met
    
    # Final feedback
    feedback = " | ".join(feedback_parts[:8])  # Limit feedback length
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }


def _parse_float(value):
    """Safely parse a float from string."""
    if value is None or value == '':
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def _is_within_tolerance(measured, expected, tolerance_pct):
    """Check if measured value is within tolerance of expected."""
    if expected is None or expected == 0:
        return False
    tolerance = expected * (tolerance_pct / 100.0)
    return abs(measured - expected) <= tolerance


def _is_plausible(value, dim_range):
    """Check if value is within plausible anatomical range."""
    return dim_range['min'] <= value <= dim_range['max']