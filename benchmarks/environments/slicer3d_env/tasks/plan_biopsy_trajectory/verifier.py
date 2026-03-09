#!/usr/bin/env python3
"""
Verifier for Plan Biopsy Trajectory task.

VERIFICATION STRATEGY (Multi-criteria scoring):

1. Markup Exists (20 points) - A line/curve markup is present in the scene
2. Correct Name (15 points) - Markup is named "Biopsy_Trajectory" 
3. Has Two Points (15 points) - Line has exactly 2 control points
4. Target Accuracy (25 points) - End point within 15mm of tumor centroid
5. Valid Entry Point (15 points) - Entry is superior to target and outside tumor
6. Reasonable Length (5 points) - Trajectory length is 30-120mm
7. Visual Confirmation (5 points) - Screenshot shows Slicer with content

Pass threshold: 70 points with markup_exists AND has_two_points satisfied

Uses copy_from_env (NOT exec_in_env) for all container data access.
"""

import json
import math
import os
import tempfile
import logging
from typing import Tuple, Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_distance(p1: List[float], p2: List[float]) -> float:
    """Calculate Euclidean distance between two 3D points."""
    if len(p1) < 3 or len(p2) < 3:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1[:3], p2[:3])))


def verify_trajectory_geometry(
    control_points: List[List[float]],
    target_ras: List[float],
    tumor_bounds_min: List[float],
    tumor_bounds_max: List[float],
    target_tolerance: float = 15.0
) -> Dict[str, Any]:
    """
    Verify the trajectory geometry is valid for biopsy planning.
    
    Args:
        control_points: List of [R, A, S] coordinates for each control point
        target_ras: Ground truth tumor centroid in RAS coordinates
        tumor_bounds_min: Minimum tumor bounds in RAS
        tumor_bounds_max: Maximum tumor bounds in RAS
        target_tolerance: Maximum allowed distance from target in mm
    
    Returns:
        Dictionary with geometric validation results
    """
    result = {
        "valid": False,
        "entry_point_ras": None,
        "target_point_ras": None,
        "target_distance_mm": float('inf'),
        "target_within_tolerance": False,
        "trajectory_length_mm": 0,
        "length_valid": False,
        "entry_is_superior": False,
        "entry_outside_tumor": True,
        "feedback": []
    }
    
    if len(control_points) < 2:
        result["feedback"].append(f"Need 2 points, got {len(control_points)}")
        return result
    
    # First point is entry, second is target
    entry_point = control_points[0]
    target_point = control_points[1]
    
    result["entry_point_ras"] = entry_point
    result["target_point_ras"] = target_point
    
    # Calculate distance from agent's target point to ground truth centroid
    target_distance = calculate_distance(target_point, target_ras)
    result["target_distance_mm"] = round(target_distance, 2)
    result["target_within_tolerance"] = target_distance <= target_tolerance
    
    if result["target_within_tolerance"]:
        result["feedback"].append(f"Target accurate ({target_distance:.1f}mm from centroid)")
    else:
        result["feedback"].append(f"Target too far ({target_distance:.1f}mm > {target_tolerance}mm)")
    
    # Calculate trajectory length
    trajectory_length = calculate_distance(entry_point, target_point)
    result["trajectory_length_mm"] = round(trajectory_length, 2)
    result["length_valid"] = 30.0 <= trajectory_length <= 120.0
    
    if result["length_valid"]:
        result["feedback"].append(f"Length OK ({trajectory_length:.1f}mm)")
    else:
        result["feedback"].append(f"Length unusual ({trajectory_length:.1f}mm, expected 30-120mm)")
    
    # Check if entry point is superior to target (higher S coordinate in RAS)
    # In RAS, S is the third coordinate (index 2)
    if len(entry_point) >= 3 and len(target_point) >= 3:
        result["entry_is_superior"] = entry_point[2] > target_point[2]
        if result["entry_is_superior"]:
            result["feedback"].append("Entry is superior to target")
        else:
            result["feedback"].append("Entry should be superior (higher S) than target")
    
    # Check if entry point is outside the tumor bounds
    if len(entry_point) >= 3 and len(tumor_bounds_min) >= 3 and len(tumor_bounds_max) >= 3:
        # Check all axes - need to handle potential coordinate order issues
        in_r = min(tumor_bounds_min[0], tumor_bounds_max[0]) <= entry_point[0] <= max(tumor_bounds_min[0], tumor_bounds_max[0])
        in_a = min(tumor_bounds_min[1], tumor_bounds_max[1]) <= entry_point[1] <= max(tumor_bounds_min[1], tumor_bounds_max[1])
        in_s = min(tumor_bounds_min[2], tumor_bounds_max[2]) <= entry_point[2] <= max(tumor_bounds_min[2], tumor_bounds_max[2])
        
        entry_in_tumor = in_r and in_a and in_s
        result["entry_outside_tumor"] = not entry_in_tumor
        
        if result["entry_outside_tumor"]:
            result["feedback"].append("Entry outside tumor")
        else:
            result["feedback"].append("Entry inside tumor (invalid)")
    
    # Overall validity
    result["valid"] = (
        result["target_within_tolerance"] and 
        result["entry_is_superior"] and 
        result["entry_outside_tumor"]
    )
    
    return result


