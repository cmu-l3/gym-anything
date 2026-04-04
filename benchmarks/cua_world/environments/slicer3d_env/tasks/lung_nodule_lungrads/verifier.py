#!/usr/bin/env python3
"""
Verifier for Lung Nodule Measurement and Lung-RADS Classification task.

VERIFICATION STRATEGY:
1. Measurement accuracy - compare agent's diameter to ground truth (40 pts)
2. Measurement created - valid ruler/line markup exists (15 pts)
3. Measurement location - ruler is near the nodule (10 pts)
4. Classification correct - Lung-RADS category matches measured size (20 pts)
5. Report complete - JSON with required fields (10 pts)
6. Reasonable range - measurement is anatomically plausible (5 pts)

Lung-RADS Criteria:
- Category 2: < 6mm
- Category 3: 6-8mm  
- Category 4A: 8-15mm
- Category 4B: >= 15mm

Pass threshold: 60 points with measurement accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging
import math
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    try:
        import numpy as np
        if isinstance(val, (np.integer, np.int32, np.int64)):
            return int(val)
        elif isinstance(val, (np.floating, np.float32, np.float64)):
            return float(val)
        elif isinstance(val, np.ndarray):
            return val.tolist()
        elif isinstance(val, np.bool_):
            return bool(val)
    except ImportError:
        pass
    
    if isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def get_lungrads_category(diameter_mm: float) -> str:
    """
    Determine Lung-RADS category based on nodule diameter.
    
    Args:
        diameter_mm: Nodule longest diameter in millimeters
        
    Returns:
        Lung-RADS category string: "2", "3", "4A", or "4B"
    """
    if diameter_mm < 6.0:
        return "2"
    elif diameter_mm < 8.0:
        return "3"
    elif diameter_mm < 15.0:
        return "4A"
    else:
        return "4B"


def calculate_distance_3d(p1: list, p2: list) -> float:
    """Calculate Euclidean distance between two 3D points."""
    if not p1 or not p2 or len(p1) < 3 or len(p2) < 3:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1[:3], p2[:3])))


def parse_coordinate_string(coord_str: str) -> Optional[list]:
    """Parse a coordinate string like '[1.0, 2.0, 3.0]' into a list."""
    if not coord_str or coord_str == "null":
        return None
    try:
        if isinstance(coord_str, list):
            return coord_str
        # Handle string representation
        coord_str = coord_str.strip()
        if coord_str.startswith('[') and coord_str.endswith(']'):
            return json.loads(coord_str)
        return None
    except (json.JSONDecodeError, ValueError):
        return None


def verify_lung_nodule_lungrads(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify lung nodule measurement and Lung-RADS classification.
    
    Scoring (100 points total):
    - Measurement accuracy: 40 points (within 3mm of ground truth)
    - Measurement created: 15 points (valid line markup exists)
    - Measurement location: 10 points (ruler near nodule center)
    - Classification correct: 20 points (Lung-RADS matches measured size)
    - Report complete: 10 points (JSON with all required fields)
    - Reasonable range: 5 points (2-50mm, anatomically plausible)
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
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    diameter_error_max = thresholds.get('diameter_error_max_mm', 3.0)
    location_error_max = thresholds.get('location_error_max_mm', 15.0)
    
    w_accuracy = weights.get('measurement_accuracy', 40)
    w_created = weights.get('measurement_created', 15)
    w_location = weights.get('measurement_location', 10)
    w_classification = weights.get('classification_correct', 20)
    w_report = weights.get('report_complete', 10)
    w_range = weights.get('reasonable_range', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lung_nodule_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # LOAD GROUND TRUTH
    # ============================================================
    gt_diameter = 0.0
    gt_category = ""
    gt_nodule_center = None
    
    # First try from result file
    gt_diameter_str = result.get('ground_truth_diameter_mm', '')
    if gt_diameter_str:
        try:
            gt_diameter = float(gt_diameter_str)
        except (ValueError, TypeError):
            pass
    
    gt_category = result.get('ground_truth_category', '')
    gt_nodule_center = parse_coordinate_string(result.get('ground_truth_nodule_center', ''))
    
    # Try loading ground truth file if values missing
    if not gt_diameter or not gt_category:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/nodule_ground_truth.json", temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                gt_data = json.load(f)
            gt_diameter = gt_data.get('ground_truth_diameter_mm', gt_diameter)
            gt_category = gt_data.get('correct_lungrads_category', gt_category)
            if not gt_nodule_center:
                gt_nodule_center = gt_data.get('nodule_center_ras')
        except Exception as e:
            logger.warning(f"Could not load ground truth file: {e}")
        finally:
            if os.path.exists(temp_gt.name):
                os.unlink(temp_gt.name)
    
    # If still no ground truth, derive category from diameter
    if gt_diameter and not gt_category:
        gt_category = get_lungrads_category(gt_diameter)
    
    details['gt_diameter_mm'] = gt_diameter
    details['gt_category'] = gt_category
    details['gt_nodule_center'] = gt_nodule_center
    
    if not gt_diameter:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Ground truth not available - cannot verify measurements"
        }
    
    # ============================================================
    # CRITERION 1: Measurement Created (15 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if measurement_exists:
        if file_created_during_task:
            score += w_created
            feedback_parts.append(f"✓ Measurement markup created during task (+{w_created})")
        else:
            score += w_created // 2
            feedback_parts.append(f"~ Measurement exists but may be pre-existing (+{w_created // 2})")
        details['measurement_created'] = True
    else:
        feedback_parts.append("✗ No measurement markup found")
        details['measurement_created'] = False
    
    # ============================================================
    # CRITERION 2: Extract Agent's Measurement
    # ============================================================
    agent_diameter = 0.0
    measurement_midpoint = None
    
    # Try measured diameter from export
    measured_str = result.get('measured_diameter_mm', '')
    if measured_str:
        try:
            agent_diameter = float(measured_str)
        except (ValueError, TypeError):
            pass
    
    # Get measurement midpoint for location check
    measurement_midpoint = parse_coordinate_string(result.get('measurement_midpoint_ras', ''))
    
    details['agent_diameter_mm'] = agent_diameter
    details['measurement_midpoint'] = measurement_midpoint
    
    # ============================================================
    # CRITERION 3: Reasonable Range (5 points)
    # ============================================================
    if 2.0 <= agent_diameter <= 50.0:
        score += w_range
        feedback_parts.append(f"✓ Measurement in anatomical range ({agent_diameter:.1f}mm) (+{w_range})")
        details['reasonable_range'] = True
    elif agent_diameter > 0:
        feedback_parts.append(f"✗ Measurement outside typical range ({agent_diameter:.1f}mm)")
        details['reasonable_range'] = False
    else:
        feedback_parts.append("✗ No valid measurement value found")
        details['reasonable_range'] = False
    
    # ============================================================
    # CRITERION 4: Measurement Accuracy (40 points)
    # ============================================================
    diameter_error = abs(agent_diameter - gt_diameter) if agent_diameter > 0 else float('inf')
    details['diameter_error_mm'] = diameter_error
    
    if diameter_error <= diameter_error_max:
        score += w_accuracy
        feedback_parts.append(f"✓ Diameter accurate: {agent_diameter:.1f}mm (GT: {gt_diameter:.1f}mm, error: {diameter_error:.1f}mm) (+{w_accuracy})")
        details['diameter_accurate'] = True
    elif diameter_error <= diameter_error_max * 2:
        partial = w_accuracy // 2
        score += partial
        feedback_parts.append(f"~ Diameter close: {agent_diameter:.1f}mm (GT: {gt_diameter:.1f}mm, error: {diameter_error:.1f}mm) (+{partial})")
        details['diameter_accurate'] = False
    elif agent_diameter > 0:
        feedback_parts.append(f"✗ Diameter inaccurate: {agent_diameter:.1f}mm (GT: {gt_diameter:.1f}mm, error: {diameter_error:.1f}mm)")
        details['diameter_accurate'] = False
    else:
        feedback_parts.append("✗ No diameter measurement to evaluate")
        details['diameter_accurate'] = False
    
    # ============================================================
    # CRITERION 5: Measurement Location (10 points)
    # ============================================================
    if measurement_midpoint and gt_nodule_center:
        location_error = calculate_distance_3d(measurement_midpoint, gt_nodule_center)
        details['location_error_mm'] = location_error
        
        if location_error <= location_error_max:
            score += w_location
            feedback_parts.append(f"✓ Measurement at correct location (error: {location_error:.1f}mm) (+{w_location})")
            details['location_correct'] = True
        elif location_error <= location_error_max * 2:
            partial = w_location // 2
            score += partial
            feedback_parts.append(f"~ Measurement near correct location (error: {location_error:.1f}mm) (+{partial})")
            details['location_correct'] = False
        else:
            feedback_parts.append(f"✗ Measurement far from nodule (error: {location_error:.1f}mm)")
            details['location_correct'] = False
    else:
        feedback_parts.append("~ Cannot verify measurement location (coordinates unavailable)")
        details['location_correct'] = None
    
    # ============================================================
    # CRITERION 6: Classification Correct (20 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    reported_category = result.get('reported_category', '')
    reported_diameter = 0.0
    
    reported_diam_str = result.get('reported_diameter_mm', '')
    if reported_diam_str:
        try:
            reported_diameter = float(reported_diam_str)
        except (ValueError, TypeError):
            pass
    
    details['report_exists'] = report_exists
    details['reported_category'] = reported_category
    details['reported_diameter_mm'] = reported_diameter
    
    # Determine expected category based on agent's measurement (not GT)
    # This tests whether they applied Lung-RADS correctly to their measurement
    if agent_diameter > 0:
        expected_category_from_measurement = get_lungrads_category(agent_diameter)
    else:
        expected_category_from_measurement = gt_category
    
    details['expected_category_from_measurement'] = expected_category_from_measurement
    
    # Normalize category strings for comparison
    reported_category_normalized = reported_category.upper().replace(" ", "").replace("-", "")
    expected_normalized = expected_category_from_measurement.upper().replace(" ", "").replace("-", "")
    gt_normalized = gt_category.upper().replace(" ", "").replace("-", "")
    
    classification_points = 0
    
    if reported_category_normalized == gt_normalized:
        # Exact match with ground truth category
        classification_points = w_classification
        feedback_parts.append(f"✓ Classification correct: {reported_category} (GT: {gt_category}) (+{w_classification})")
    elif reported_category_normalized == expected_normalized:
        # Matches what their measurement would suggest (even if measurement was wrong)
        classification_points = w_classification * 3 // 4
        feedback_parts.append(f"~ Classification consistent with measurement: {reported_category} (+{classification_points})")
    elif reported_category:
        # They provided a category but it's wrong
        feedback_parts.append(f"✗ Classification incorrect: {reported_category} (expected: {gt_category})")
    else:
        feedback_parts.append("✗ No classification provided")
    
    score += classification_points
    details['classification_correct'] = (reported_category_normalized == gt_normalized)
    
    # ============================================================
    # CRITERION 7: Report Complete (10 points)
    # ============================================================
    if report_exists:
        report_fields_present = 0
        if reported_diameter > 0:
            report_fields_present += 1
        if reported_category:
            report_fields_present += 1
        if result.get('reported_recommendation', ''):
            report_fields_present += 1
        
        if report_fields_present >= 3:
            score += w_report
            feedback_parts.append(f"✓ Report complete with all fields (+{w_report})")
            details['report_complete'] = True
        elif report_fields_present >= 2:
            partial = w_report * 2 // 3
            score += partial
            feedback_parts.append(f"~ Report partially complete ({report_fields_present}/3 fields) (+{partial})")
            details['report_complete'] = False
        else:
            partial = w_report // 3
            score += partial
            feedback_parts.append(f"~ Report exists but incomplete ({report_fields_present}/3 fields) (+{partial})")
            details['report_complete'] = False
    else:
        feedback_parts.append("✗ No report file found")
        details['report_complete'] = False
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Key criteria: measurement must be reasonably accurate AND classification provided
    key_criteria_met = (
        diameter_error <= diameter_error_max * 2 and  # Measurement at least close
        measurement_exists and  # Markup exists
        agent_diameter > 0  # Valid measurement
    )
    
    passed = score >= 60 and key_criteria_met
    
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "criteria": {
            "measurement_created": measurement_exists,
            "diameter_error_mm": diameter_error if diameter_error != float('inf') else None,
            "classification_correct": details.get('classification_correct', False),
            "report_complete": details.get('report_complete', False),
            "key_criteria_met": key_criteria_met
        }
    }