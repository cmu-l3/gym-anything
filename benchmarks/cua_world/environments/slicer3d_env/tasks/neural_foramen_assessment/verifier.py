#!/usr/bin/env python3
"""
Verifier for neural foramen stenosis assessment task.

VERIFICATION CRITERIA:
1. Level Identification (15 pts): Measurements at correct L4-L5 and L5-S1 levels
2. Height Accuracy L4-L5 (15 pts): Both sides within ±3mm of ground truth
3. Height Accuracy L5-S1 (15 pts): Both sides within ±3mm of ground truth
4. Width Measurements (10 pts): At least 2 of 4 width measurements within ±2mm
5. Bilateral Coverage (10 pts): All four foramina measured
6. Stenosis Grading (15 pts): Correct grade for at least 3 of 4 foramina
7. Area Calculations (5 pts): Mathematically correct area approximations
8. Report Completeness (10 pts): JSON contains all required fields
9. Clinical Impression (5 pts): Impression consistent with measurements

Pass Threshold: 60 points with level identification achieved
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


def grade_from_height(height_mm):
    """Calculate stenosis grade from foraminal height."""
    if height_mm >= 15:
        return 0  # Normal
    elif height_mm >= 10:
        return 1  # Mild
    elif height_mm >= 5:
        return 2  # Moderate
    else:
        return 3  # Severe


def normalize_key(key):
    """Normalize foramen key to standard format."""
    key = key.lower().replace("-", "").replace("_", "").replace(" ", "")
    # Map common variations
    mappings = {
        "l4l5left": "L4L5_left",
        "l4l5right": "L4L5_right",
        "l5s1left": "L5S1_left",
        "l5s1right": "L5S1_right",
        "l45left": "L4L5_left",
        "l45right": "L4L5_right",
        "l51left": "L5S1_left",
        "l51right": "L5S1_right",
    }
    return mappings.get(key, key)


def extract_report_values(report_data):
    """Extract foramen measurements from various report formats."""
    extracted = {}
    standard_keys = ["L4L5_left", "L4L5_right", "L5S1_left", "L5S1_right"]
    
    for key in standard_keys:
        extracted[key] = {"height_mm": None, "width_mm": None, "grade": None, "area_mm2": None}
    
    # Try to find each foramen in the report
    for orig_key, value in report_data.items():
        norm_key = normalize_key(orig_key)
        if norm_key in standard_keys and isinstance(value, dict):
            if "height_mm" in value or "height" in value:
                extracted[norm_key]["height_mm"] = value.get("height_mm", value.get("height"))
            if "width_mm" in value or "width" in value:
                extracted[norm_key]["width_mm"] = value.get("width_mm", value.get("width"))
            if "grade" in value:
                extracted[norm_key]["grade"] = value.get("grade")
            if "area_mm2" in value or "area" in value:
                extracted[norm_key]["area_mm2"] = value.get("area_mm2", value.get("area"))
    
    return extracted


def verify_neural_foramen_assessment(traj, env_info, task_info):
    """
    Verify neural foramen assessment task completion.
    
    Scoring (100 points total):
    - Level identification: 15 points
    - Height accuracy L4-L5: 15 points
    - Height accuracy L5-S1: 15 points
    - Width measurements: 10 points
    - Bilateral coverage: 10 points
    - Stenosis grading: 15 points
    - Area calculations: 5 points
    - Report completeness: 10 points
    - Clinical impression: 5 points
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
    
    height_error_max = thresholds.get('height_error_max_mm', 3.0)
    width_error_max = thresholds.get('width_error_max_mm', 2.0)
    grade_tolerance = thresholds.get('grade_tolerance', 1)
    
    # Scoring weights
    w_level = weights.get('level_identification', 15)
    w_height_l4l5 = weights.get('height_accuracy_l4l5', 15)
    w_height_l5s1 = weights.get('height_accuracy_l5s1', 15)
    w_width = weights.get('width_measurements', 10)
    w_bilateral = weights.get('bilateral_coverage', 10)
    w_grading = weights.get('stenosis_grading', 15)
    w_area = weights.get('area_calculations', 5)
    w_report = weights.get('report_completeness', 10)
    w_impression = weights.get('clinical_impression', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/foramen_task_result.json", temp_result.name)
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
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/foramen_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    details['ground_truth'] = to_python_type(gt_data)
    
    # ============================================================
    # LOAD AGENT'S REPORT
    # ============================================================
    agent_report = {}
    if result.get('report_exists', False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_foramen_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                agent_report = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load agent report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    
    details['agent_report'] = to_python_type(agent_report)
    
    # Extract measurements from report
    agent_values = extract_report_values(agent_report)
    details['extracted_values'] = to_python_type(agent_values)
    
    standard_keys = ["L4L5_left", "L4L5_right", "L5S1_left", "L5S1_right"]
    
    # ============================================================
    # CRITERION 1: Level Identification (15 pts)
    # Check if measurements are at correct levels
    # ============================================================
    levels_identified = 0
    for key in standard_keys:
        if agent_values.get(key, {}).get('height_mm') is not None:
            levels_identified += 1
    
    if levels_identified >= 4:
        score += w_level
        feedback_parts.append(f"✓ All foramen levels identified ({levels_identified}/4)")
        level_id_passed = True
    elif levels_identified >= 2:
        partial = int(w_level * levels_identified / 4)
        score += partial
        feedback_parts.append(f"◐ Partial level identification ({levels_identified}/4, +{partial}pts)")
        level_id_passed = True
    else:
        feedback_parts.append(f"✗ Insufficient level identification ({levels_identified}/4)")
        level_id_passed = False
    
    details['levels_identified'] = levels_identified
    
    # ============================================================
    # CRITERION 2: Height Accuracy L4-L5 (15 pts)
    # ============================================================
    l4l5_height_correct = 0
    l4l5_height_details = []
    
    for side in ["left", "right"]:
        key = f"L4L5_{side}"
        gt_h = gt_data.get(key, {}).get('height_mm')
        agent_h = agent_values.get(key, {}).get('height_mm')
        
        if gt_h is not None and agent_h is not None:
            try:
                error = abs(float(agent_h) - float(gt_h))
                l4l5_height_details.append(f"{side}: agent={agent_h:.1f}mm, gt={gt_h:.1f}mm, err={error:.1f}mm")
                if error <= height_error_max:
                    l4l5_height_correct += 1
            except (ValueError, TypeError):
                l4l5_height_details.append(f"{side}: invalid value")
    
    if l4l5_height_correct >= 2:
        score += w_height_l4l5
        feedback_parts.append(f"✓ L4-L5 heights accurate ({l4l5_height_correct}/2)")
    elif l4l5_height_correct == 1:
        score += int(w_height_l4l5 / 2)
        feedback_parts.append(f"◐ L4-L5 heights partial ({l4l5_height_correct}/2)")
    else:
        feedback_parts.append(f"✗ L4-L5 heights inaccurate")
    
    details['l4l5_height'] = l4l5_height_details
    
    # ============================================================
    # CRITERION 3: Height Accuracy L5-S1 (15 pts)
    # ============================================================
    l5s1_height_correct = 0
    l5s1_height_details = []
    
    for side in ["left", "right"]:
        key = f"L5S1_{side}"
        gt_h = gt_data.get(key, {}).get('height_mm')
        agent_h = agent_values.get(key, {}).get('height_mm')
        
        if gt_h is not None and agent_h is not None:
            try:
                error = abs(float(agent_h) - float(gt_h))
                l5s1_height_details.append(f"{side}: agent={agent_h:.1f}mm, gt={gt_h:.1f}mm, err={error:.1f}mm")
                if error <= height_error_max:
                    l5s1_height_correct += 1
            except (ValueError, TypeError):
                l5s1_height_details.append(f"{side}: invalid value")
    
    if l5s1_height_correct >= 2:
        score += w_height_l5s1
        feedback_parts.append(f"✓ L5-S1 heights accurate ({l5s1_height_correct}/2)")
    elif l5s1_height_correct == 1:
        score += int(w_height_l5s1 / 2)
        feedback_parts.append(f"◐ L5-S1 heights partial ({l5s1_height_correct}/2)")
    else:
        feedback_parts.append(f"✗ L5-S1 heights inaccurate")
    
    details['l5s1_height'] = l5s1_height_details
    
    # ============================================================
    # CRITERION 4: Width Measurements (10 pts)
    # ============================================================
    width_correct = 0
    
    for key in standard_keys:
        gt_w = gt_data.get(key, {}).get('width_mm')
        agent_w = agent_values.get(key, {}).get('width_mm')
        
        if gt_w is not None and agent_w is not None:
            try:
                error = abs(float(agent_w) - float(gt_w))
                if error <= width_error_max:
                    width_correct += 1
            except (ValueError, TypeError):
                pass
    
    if width_correct >= 2:
        score += w_width
        feedback_parts.append(f"✓ Width measurements accurate ({width_correct}/4)")
    elif width_correct == 1:
        score += int(w_width / 2)
        feedback_parts.append(f"◐ Width measurements partial ({width_correct}/4)")
    else:
        feedback_parts.append(f"✗ Width measurements inaccurate")
    
    details['width_correct'] = width_correct
    
    # ============================================================
    # CRITERION 5: Bilateral Coverage (10 pts)
    # ============================================================
    foramina_measured = 0
    for key in standard_keys:
        h = agent_values.get(key, {}).get('height_mm')
        if h is not None:
            foramina_measured += 1
    
    if foramina_measured >= 4:
        score += w_bilateral
        feedback_parts.append(f"✓ All 4 foramina measured")
    elif foramina_measured >= 2:
        partial = int(w_bilateral * foramina_measured / 4)
        score += partial
        feedback_parts.append(f"◐ Bilateral coverage partial ({foramina_measured}/4)")
    else:
        feedback_parts.append(f"✗ Insufficient bilateral coverage ({foramina_measured}/4)")
    
    details['foramina_measured'] = foramina_measured
    
    # ============================================================
    # CRITERION 6: Stenosis Grading (15 pts)
    # ============================================================
    grading_correct = 0
    grading_details = []
    
    for key in standard_keys:
        gt_grade = gt_data.get(key, {}).get('grade')
        agent_grade = agent_values.get(key, {}).get('grade')
        
        if gt_grade is not None and agent_grade is not None:
            try:
                gt_g = int(gt_grade)
                agent_g = int(agent_grade)
                diff = abs(agent_g - gt_g)
                grading_details.append(f"{key}: agent={agent_g}, gt={gt_g}")
                if diff <= grade_tolerance:
                    grading_correct += 1
            except (ValueError, TypeError):
                pass
    
    if grading_correct >= 3:
        score += w_grading
        feedback_parts.append(f"✓ Stenosis grading correct ({grading_correct}/4)")
    elif grading_correct >= 2:
        score += int(w_grading * 2 / 3)
        feedback_parts.append(f"◐ Stenosis grading partial ({grading_correct}/4)")
    else:
        feedback_parts.append(f"✗ Stenosis grading incorrect ({grading_correct}/4)")
    
    details['grading'] = grading_details
    details['grading_correct'] = grading_correct
    
    # ============================================================
    # CRITERION 7: Area Calculations (5 pts)
    # ============================================================
    area_correct = 0
    
    for key in standard_keys:
        h = agent_values.get(key, {}).get('height_mm')
        w = agent_values.get(key, {}).get('width_mm')
        area = agent_values.get(key, {}).get('area_mm2')
        
        if h is not None and w is not None and area is not None:
            try:
                expected_area = float(h) * float(w) * 0.785
                error_pct = abs(float(area) - expected_area) / expected_area * 100 if expected_area > 0 else 100
                if error_pct <= 10:  # Within 10% of correct calculation
                    area_correct += 1
            except (ValueError, TypeError, ZeroDivisionError):
                pass
    
    if area_correct >= 2:
        score += w_area
        feedback_parts.append(f"✓ Area calculations correct")
    else:
        feedback_parts.append(f"◐ Area calculations partial or missing")
    
    details['area_correct'] = area_correct
    
    # ============================================================
    # CRITERION 8: Report Completeness (10 pts)
    # ============================================================
    report_fields = 0
    required_fields = ['height_mm', 'width_mm', 'grade']
    
    for key in standard_keys:
        foramen_data = agent_values.get(key, {})
        fields_present = sum(1 for f in required_fields if foramen_data.get(f) is not None)
        if fields_present >= 2:  # At least height and one other
            report_fields += 1
    
    has_impression = 'clinical_impression' in agent_report or 'impression' in agent_report
    
    if report_fields >= 4 and has_impression:
        score += w_report
        feedback_parts.append(f"✓ Report complete with impression")
    elif report_fields >= 3:
        score += int(w_report * 0.7)
        feedback_parts.append(f"◐ Report mostly complete ({report_fields}/4 foramina)")
    elif report_fields >= 1:
        score += int(w_report * 0.3)
        feedback_parts.append(f"◐ Report partial ({report_fields}/4 foramina)")
    else:
        feedback_parts.append(f"✗ Report incomplete")
    
    details['report_fields'] = report_fields
    details['has_impression'] = has_impression
    
    # ============================================================
    # CRITERION 9: Clinical Impression (5 pts)
    # ============================================================
    impression_text = agent_report.get('clinical_impression', agent_report.get('impression', '')).lower()
    expected_impression = gt_data.get('expected_impression', '').lower()
    
    # Check if impression matches severity
    gt_max_grade = max([gt_data.get(k, {}).get('grade', 0) for k in standard_keys])
    
    impression_consistent = False
    if gt_max_grade == 0 and ('normal' in impression_text or 'no significant' in impression_text or 'no stenosis' in impression_text):
        impression_consistent = True
    elif gt_max_grade == 1 and ('mild' in impression_text or 'minimal' in impression_text):
        impression_consistent = True
    elif gt_max_grade == 2 and ('moderate' in impression_text):
        impression_consistent = True
    elif gt_max_grade == 3 and ('severe' in impression_text):
        impression_consistent = True
    
    if impression_text and impression_consistent:
        score += w_impression
        feedback_parts.append(f"✓ Clinical impression consistent")
    elif impression_text:
        score += int(w_impression / 2)
        feedback_parts.append(f"◐ Clinical impression present but may not match findings")
    else:
        feedback_parts.append(f"✗ No clinical impression provided")
    
    details['impression_consistent'] = impression_consistent
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Check anti-gaming: files must be created during task
    created_during_task = result.get('measurement_created_during_task', False) or result.get('report_created_during_task', False)
    
    if not created_during_task and score > 0:
        # Penalize if outputs existed before task
        penalty = 20
        score = max(0, score - penalty)
        feedback_parts.append(f"⚠ Output files may have pre-existed task (-{penalty}pts)")
    
    # Pass requires at least level identification and 60 points
    key_criteria_met = level_id_passed and (l4l5_height_correct + l5s1_height_correct >= 2)
    passed = score >= 60 and key_criteria_met
    
    # Final details
    details['score_breakdown'] = {
        'level_identification': w_level if levels_identified >= 4 else int(w_level * levels_identified / 4),
        'height_l4l5': w_height_l4l5 if l4l5_height_correct >= 2 else int(w_height_l4l5 * l4l5_height_correct / 2),
        'height_l5s1': w_height_l5s1 if l5s1_height_correct >= 2 else int(w_height_l5s1 * l5s1_height_correct / 2),
        'width': w_width if width_correct >= 2 else int(w_width * width_correct / 4),
        'bilateral': w_bilateral if foramina_measured >= 4 else int(w_bilateral * foramina_measured / 4),
        'grading': w_grading if grading_correct >= 3 else int(w_grading * grading_correct / 4),
    }
    
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": min(100, max(0, score)),
        "feedback": feedback,
        "details": details
    })