def verify_plan_biopsy_trajectory(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for biopsy trajectory planning task.
    
    Uses copy_from_env to retrieve result files from container.
    Returns standardized result dictionary with passed, score, and feedback.
    """
    # Get copy function from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    target_tolerance = metadata.get('target_tolerance_mm', 15.0)
    length_range = metadata.get('trajectory_length_range_mm', {"min": 30, "max": 120})
    weights = metadata.get('scoring_weights', {})
    
    # Default weights
    w_markup_exists = weights.get('markup_exists', 20)
    w_correct_name = weights.get('correct_name', 15)
    w_has_two_points = weights.get('has_two_points', 15)
    w_target_accuracy = weights.get('target_accuracy', 25)
    w_valid_entry = weights.get('valid_entry_point', 15)
    w_reasonable_length = weights.get('reasonable_length', 5)
    w_visual = weights.get('visual_confirmation', 5)
    
    # Initialize results
    score = 0
    feedback_parts = []
    details = {
        "checks": {},
        "score_breakdown": {},
        "geometry": {}
    }
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/trajectory_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script may have failed"
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
    
    # ================================================================
    # Check Slicer was running
    # ================================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - task not completed"
        }
    
    # ================================================================
    # Load ground truth
    # ================================================================
    sample_id = result.get('sample_id', 'BraTS2021_00000')
    gt_file = result.get('ground_truth_file', f'/var/lib/slicer/ground_truth/{sample_id}_trajectory_gt.json')
    
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env(gt_file, temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Continue without ground truth - will use heuristics
        details["gt_error"] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    target_ras = gt_data.get('centroid_ras', [0, 0, 0])
    tumor_bounds_min = gt_data.get('tumor_bounds_min_ras', [-100, -100, -100])
    tumor_bounds_max = gt_data.get('tumor_bounds_max_ras', [100, 100, 100])
    
    details["ground_truth"] = {
        "target_ras": target_ras,
        "tumor_bounds_min": tumor_bounds_min,
        "tumor_bounds_max": tumor_bounds_max
    }
    
    # ================================================================
    # CHECK 1: Markup Exists (20 points)
    # ================================================================
    markup_exists = result.get('markup_exists', False)
    details["checks"]["markup_exists"] = markup_exists
    
    if markup_exists:
        score += w_markup_exists
        details["score_breakdown"]["markup_exists"] = w_markup_exists
        feedback_parts.append("✓ Line markup exists")
    else:
        details["score_breakdown"]["markup_exists"] = 0
        feedback_parts.append("✗ No line markup found")
        # Can't continue without markup
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CHECK 2: Correct Name (15 points)
    # ================================================================
    markup_name = result.get('markup_name', '') or ''
    name_lower = markup_name.lower()
    correct_name = 'biopsy' in name_lower and 'trajectory' in name_lower
    
    # Also accept close variations
    if not correct_name:
        correct_name = (
            'biopsy_trajectory' in name_lower or
            'biopsytrajectory' in name_lower or
            ('biopsy' in name_lower and 'traj' in name_lower)
        )
    
    details["checks"]["correct_name"] = correct_name
    details["checks"]["actual_name"] = markup_name
    
    if correct_name:
        score += w_correct_name
        details["score_breakdown"]["correct_name"] = w_correct_name
        feedback_parts.append(f"✓ Name correct: {markup_name}")
    else:
        # Partial credit for any reasonable name
        if markup_name and len(markup_name) > 2:
            partial = w_correct_name // 2
            score += partial
            details["score_breakdown"]["correct_name"] = partial
            feedback_parts.append(f"△ Name '{markup_name}' (expected 'Biopsy_Trajectory')")
        else:
            details["score_breakdown"]["correct_name"] = 0
            feedback_parts.append("✗ Markup not named correctly")
    
    # ================================================================
    # CHECK 3: Has 2 Control Points (15 points)
    # ================================================================
    num_points = result.get('num_control_points', 0)
    has_two_points = num_points == 2
    
    details["checks"]["has_two_points"] = has_two_points
    details["checks"]["num_control_points"] = num_points
    
    if has_two_points:
        score += w_has_two_points
        details["score_breakdown"]["has_two_points"] = w_has_two_points
        feedback_parts.append("✓ Line has 2 control points")
    else:
        details["score_breakdown"]["has_two_points"] = 0
        feedback_parts.append(f"✗ Expected 2 points, got {num_points}")
        # Can't verify trajectory geometry without 2 points
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # Get control points for geometric checks
    # ================================================================
    control_points = result.get('control_points_ras', [])
    
    if len(control_points) >= 2:
        geometry = verify_trajectory_geometry(
            control_points=control_points,
            target_ras=target_ras,
            tumor_bounds_min=tumor_bounds_min,
            tumor_bounds_max=tumor_bounds_max,
            target_tolerance=target_tolerance
        )
        details["geometry"] = geometry
        
        # ================================================================
        # CHECK 4: Target Accuracy (25 points)
        # ================================================================
        target_distance = geometry.get('target_distance_mm', float('inf'))
        
        if geometry.get('target_within_tolerance', False):
            score += w_target_accuracy
            details["score_breakdown"]["target_accuracy"] = w_target_accuracy
            feedback_parts.append(f"✓ Target accurate ({target_distance:.1f}mm)")
        else:
            # Partial credit based on distance
            if target_distance <= 25:
                partial = int(w_target_accuracy * 0.6)
            elif target_distance <= 35:
                partial = int(w_target_accuracy * 0.4)
            elif target_distance <= 50:
                partial = int(w_target_accuracy * 0.2)
            else:
                partial = 0
            
            score += partial
            details["score_breakdown"]["target_accuracy"] = partial
            feedback_parts.append(f"△ Target {target_distance:.1f}mm from centroid")
        
        # ================================================================
        # CHECK 5: Valid Entry Point (15 points)
        # ================================================================
        entry_superior = geometry.get('entry_is_superior', False)
        entry_outside = geometry.get('entry_outside_tumor', True)
        valid_entry = entry_superior and entry_outside
        
        details["checks"]["valid_entry"] = valid_entry
        details["checks"]["entry_is_superior"] = entry_superior
        details["checks"]["entry_outside_tumor"] = entry_outside
        
        if valid_entry:
            score += w_valid_entry
            details["score_breakdown"]["valid_entry"] = w_valid_entry
            feedback_parts.append("✓ Valid entry point")
        elif entry_outside:
            # Partial credit - outside tumor but not superior
            partial = int(w_valid_entry * 0.5)
            score += partial
            details["score_breakdown"]["valid_entry"] = partial
            feedback_parts.append("△ Entry outside tumor but not superior")
        else:
            details["score_breakdown"]["valid_entry"] = 0
            feedback_parts.append("✗ Invalid entry (inside tumor or not superior)")
        
        # ================================================================
        # CHECK 6: Reasonable Length (5 points)
        # ================================================================
        length_valid = geometry.get('length_valid', False)
        trajectory_length = geometry.get('trajectory_length_mm', 0)
        
        details["checks"]["length_valid"] = length_valid
        details["checks"]["trajectory_length_mm"] = trajectory_length
        
        if length_valid:
            score += w_reasonable_length
            details["score_breakdown"]["reasonable_length"] = w_reasonable_length
            feedback_parts.append(f"✓ Length {trajectory_length:.1f}mm")
        else:
            details["score_breakdown"]["reasonable_length"] = 0
            feedback_parts.append(f"△ Length {trajectory_length:.1f}mm (expected 30-120mm)")
    
    # ================================================================
    # CHECK 7: Visual Confirmation (5 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_bytes', 0)
    
    # A real screenshot with Slicer content should be >30KB
    if screenshot_exists and screenshot_size > 30000:
        score += w_visual
        details["score_breakdown"]["visual_confirmation"] = w_visual
        feedback_parts.append("✓ Screenshot captured")
    else:
        details["score_breakdown"]["visual_confirmation"] = 0
        feedback_parts.append("△ Screenshot missing or small")
    
    # ================================================================
    # Final scoring
    # ================================================================
    details["total_score"] = score
    
    # Pass criteria: score >= 70 AND markup exists AND has 2 points
    key_criteria_met = markup_exists and has_two_points
    passed = score >= 70 and key_criteria_met
    
    details["pass_criteria"] = {
        "score_threshold": 70,
        "score_met": score >= 70,
        "key_criteria_met": key_criteria_met,
        "passed": passed
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


# Allow running as standalone script for testing
if __name__ == "__main__":
    import sys
    
    # Mock environment for testing
    print("Plan Biopsy Trajectory Verifier")
    print("=" * 50)
    print("This verifier requires the framework to run properly.")
    print("Use with: verifier.py::verify_plan_biopsy_trajectory")