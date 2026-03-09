#!/usr/bin/env python3
"""
Verifier for Duodenal Diameter Assessment task.

VERIFICATION METRICS (100 points total):
1. Diameter Accuracy (35 pts): Measured diameter within 5mm of ground truth
2. Classification Correct (20 pts): Correct clinical category
3. Measurement Placed (15 pts): Valid ruler markup file exists
4. Location Identified (10 pts): D1-D4 segment correctly identified
5. Measurement Position (10 pts): Measurement value within plausible range
6. Report Completeness (10 pts): JSON report with all required fields

Pass threshold: 60 points with Diameter Accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def classify_diameter(diameter_mm: float) -> str:
    """Classify duodenal diameter based on clinical thresholds."""
    if diameter_mm <= 30:
        return "Normal"
    elif diameter_mm <= 40:
        return "Mildly dilated"
    elif diameter_mm <= 50:
        return "Moderately dilated"
    else:
        return "Severely dilated"


def normalize_classification(classification: str) -> str:
    """Normalize classification string for comparison."""
    if not classification:
        return ""
    c = classification.lower().strip()
    # Handle variations
    if "normal" in c:
        return "normal"
    elif "mild" in c:
        return "mildly dilated"
    elif "moderate" in c:
        return "moderately dilated"
    elif "severe" in c:
        return "severely dilated"
    return c


def verify_duodenal_diameter(traj, env_info, task_info):
    """
    Verify the duodenal diameter assessment task.
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback'
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
    
    diameter_tolerance = thresholds.get('diameter_error_max_mm', 5.0)
    
    w_diameter = weights.get('diameter_accuracy', 35)
    w_classification = weights.get('classification_correct', 20)
    w_measurement = weights.get('measurement_placed', 15)
    w_location = weights.get('location_identified', 10)
    w_position = weights.get('measurement_position', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {
        "criteria": {},
        "ground_truth": {},
        "agent_result": {}
    }
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/duodenal_task_result.json", temp_result.name)
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
    
    details["agent_result"] = result
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env("/tmp/duodenum_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use defaults
        ground_truth = {
            "max_diameter_mm": 28.0,
            "location": "D3",
            "classification": "Normal",
            "tolerance_mm": 5.0
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    details["ground_truth"] = ground_truth
    
    gt_diameter = ground_truth.get('max_diameter_mm', 28.0)
    gt_location = ground_truth.get('location', 'D3')
    gt_classification = ground_truth.get('classification', 'Normal')
    tolerance = ground_truth.get('tolerance_mm', diameter_tolerance)
    
    # ============================================================
    # Get agent's measurements
    # ============================================================
    measured_diameter = 0.0
    try:
        measured_diameter = float(result.get('measured_diameter_mm', 0))
    except (ValueError, TypeError):
        measured_diameter = 0.0
    
    reported_diameter = 0.0
    try:
        reported_diameter = float(result.get('reported_diameter_mm', 0))
    except (ValueError, TypeError):
        reported_diameter = 0.0
    
    # Use measurement if available, else use reported
    agent_diameter = measured_diameter if measured_diameter > 0 else reported_diameter
    
    reported_location = result.get('reported_location', '').upper().strip()
    reported_classification = result.get('reported_classification', '')
    
    # ============================================================
    # CRITERION 1: Diameter Accuracy (35 points)
    # ============================================================
    diameter_error = abs(agent_diameter - gt_diameter) if agent_diameter > 0 else float('inf')
    diameter_accurate = diameter_error <= tolerance
    
    if diameter_accurate:
        score += w_diameter
        details["criteria"]["diameter_accuracy"] = {
            "passed": True,
            "points": w_diameter,
            "details": f"Diameter {agent_diameter:.1f}mm within {tolerance}mm of ground truth {gt_diameter:.1f}mm (error: {diameter_error:.1f}mm)"
        }
        feedback_parts.append(f"✓ Diameter accurate ({agent_diameter:.1f}mm, error {diameter_error:.1f}mm)")
    else:
        details["criteria"]["diameter_accuracy"] = {
            "passed": False,
            "points": 0,
            "details": f"Diameter {agent_diameter:.1f}mm not within {tolerance}mm of ground truth {gt_diameter:.1f}mm (error: {diameter_error:.1f}mm)"
        }
        if agent_diameter > 0:
            feedback_parts.append(f"✗ Diameter inaccurate ({agent_diameter:.1f}mm vs {gt_diameter:.1f}mm)")
        else:
            feedback_parts.append("✗ No diameter measurement found")
    
    # ============================================================
    # CRITERION 2: Classification Correct (20 points)
    # ============================================================
    # Also derive classification from agent's diameter
    agent_classification = classify_diameter(agent_diameter) if agent_diameter > 0 else ""
    
    norm_reported = normalize_classification(reported_classification)
    norm_agent = normalize_classification(agent_classification)
    norm_gt = normalize_classification(gt_classification)
    
    classification_match = (norm_reported == norm_gt or norm_agent == norm_gt)
    
    if classification_match:
        score += w_classification
        details["criteria"]["classification_correct"] = {
            "passed": True,
            "points": w_classification,
            "details": f"Classification matches ground truth '{gt_classification}'"
        }
        feedback_parts.append(f"✓ Classification correct ({gt_classification})")
    else:
        details["criteria"]["classification_correct"] = {
            "passed": False,
            "points": 0,
            "details": f"Classification '{reported_classification}' (derived: '{agent_classification}') does not match '{gt_classification}'"
        }
        feedback_parts.append(f"✗ Classification incorrect (expected {gt_classification})")
    
    # ============================================================
    # CRITERION 3: Measurement Placed (15 points)
    # ============================================================
    measurement_exists = result.get('measurement_file_exists', False)
    measurement_valid = result.get('measurement_valid', False)
    measurement_created = result.get('measurement_created_during_task', False)
    
    if measurement_valid and measurement_created:
        score += w_measurement
        details["criteria"]["measurement_placed"] = {
            "passed": True,
            "points": w_measurement,
            "details": "Valid measurement markup created during task"
        }
        feedback_parts.append("✓ Measurement markup created")
    elif measurement_valid:
        partial = int(w_measurement * 0.7)
        score += partial
        details["criteria"]["measurement_placed"] = {
            "passed": False,
            "points": partial,
            "details": "Measurement exists but may not have been created during task"
        }
        feedback_parts.append("~ Measurement exists (timing uncertain)")
    elif measurement_exists:
        partial = int(w_measurement * 0.4)
        score += partial
        details["criteria"]["measurement_placed"] = {
            "passed": False,
            "points": partial,
            "details": "Measurement file exists but could not extract valid value"
        }
        feedback_parts.append("~ Measurement file exists but invalid")
    else:
        details["criteria"]["measurement_placed"] = {
            "passed": False,
            "points": 0,
            "details": "No measurement markup file found"
        }
        feedback_parts.append("✗ No measurement file")
    
    # ============================================================
    # CRITERION 4: Location Identified (10 points)
    # ============================================================
    valid_locations = ["D1", "D2", "D3", "D4"]
    gt_location_upper = gt_location.upper()
    
    if reported_location in valid_locations:
        if reported_location == gt_location_upper:
            score += w_location
            details["criteria"]["location_identified"] = {
                "passed": True,
                "points": w_location,
                "details": f"Location '{reported_location}' matches ground truth"
            }
            feedback_parts.append(f"✓ Location correct ({reported_location})")
        else:
            # Partial credit for adjacent segment
            gt_idx = valid_locations.index(gt_location_upper) if gt_location_upper in valid_locations else -1
            agent_idx = valid_locations.index(reported_location)
            if gt_idx >= 0 and abs(gt_idx - agent_idx) == 1:
                partial = int(w_location * 0.5)
                score += partial
                details["criteria"]["location_identified"] = {
                    "passed": False,
                    "points": partial,
                    "details": f"Location '{reported_location}' is adjacent to ground truth '{gt_location}'"
                }
                feedback_parts.append(f"~ Location adjacent ({reported_location} vs {gt_location})")
            else:
                details["criteria"]["location_identified"] = {
                    "passed": False,
                    "points": 0,
                    "details": f"Location '{reported_location}' does not match ground truth '{gt_location}'"
                }
                feedback_parts.append(f"✗ Location incorrect ({reported_location} vs {gt_location})")
    else:
        details["criteria"]["location_identified"] = {
            "passed": False,
            "points": 0,
            "details": f"Invalid or missing location (got: '{reported_location}', expected D1-D4)"
        }
        feedback_parts.append("✗ Location not identified")
    
    # ============================================================
    # CRITERION 5: Measurement Position/Plausibility (10 points)
    # ============================================================
    # Check if measurement is within plausible anatomical range
    if measurement_valid and 5 < agent_diameter < 100:
        score += w_position
        details["criteria"]["measurement_position"] = {
            "passed": True,
            "points": w_position,
            "details": f"Measurement value {agent_diameter:.1f}mm is within plausible anatomical range"
        }
        feedback_parts.append("✓ Measurement plausible")
    elif agent_diameter > 0:
        if agent_diameter < 5 or agent_diameter > 100:
            details["criteria"]["measurement_position"] = {
                "passed": False,
                "points": 0,
                "details": f"Measurement value {agent_diameter:.1f}mm outside plausible range (5-100mm)"
            }
            feedback_parts.append("✗ Measurement implausible")
        else:
            score += w_position
            details["criteria"]["measurement_position"] = {
                "passed": True,
                "points": w_position,
                "details": f"Measurement value {agent_diameter:.1f}mm is within plausible range"
            }
            feedback_parts.append("✓ Measurement plausible")
    else:
        details["criteria"]["measurement_position"] = {
            "passed": False,
            "points": 0,
            "details": "No valid measurement to evaluate"
        }
        feedback_parts.append("✗ No measurement to evaluate")
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_file_exists', False)
    report_valid = result.get('report_valid', False)
    report_created = result.get('report_created_during_task', False)
    
    has_diameter = reported_diameter > 0
    has_location = len(reported_location) > 0
    has_classification = len(reported_classification) > 0
    
    fields_present = sum([has_diameter, has_location, has_classification])
    
    if report_valid and report_created and fields_present == 3:
        score += w_report
        details["criteria"]["report_completeness"] = {
            "passed": True,
            "points": w_report,
            "details": "Report contains all required fields and was created during task"
        }
        feedback_parts.append("✓ Report complete")
    elif report_valid and fields_present >= 2:
        partial = int(w_report * fields_present / 3)
        score += partial
        details["criteria"]["report_completeness"] = {
            "passed": False,
            "points": partial,
            "details": f"Report has {fields_present}/3 required fields"
        }
        feedback_parts.append(f"~ Report partial ({fields_present}/3 fields)")
    elif report_exists:
        partial = int(w_report * 0.3)
        score += partial
        details["criteria"]["report_completeness"] = {
            "passed": False,
            "points": partial,
            "details": "Report file exists but missing required fields"
        }
        feedback_parts.append("~ Report exists but incomplete")
    else:
        details["criteria"]["report_completeness"] = {
            "passed": False,
            "points": 0,
            "details": "No report file found"
        }
        feedback_parts.append("✗ No report file")
    
    # ============================================================
    # Final Assessment
    # ============================================================
    max_score = 100
    pass_threshold = 60
    
    # Pass requires 60+ points AND diameter accuracy
    passed = score >= pass_threshold and diameter_accurate
    
    # Generate summary
    if passed:
        summary = f"PASSED with {score}/{max_score} points. Duodenal diameter accurately measured as {agent_diameter:.1f}mm ({gt_classification})."
    elif diameter_accurate and score < pass_threshold:
        summary = f"PARTIAL: Diameter accurate but overall score {score}/{max_score} below threshold of {pass_threshold}."
    elif not diameter_accurate and score >= pass_threshold:
        summary = f"PARTIAL: Score {score}/{max_score} meets threshold but diameter measurement not accurate (error: {diameter_error:.1f}mm)."
    else:
        summary = f"FAILED with {score}/{max_score} points. Primary issue: {'No valid measurement' if agent_diameter <= 0 else f'Diameter error {diameter_error:.1f}mm exceeds {tolerance}mm tolerance'}."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # For testing
    print("Duodenal Diameter Assessment Verifier")
    print("Run via framework for actual verification")