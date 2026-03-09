#!/usr/bin/env python3
"""
Verifier for Bone Density HU Screening task.

VERIFICATION STRATEGY:
1. HU Measurement Accuracy (30 pts) - within tolerance of ground truth
2. Classification Correct (20 pts) - matches expected category
3. ROI Placement Quality (15 pts) - ROI file exists and was created during task
4. ROI Area Appropriate (10 pts) - within acceptable range
5. Vertebral Level Correct (10 pts) - T12/L1 or adjacent
6. Report Completeness (10 pts) - all required fields present
7. Screenshot Evidence (5 pts) - visual documentation

Pass threshold: 60 points AND HU measurement accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def classify_bone_density(hu_value: float) -> str:
    """Classify bone density based on HU value."""
    if hu_value > 160:
        return "Normal"
    elif hu_value >= 110:
        return "Osteopenia"
    else:
        return "Osteoporosis"


def verify_bone_density_screening(traj, env_info, task_info):
    """
    Verify bone density HU screening task completion.
    
    Uses copy_from_env to retrieve results from container.
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
    weights = metadata.get('scoring_weights', {})
    hu_tolerance = metadata.get('hu_tolerance', 25)
    exact_levels = metadata.get('exact_levels', ['T12', 'L1'])
    acceptable_levels = metadata.get('acceptable_levels', ['T12', 'L1', 'T11', 'L2'])
    roi_area_min = metadata.get('roi_area_min_mm2', 80)
    roi_area_max = metadata.get('roi_area_max_mm2', 300)
    
    w_hu = weights.get('hu_measurement_accuracy', 30)
    w_class = weights.get('classification_correct', 20)
    w_roi_placement = weights.get('roi_placement_quality', 15)
    w_roi_area = weights.get('roi_area_appropriate', 10)
    w_level = weights.get('vertebral_level_correct', 10)
    w_report = weights.get('report_completeness', 10)
    w_screenshot = weights.get('screenshot_evidence', 5)
    
    # Load result data from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
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
    
    logger.info(f"Result data: {json.dumps(result, indent=2)}")
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/bone_density_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Extract ground truth values
    t12_gt = gt_data.get('t12', {})
    l1_gt = gt_data.get('l1', {})
    gt_tolerance = gt_data.get('tolerance_hu', hu_tolerance)
    
    t12_hu = t12_gt.get('trabecular_hu') if t12_gt else None
    l1_hu = l1_gt.get('trabecular_hu') if l1_gt else None
    t12_class = t12_gt.get('classification', '') if t12_gt else ''
    l1_class = l1_gt.get('classification', '') if l1_gt else ''
    
    logger.info(f"Ground truth: T12 HU={t12_hu}, L1 HU={l1_hu}")
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {
        "ground_truth": {
            "t12_hu": t12_hu,
            "l1_hu": l1_hu,
            "t12_classification": t12_class,
            "l1_classification": l1_class
        }
    }
    
    # Check basic requirements
    slicer_running = result.get('slicer_was_running', False)
    report_valid = result.get('report_valid', False)
    report_created = result.get('report_created_during_task', False)
    
    if not slicer_running:
        feedback_parts.append("WARNING: Slicer was not running at export")
    
    if not report_valid:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No valid report file found. Agent must create bone_density_report.json with required fields.",
            "details": details
        }
    
    # Parse agent values
    try:
        agent_hu_str = result.get('agent_mean_hu', '')
        agent_hu = float(agent_hu_str) if agent_hu_str else 0.0
    except (ValueError, TypeError):
        agent_hu = 0.0
    
    agent_classification = result.get('agent_classification', '').strip()
    agent_level = result.get('agent_vertebral_level', '').strip().upper()
    
    try:
        agent_roi_area_str = result.get('agent_roi_area_mm2', '')
        agent_roi_area = float(agent_roi_area_str) if agent_roi_area_str else 0.0
    except (ValueError, TypeError):
        agent_roi_area = 0.0
    
    details['agent_measurements'] = {
        'mean_hu': agent_hu,
        'classification': agent_classification,
        'vertebral_level': agent_level,
        'roi_area_mm2': agent_roi_area
    }
    
    logger.info(f"Agent measurements: HU={agent_hu}, Class={agent_classification}, Level={agent_level}")
    
    # ================================================================
    # CRITERION 1: HU Measurement Accuracy (30 points)
    # ================================================================
    hu_accurate = False
    hu_points = 0
    
    if agent_hu > 0 and (t12_hu is not None or l1_hu is not None):
        # Check against both T12 and L1
        closest_diff = float('inf')
        matched_level = None
        matched_hu = None
        
        if t12_hu is not None:
            diff = abs(agent_hu - t12_hu)
            if diff < closest_diff:
                closest_diff = diff
                matched_level = "T12"
                matched_hu = t12_hu
        
        if l1_hu is not None:
            diff = abs(agent_hu - l1_hu)
            if diff < closest_diff:
                closest_diff = diff
                matched_level = "L1"
                matched_hu = l1_hu
        
        details['hu_comparison'] = {
            'agent_hu': agent_hu,
            'closest_gt_hu': matched_hu,
            'closest_level': matched_level,
            'difference': closest_diff,
            'tolerance': gt_tolerance
        }
        
        if closest_diff <= gt_tolerance:
            hu_points = w_hu
            hu_accurate = True
            feedback_parts.append(f"✓ HU measurement accurate: {agent_hu:.1f} vs {matched_hu:.1f} (diff: {closest_diff:.1f})")
        elif closest_diff <= gt_tolerance * 1.5:
            hu_points = int(w_hu * 0.6)
            feedback_parts.append(f"~ HU measurement close: {agent_hu:.1f} vs {matched_hu:.1f} (diff: {closest_diff:.1f})")
        elif closest_diff <= gt_tolerance * 2:
            hu_points = int(w_hu * 0.3)
            feedback_parts.append(f"✗ HU measurement outside tolerance: {agent_hu:.1f} vs {matched_hu:.1f} (diff: {closest_diff:.1f})")
        else:
            feedback_parts.append(f"✗ HU measurement inaccurate: {agent_hu:.1f} vs {matched_hu:.1f} (diff: {closest_diff:.1f})")
    elif agent_hu > 0:
        # No ground truth available, give partial credit if measurement is in valid range
        if 50 < agent_hu < 400:
            hu_points = int(w_hu * 0.5)
            feedback_parts.append(f"~ HU measurement {agent_hu:.1f} in valid range (no GT for comparison)")
        else:
            feedback_parts.append(f"✗ HU measurement {agent_hu:.1f} outside valid bone range")
    else:
        feedback_parts.append("✗ No HU measurement provided")
    
    score += hu_points
    
    # ================================================================
    # CRITERION 2: Classification Correct (20 points)
    # ================================================================
    class_points = 0
    valid_classifications = ["Normal", "Osteopenia", "Osteoporosis"]
    
    # Normalize agent classification
    agent_class_normalized = agent_classification.title() if agent_classification else ""
    
    if agent_class_normalized in valid_classifications:
        # Check based on agent's HU value
        expected_class = classify_bone_density(agent_hu) if agent_hu > 0 else ""
        
        # Also check against ground truth classifications
        gt_classifications = []
        if t12_class:
            gt_classifications.append(t12_class)
        if l1_class:
            gt_classifications.append(l1_class)
        
        if agent_class_normalized == expected_class:
            class_points = w_class
            feedback_parts.append(f"✓ Classification correct: {agent_class_normalized}")
        elif agent_class_normalized in gt_classifications:
            class_points = w_class
            feedback_parts.append(f"✓ Classification matches ground truth: {agent_class_normalized}")
        else:
            # Partial credit for valid but potentially wrong classification
            class_points = int(w_class * 0.3)
            feedback_parts.append(f"✗ Classification mismatch: {agent_class_normalized} (expected: {expected_class})")
    else:
        feedback_parts.append(f"✗ Invalid classification: '{agent_classification}'")
    
    score += class_points
    
    # ================================================================
    # CRITERION 3: ROI Placement Quality (15 points)
    # ================================================================
    roi_points = 0
    roi_exists = result.get('roi_file_exists', False)
    roi_created = result.get('roi_created_during_task', False)
    
    if roi_exists and roi_created:
        roi_points = w_roi_placement
        feedback_parts.append("✓ ROI file created during task")
    elif roi_exists:
        roi_points = int(w_roi_placement * 0.5)
        feedback_parts.append("~ ROI file exists (may be pre-existing)")
    else:
        feedback_parts.append("✗ No ROI file found")
    
    score += roi_points
    
    # ================================================================
    # CRITERION 4: ROI Area Appropriate (10 points)
    # ================================================================
    area_points = 0
    
    if agent_roi_area > 0:
        if roi_area_min <= agent_roi_area <= roi_area_max:
            area_points = w_roi_area
            feedback_parts.append(f"✓ ROI area appropriate: {agent_roi_area:.1f} mm²")
        elif roi_area_min * 0.5 <= agent_roi_area <= roi_area_max * 1.5:
            area_points = int(w_roi_area * 0.5)
            feedback_parts.append(f"~ ROI area marginal: {agent_roi_area:.1f} mm² (optimal: {roi_area_min}-{roi_area_max})")
        else:
            feedback_parts.append(f"✗ ROI area inappropriate: {agent_roi_area:.1f} mm²")
    else:
        feedback_parts.append("✗ No ROI area reported")
    
    score += area_points
    
    # ================================================================
    # CRITERION 5: Vertebral Level Correct (10 points)
    # ================================================================
    level_points = 0
    
    if agent_level:
        if agent_level in exact_levels:
            level_points = w_level
            feedback_parts.append(f"✓ Vertebral level correct: {agent_level}")
        elif agent_level in acceptable_levels:
            level_points = int(w_level * 0.5)
            feedback_parts.append(f"~ Vertebral level adjacent: {agent_level} (optimal: T12 or L1)")
        else:
            feedback_parts.append(f"✗ Vertebral level incorrect: {agent_level}")
    else:
        feedback_parts.append("✗ No vertebral level reported")
    
    score += level_points
    
    # ================================================================
    # CRITERION 6: Report Completeness (10 points)
    # ================================================================
    report_points = 0
    required_fields = ['mean_hu', 'classification', 'vertebral_level']
    present_fields = 0
    
    if result.get('agent_mean_hu'):
        present_fields += 1
    if result.get('agent_classification'):
        present_fields += 1
    if result.get('agent_vertebral_level'):
        present_fields += 1
    
    if present_fields == len(required_fields):
        report_points = w_report
        if report_created:
            feedback_parts.append("✓ Report complete with all required fields")
        else:
            report_points = int(w_report * 0.7)
            feedback_parts.append("~ Report complete but may be pre-existing")
    elif present_fields > 0:
        report_points = int(w_report * present_fields / len(required_fields))
        feedback_parts.append(f"~ Report partial: {present_fields}/{len(required_fields)} fields")
    else:
        feedback_parts.append("✗ Report missing required fields")
    
    score += report_points
    
    # ================================================================
    # CRITERION 7: Screenshot Evidence (5 points)
    # ================================================================
    screenshot_points = 0
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_count = result.get('screenshot_count', 0)
    
    if screenshot_count > 0:
        screenshot_points = w_screenshot
        feedback_parts.append(f"✓ Screenshot evidence: {screenshot_count} image(s)")
    elif screenshot_exists:
        screenshot_points = int(w_screenshot * 0.5)
        feedback_parts.append("~ Screenshot may exist")
    else:
        feedback_parts.append("✗ No screenshot evidence")
    
    score += screenshot_points
    
    # ================================================================
    # Final scoring
    # ================================================================
    max_score = w_hu + w_class + w_roi_placement + w_roi_area + w_level + w_report + w_screenshot
    
    # Pass criteria: 60 points AND HU measurement accuracy
    passed = score >= 60 and hu_accurate
    
    details['scoring'] = {
        'hu_measurement': hu_points,
        'classification': class_points,
        'roi_placement': roi_points,
        'roi_area': area_points,
        'vertebral_level': level_points,
        'report_completeness': report_points,
        'screenshot': screenshot_points,
        'total': score,
        'max': max_score
    }
    
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED ({score}/{max_score}) - {feedback}"
    else:
        if not hu_accurate:
            feedback = f"FAILED ({score}/{max_score}) - HU measurement accuracy required to pass | {feedback}"
        else:
            feedback = f"FAILED ({score}/{max_score}) - Score below 60 threshold | {feedback}"
    
    logger.info(f"Final score: {score}/{max_score}, passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }