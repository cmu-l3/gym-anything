#!/usr/bin/env python3
"""
Verifier for Renal Cyst Bosniak Classification task.

VERIFICATION CRITERIA:
1. Cyst Located (15 pts): Measurements placed in correct anatomical region
2. Diameter Accuracy (20 pts): Within tolerance of ground truth
3. HU Measurement (20 pts): Internal density measurement accurate
4. Bosniak Category (25 pts): Correct classification
5. Reference HU (5 pts): Measured normal parenchyma
6. Report Complete (10 pts): All required fields present
7. Recommendation (5 pts): Appropriate for category

Pass threshold: 60 points with Bosniak Category correct or adjacent
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types."""
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


def load_json_safely(filepath):
    """Load JSON file with error handling."""
    if not os.path.exists(filepath):
        return None, f"File not found: {filepath}"
    try:
        with open(filepath, 'r') as f:
            return json.load(f), None
    except json.JSONDecodeError as e:
        return None, f"Invalid JSON: {e}"
    except Exception as e:
        return None, f"Error reading: {e}"


def verify_diameter_accuracy(agent_diameter, gt_diameter, tolerance_mm=3.0):
    """Verify diameter measurement accuracy."""
    if agent_diameter is None or gt_diameter is None:
        return False, 0, "Missing diameter data"
    
    try:
        agent_val = float(agent_diameter)
        gt_val = float(gt_diameter)
    except (ValueError, TypeError):
        return False, 0, "Invalid diameter values"
    
    error = abs(agent_val - gt_val)
    
    if error <= tolerance_mm:
        return True, error, f"Diameter accurate: {agent_val:.1f}mm (GT: {gt_val:.1f}mm, error: {error:.1f}mm)"
    else:
        return False, error, f"Diameter inaccurate: {agent_val:.1f}mm (GT: {gt_val:.1f}mm, error: {error:.1f}mm)"


def verify_hu_measurement(agent_hu, gt_hu, tolerance=10.0):
    """Verify HU measurement accuracy."""
    if agent_hu is None or gt_hu is None:
        return False, 0, "Missing HU data"
    
    try:
        agent_val = float(agent_hu)
        gt_val = float(gt_hu)
    except (ValueError, TypeError):
        return False, 0, "Invalid HU values"
    
    error = abs(agent_val - gt_val)
    
    if error <= tolerance:
        return True, error, f"HU accurate: {agent_val:.1f} (GT: {gt_val:.1f}, error: {error:.1f})"
    else:
        return False, error, f"HU inaccurate: {agent_val:.1f} (GT: {gt_val:.1f}, error: {error:.1f})"


def verify_bosniak_classification(agent_category, gt_category):
    """Verify Bosniak classification accuracy."""
    valid_categories = ["I", "II", "IIF", "III", "IV"]
    cat_order = ["I", "II", "IIF", "III", "IV"]
    
    if not agent_category:
        return False, False, "No classification provided"
    
    # Normalize
    agent_cat = str(agent_category).upper().strip()
    gt_cat = str(gt_category).upper().strip()
    
    if agent_cat not in valid_categories:
        return False, False, f"Invalid category: {agent_category}"
    
    if agent_cat == gt_cat:
        return True, False, f"Correct classification: Bosniak {agent_cat}"
    
    # Check for adjacent category (partial credit)
    try:
        agent_idx = cat_order.index(agent_cat)
        gt_idx = cat_order.index(gt_cat)
        if abs(agent_idx - gt_idx) == 1:
            return False, True, f"Adjacent category: {agent_cat} vs GT {gt_cat}"
    except ValueError:
        pass
    
    return False, False, f"Incorrect: {agent_cat} vs GT {gt_cat}"


def verify_report_completeness(report):
    """Check report has all required fields."""
    required_fields = [
        "cyst_location",
        "max_diameter_mm",
        "internal_hu_mean",
        "bosniak_category",
        "recommendation"
    ]
    
    if not isinstance(report, dict):
        return 0, len(required_fields), "Report is not a valid JSON object"
    
    present = 0
    missing = []
    for field in required_fields:
        if field in report and report[field] is not None:
            present += 1
        else:
            missing.append(field)
    
    if missing:
        msg = f"Report: {present}/{len(required_fields)} fields (missing: {', '.join(missing)})"
    else:
        msg = f"Report complete: {present}/{len(required_fields)} fields"
    
    return present, len(required_fields), msg


def verify_recommendation_consistency(category, recommendation):
    """Check if recommendation matches Bosniak category."""
    if not category or not recommendation:
        return False, "Missing category or recommendation"
    
    category = str(category).upper().strip()
    rec_lower = str(recommendation).lower()
    
    expected_keywords = {
        "I": ["benign", "no follow", "no further", "simple"],
        "II": ["benign", "no follow", "no further", "minimal"],
        "IIF": ["follow", "surveillance", "monitor", "6", "12", "indeterminate"],
        "III": ["surg", "excis", "biops", "indeterminate", "resect"],
        "IV": ["surg", "excis", "malignant", "resect", "cancer"]
    }
    
    if category not in expected_keywords:
        return False, f"Unknown category: {category}"
    
    keywords = expected_keywords[category]
    if any(kw in rec_lower for kw in keywords):
        return True, f"Recommendation consistent with {category}"
    else:
        return False, f"Recommendation may not match {category}"


def verify_renal_cyst_bosniak(traj, env_info, task_info):
    """
    Main verification function for Renal Cyst Bosniak Classification task.
    
    Returns:
        dict with 'passed', 'score', 'feedback' keys
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
    
    diameter_tolerance = thresholds.get('diameter_tolerance_mm', 3.0)
    hu_tolerance = thresholds.get('hu_tolerance', 10.0)
    
    w_located = weights.get('cyst_located', 15)
    w_diameter = weights.get('diameter_accuracy', 20)
    w_hu = weights.get('hu_measurement', 20)
    w_category = weights.get('bosniak_category', 25)
    w_ref_hu = weights.get('reference_hu', 5)
    w_report = weights.get('report_complete', 10)
    w_rec = weights.get('recommendation', 5)
    
    feedback_parts = []
    details = {}
    score = 0
    
    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        result, err = load_json_safely(temp_result.name)
        if err:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {err}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - task not attempted"
        }
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/cyst_ground_truth.json", temp_gt.name)
        gt, err = load_json_safely(temp_gt.name)
        if err:
            details['gt_error'] = err
    except Exception as e:
        details['gt_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    if not gt:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Ground truth not available - setup error"
        }
    
    gt_diameter = gt.get('max_diameter_mm', 0)
    gt_hu = gt.get('internal_hu_mean', 0)
    gt_category = gt.get('bosniak_category', '')
    gt_ref_hu = gt.get('reference_parenchyma_hu', 35)
    
    details['ground_truth'] = {
        'diameter_mm': gt_diameter,
        'internal_hu': gt_hu,
        'bosniak_category': gt_category
    }
    
    # Extract agent's report
    agent_report = result.get('agent_report', {})
    if isinstance(agent_report, str):
        try:
            agent_report = json.loads(agent_report)
        except:
            agent_report = {}
    
    # ================================================================
    # CRITERION 1: Cyst Located (15 points)
    # ================================================================
    cyst_located = False
    markups_created = result.get('markups_created_during_task', False)
    report_created = result.get('report_created_during_task', False)
    
    if markups_created or report_created:
        if agent_report.get('cyst_location'):
            cyst_located = True
            score += w_located
            feedback_parts.append(f"Cyst located: {agent_report.get('cyst_location')}")
            details['cyst_located'] = w_located
        elif result.get('markups_exist'):
            cyst_located = True
            score += int(w_located * 0.7)
            feedback_parts.append("Markups placed (location not specified)")
            details['cyst_located'] = int(w_located * 0.7)
    
    if not cyst_located:
        feedback_parts.append("Cyst not located")
        details['cyst_located'] = 0
    
    # ================================================================
    # CRITERION 2: Diameter Accuracy (20 points)
    # ================================================================
    agent_diameter = agent_report.get('max_diameter_mm')
    
    if agent_diameter is not None and gt_diameter:
        accurate, error_mm, msg = verify_diameter_accuracy(agent_diameter, gt_diameter, diameter_tolerance)
        feedback_parts.append(msg)
        
        if accurate:
            score += w_diameter
            details['diameter_accuracy'] = w_diameter
        elif error_mm <= diameter_tolerance * 2:
            partial = int(w_diameter * (1 - error_mm / (diameter_tolerance * 2)))
            score += partial
            details['diameter_accuracy'] = partial
        else:
            details['diameter_accuracy'] = 0
    else:
        feedback_parts.append("Diameter not measured")
        details['diameter_accuracy'] = 0
    
    # ================================================================
    # CRITERION 3: HU Measurement (20 points)
    # ================================================================
    agent_hu = agent_report.get('internal_hu_mean')
    
    if agent_hu is not None and gt_hu:
        accurate, error_hu, msg = verify_hu_measurement(agent_hu, gt_hu, hu_tolerance)
        feedback_parts.append(msg)
        
        if accurate:
            score += w_hu
            details['hu_measurement'] = w_hu
        elif error_hu <= hu_tolerance * 2:
            partial = int(w_hu * (1 - error_hu / (hu_tolerance * 2)))
            score += partial
            details['hu_measurement'] = partial
        else:
            details['hu_measurement'] = 0
    else:
        feedback_parts.append("HU not measured")
        details['hu_measurement'] = 0
    
    # ================================================================
    # CRITERION 4: Bosniak Category (25 points)
    # ================================================================
    agent_category = agent_report.get('bosniak_category')
    
    correct, adjacent, msg = verify_bosniak_classification(agent_category, gt_category)
    feedback_parts.append(msg)
    
    if correct:
        score += w_category
        details['bosniak_category'] = w_category
    elif adjacent:
        partial = int(w_category * 0.5)
        score += partial
        details['bosniak_category'] = partial
    else:
        details['bosniak_category'] = 0
    
    # ================================================================
    # CRITERION 5: Reference HU (5 points)
    # ================================================================
    ref_hu = agent_report.get('reference_parenchyma_hu')
    
    if ref_hu is not None:
        try:
            ref_val = float(ref_hu)
            # Kidney parenchyma typically 30-50 HU on non-contrast
            if 20 <= ref_val <= 100:
                score += w_ref_hu
                feedback_parts.append(f"Reference HU measured: {ref_val:.0f}")
                details['reference_hu'] = w_ref_hu
            else:
                feedback_parts.append(f"Reference HU unlikely: {ref_val:.0f}")
                details['reference_hu'] = 0
        except:
            feedback_parts.append("Invalid reference HU")
            details['reference_hu'] = 0
    else:
        feedback_parts.append("Reference HU not measured")
        details['reference_hu'] = 0
    
    # ================================================================
    # CRITERION 6: Report Complete (10 points)
    # ================================================================
    present, total, msg = verify_report_completeness(agent_report)
    completeness_score = int(w_report * present / total) if total > 0 else 0
    score += completeness_score
    feedback_parts.append(msg)
    details['report_complete'] = completeness_score
    
    # ================================================================
    # CRITERION 7: Recommendation (5 points)
    # ================================================================
    recommendation = agent_report.get('recommendation', '')
    
    if agent_category and recommendation:
        consistent, msg = verify_recommendation_consistency(agent_category, recommendation)
        feedback_parts.append(msg)
        if consistent:
            score += w_rec
            details['recommendation'] = w_rec
        else:
            details['recommendation'] = 0
    else:
        feedback_parts.append("Missing recommendation")
        details['recommendation'] = 0
    
    # ================================================================
    # Final assessment
    # ================================================================
    
    # Anti-gaming check
    task_start = result.get('task_start_time', 0)
    export_time = result.get('export_time', 0)
    if task_start > 0 and export_time > 0:
        elapsed = export_time - task_start
        if elapsed < 30:
            feedback_parts.append(f"WARNING: Task completed in {elapsed}s (suspiciously fast)")
            details['timing_warning'] = True
    
    # Pass requires >= 60 points AND at least partial credit on Bosniak category
    bosniak_score = details.get('bosniak_category', 0)
    passed = score >= 60 and bosniak_score > 0
    
    details['total_score'] = score
    details['passed'] = passed
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    })


if __name__ == "__main__":
    # Test mode
    print("Renal Cyst Bosniak Classification Verifier")
    print("Run with framework to execute verification")