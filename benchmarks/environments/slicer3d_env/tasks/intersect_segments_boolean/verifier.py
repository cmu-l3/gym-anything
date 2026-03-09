#!/usr/bin/env python3
"""
Verifier for Intersect Segments Boolean task.

VERIFICATION CRITERIA (100 points total):
1. Intersection segment exists (30 points) - segment with appropriate name exists
2. Correct voxel count (25 points) - within tolerance of ground truth
3. Non-empty segment (15 points) - intersection has minimum voxels
4. Bounded by parents (15 points) - intersection <= min(tumor, motor)
5. Parent segments intact (10 points) - original segments unchanged
6. VLM visualization (5 points) - screenshot shows three segments

Pass threshold: 70 points with intersection_exists AND non_empty
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_intersect_segments_boolean(traj, env_info, task_info):
    """
    Verify that segment intersection was created correctly.
    
    Uses multi-criteria scoring with geometric validation.
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
    expected_name = metadata.get('expected_intersection_name', 'Tumor_Motor_Overlap')
    min_voxels = metadata.get('min_intersection_voxels', 100)
    max_voxels = metadata.get('max_intersection_voxels', 50000)
    tolerance_pct = metadata.get('voxel_count_tolerance_percent', 10)
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('intersection_exists', 30)
    w_voxel_count = weights.get('correct_voxel_count', 25)
    w_non_empty = weights.get('non_empty', 15)
    w_bounded = weights.get('bounded_by_parents', 15)
    w_parents = weights.get('parents_intact', 10)
    w_vlm = weights.get('vlm_visualization', 5)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/intersection_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export may have failed"
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
    
    details['export_result'] = result
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - task not completed"
        }
    
    # Check if segmentation was found
    if not result.get('segmentation_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No segmentation found in scene"
        }
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/var/lib/slicer/ground_truth/intersection_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        # Continue without ground truth - use heuristics
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    expected_intersection = gt_data.get('expected_intersection_voxels', 0)
    gt_tumor_voxels = gt_data.get('tumor_voxels', 0)
    gt_motor_voxels = gt_data.get('motor_voxels', 0)
    
    details['ground_truth'] = {
        'expected_intersection': expected_intersection,
        'tumor_voxels': gt_tumor_voxels,
        'motor_voxels': gt_motor_voxels
    }
    
    # ================================================================
    # CRITERION 1: Intersection segment exists (30 points)
    # ================================================================
    intersection_exists = result.get('intersection_segment_exists', False)
    intersection_name = result.get('intersection_segment_name', '')
    segment_names = result.get('segment_names', [])
    
    # Check for intersection segment by name patterns
    name_match = False
    if intersection_exists:
        name_match = True
    else:
        # Check if any segment could be the intersection
        for name in segment_names:
            name_lower = name.lower()
            # Check for expected name patterns
            if any(pattern in name_lower for pattern in ['overlap', 'intersect', 'tumor_motor', 'motor_tumor']):
                intersection_exists = True
                intersection_name = name
                name_match = True
                break
            # Check for newly added segment (not Tumor or Motor_Region)
            if name not in ['Tumor', 'Motor_Region'] and name_lower not in ['tumor', 'motor_region', 'tumorlabelmap', 'motorlabelmap']:
                # This might be the intersection
                if result.get('total_segments', 0) >= 3:
                    intersection_exists = True
                    intersection_name = name
                    break
    
    if intersection_exists:
        score += w_exists
        feedback_parts.append(f"Intersection segment exists: '{intersection_name}'")
        
        # Bonus for correct naming
        if expected_name.lower() in intersection_name.lower():
            feedback_parts.append("Correct name format")
    else:
        feedback_parts.append("Intersection segment NOT found")
        # Early exit - key criterion not met
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    details['intersection_name'] = intersection_name
    
    # ================================================================
    # CRITERION 2: Correct voxel count (25 points)
    # ================================================================
    intersection_voxels = result.get('intersection_voxel_count', 0)
    details['intersection_voxels'] = intersection_voxels
    
    if expected_intersection > 0 and intersection_voxels > 0:
        # Check if within tolerance
        lower_bound = expected_intersection * (1 - tolerance_pct / 100)
        upper_bound = expected_intersection * (1 + tolerance_pct / 100)
        
        if lower_bound <= intersection_voxels <= upper_bound:
            score += w_voxel_count
            feedback_parts.append(f"Voxel count correct ({intersection_voxels} ≈ {expected_intersection})")
        elif intersection_voxels > 0:
            # Partial credit for close values
            error_pct = abs(intersection_voxels - expected_intersection) / expected_intersection * 100
            if error_pct < 30:
                partial = int(w_voxel_count * 0.5)
                score += partial
                feedback_parts.append(f"Voxel count close ({intersection_voxels} vs {expected_intersection})")
            else:
                feedback_parts.append(f"Voxel count differs ({intersection_voxels} vs {expected_intersection})")
    elif intersection_voxels > 0:
        # No ground truth, but segment has voxels
        score += int(w_voxel_count * 0.6)
        feedback_parts.append(f"Intersection has {intersection_voxels} voxels")
    else:
        feedback_parts.append("No voxel count available")
    
    # ================================================================
    # CRITERION 3: Non-empty segment (15 points)
    # ================================================================
    if intersection_voxels >= min_voxels:
        score += w_non_empty
        feedback_parts.append(f"Non-trivial intersection (≥{min_voxels} voxels)")
    elif intersection_voxels > 0:
        score += int(w_non_empty * 0.5)
        feedback_parts.append(f"Small intersection ({intersection_voxels} < {min_voxels})")
    else:
        feedback_parts.append("Empty intersection")
    
    # ================================================================
    # CRITERION 4: Bounded by parents (15 points)
    # ================================================================
    tumor_voxels = result.get('tumor_voxel_count', 0)
    motor_voxels = result.get('motor_voxel_count', 0)
    
    if tumor_voxels > 0 and motor_voxels > 0 and intersection_voxels > 0:
        max_possible = min(tumor_voxels, motor_voxels)
        if intersection_voxels <= max_possible:
            score += w_bounded
            feedback_parts.append("Intersection bounded correctly")
        else:
            feedback_parts.append(f"Intersection too large ({intersection_voxels} > {max_possible})")
    elif intersection_voxels > 0 and intersection_voxels <= max_voxels:
        # Can't verify exactly but within reasonable bounds
        score += int(w_bounded * 0.5)
        feedback_parts.append("Size appears reasonable")
    
    details['tumor_voxels'] = tumor_voxels
    details['motor_voxels'] = motor_voxels
    
    # ================================================================
    # CRITERION 5: Parent segments intact (10 points)
    # ================================================================
    tumor_exists = result.get('tumor_segment_exists', False)
    motor_exists = result.get('motor_segment_exists', False)
    
    parents_intact = True
    
    if tumor_exists and motor_exists:
        # Check if parent voxel counts are similar to ground truth
        if gt_tumor_voxels > 0 and tumor_voxels > 0:
            tumor_change = abs(tumor_voxels - gt_tumor_voxels) / gt_tumor_voxels
            if tumor_change > 0.1:  # More than 10% change
                parents_intact = False
                feedback_parts.append("Tumor segment may have been modified")
        
        if gt_motor_voxels > 0 and motor_voxels > 0:
            motor_change = abs(motor_voxels - gt_motor_voxels) / gt_motor_voxels
            if motor_change > 0.1:
                parents_intact = False
                feedback_parts.append("Motor_Region may have been modified")
        
        if parents_intact:
            score += w_parents
            feedback_parts.append("Parent segments intact")
    else:
        if not tumor_exists:
            feedback_parts.append("Tumor segment missing")
        if not motor_exists:
            feedback_parts.append("Motor_Region segment missing")
    
    # ================================================================
    # CRITERION 6: VLM visualization check (5 points)
    # ================================================================
    # Check total segment count as proxy for proper setup
    total_segments = result.get('total_segments', 0)
    if total_segments >= 3:
        score += w_vlm
        feedback_parts.append(f"{total_segments} segments in scene")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_exists + w_voxel_count + w_non_empty + w_bounded + w_parents + w_vlm
    
    # Key criteria check
    key_criteria_met = (
        intersection_exists and 
        intersection_voxels >= min_voxels
    )
    
    # Pass threshold: 70 points AND key criteria
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }