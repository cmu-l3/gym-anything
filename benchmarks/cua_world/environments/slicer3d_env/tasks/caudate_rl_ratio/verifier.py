#!/usr/bin/env python3
"""
Verifier for Caudate-to-Right-Lobe Ratio task.

VERIFICATION CRITERIA:
1. Caudate width measurement accuracy (±8mm) - 25 points
2. Right lobe width measurement accuracy (±15mm) - 25 points
3. Measurement at correct slice level (±20mm of portal bifurcation) - 15 points
4. Ratio calculation correctness - 10 points
5. Clinical classification correctness - 15 points
6. Report completeness - 10 points

Total: 100 points
Pass threshold: 60 points with at least one accurate measurement
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_caudate_rl_ratio(traj, env_info, task_info):
    """
    Verify the Caudate-RL Ratio task completion.
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with passed, score, feedback
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
    
    CAUDATE_TOLERANCE = thresholds.get('caudate_tolerance_mm', 8.0)
    RIGHTLOBE_TOLERANCE = thresholds.get('rightlobe_tolerance_mm', 15.0)
    SLICE_TOLERANCE = thresholds.get('slice_tolerance_mm', 20.0)
    
    w_caudate = weights.get('caudate_accuracy', 25)
    w_rightlobe = weights.get('rightlobe_accuracy', 25)
    w_level = weights.get('correct_level', 15)
    w_ratio = weights.get('ratio_correct', 10)
    w_classification = weights.get('classification_correct', 15)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/crl_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
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
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # Initialize scoring
    scores = {
        "caudate_accuracy": 0,
        "rightlobe_accuracy": 0,
        "correct_level": 0,
        "ratio_correct": 0,
        "classification_correct": 0,
        "report_completeness": 0
    }
    feedback = []
    
    # Check if Slicer was running
    if not result.get('slicer_running', False):
        feedback.append("FAIL: 3D Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback),
            "scores": scores
        }
    
    # Check if report exists
    report_exists = result.get('report_exists', False)
    if not report_exists:
        feedback.append("FAIL: No report file found")
        # Check for markups at least
        if not result.get('caudate_markup_exists', False):
            feedback.append("FAIL: No caudate measurement markup found")
        if not result.get('rightlobe_markup_exists', False):
            feedback.append("FAIL: No right lobe measurement markup found")
    
    # Parse measurements
    def safe_float(val, default=0.0):
        if val is None or val == "":
            return default
        try:
            return float(val)
        except (ValueError, TypeError):
            return default
    
    agent_caudate = safe_float(result.get('agent_caudate_mm'))
    agent_rightlobe = safe_float(result.get('agent_rightlobe_mm'))
    agent_ratio = safe_float(result.get('agent_ratio'))
    agent_classification = str(result.get('agent_classification', '')).lower()
    agent_slice = safe_float(result.get('agent_slice_mm'))
    
    gt_caudate = safe_float(result.get('gt_caudate_mm'))
    gt_rightlobe = safe_float(result.get('gt_rightlobe_mm'))
    gt_ratio = safe_float(result.get('gt_ratio'))
    gt_classification = str(result.get('gt_classification', '')).lower()
    gt_slice = safe_float(result.get('gt_slice_mm'))
    
    # ============================================================
    # CRITERION 1: Caudate Width Accuracy (25 points)
    # ============================================================
    if gt_caudate > 0 and agent_caudate > 0:
        caudate_error = abs(agent_caudate - gt_caudate)
        if caudate_error <= CAUDATE_TOLERANCE:
            scores["caudate_accuracy"] = w_caudate
            feedback.append(f"PASS: Caudate width accurate ({agent_caudate:.1f}mm vs GT {gt_caudate:.1f}mm, error {caudate_error:.1f}mm)")
        elif caudate_error <= CAUDATE_TOLERANCE * 2:
            scores["caudate_accuracy"] = w_caudate // 2
            feedback.append(f"PARTIAL: Caudate width close ({agent_caudate:.1f}mm vs GT {gt_caudate:.1f}mm, error {caudate_error:.1f}mm)")
        else:
            feedback.append(f"FAIL: Caudate width inaccurate ({agent_caudate:.1f}mm vs GT {gt_caudate:.1f}mm, error {caudate_error:.1f}mm)")
    elif agent_caudate > 0:
        scores["caudate_accuracy"] = w_caudate // 4
        feedback.append(f"PARTIAL: Caudate measured ({agent_caudate:.1f}mm) but no GT for comparison")
    else:
        feedback.append("FAIL: No caudate measurement found")
    
    # ============================================================
    # CRITERION 2: Right Lobe Width Accuracy (25 points)
    # ============================================================
    if gt_rightlobe > 0 and agent_rightlobe > 0:
        rightlobe_error = abs(agent_rightlobe - gt_rightlobe)
        if rightlobe_error <= RIGHTLOBE_TOLERANCE:
            scores["rightlobe_accuracy"] = w_rightlobe
            feedback.append(f"PASS: Right lobe width accurate ({agent_rightlobe:.1f}mm vs GT {gt_rightlobe:.1f}mm, error {rightlobe_error:.1f}mm)")
        elif rightlobe_error <= RIGHTLOBE_TOLERANCE * 2:
            scores["rightlobe_accuracy"] = w_rightlobe // 2
            feedback.append(f"PARTIAL: Right lobe width close ({agent_rightlobe:.1f}mm vs GT {gt_rightlobe:.1f}mm, error {rightlobe_error:.1f}mm)")
        else:
            feedback.append(f"FAIL: Right lobe width inaccurate ({agent_rightlobe:.1f}mm vs GT {gt_rightlobe:.1f}mm, error {rightlobe_error:.1f}mm)")
    elif agent_rightlobe > 0:
        scores["rightlobe_accuracy"] = w_rightlobe // 4
        feedback.append(f"PARTIAL: Right lobe measured ({agent_rightlobe:.1f}mm) but no GT for comparison")
    else:
        feedback.append("FAIL: No right lobe measurement found")
    
    # ============================================================
    # CRITERION 3: Correct Measurement Level (15 points)
    # ============================================================
    if gt_slice > 0 and agent_slice > 0:
        slice_error = abs(agent_slice - gt_slice)
        if slice_error <= SLICE_TOLERANCE:
            scores["correct_level"] = w_level
            feedback.append(f"PASS: Measurement at correct level (z={agent_slice:.1f}mm vs GT z={gt_slice:.1f}mm)")
        elif slice_error <= SLICE_TOLERANCE * 2:
            scores["correct_level"] = w_level // 2
            feedback.append(f"PARTIAL: Measurement level close (z={agent_slice:.1f}mm vs GT z={gt_slice:.1f}mm)")
        else:
            feedback.append(f"FAIL: Measurement at wrong level (z={agent_slice:.1f}mm vs GT z={gt_slice:.1f}mm)")
    elif agent_slice == 0:
        # No slice info but measurements exist
        if scores["caudate_accuracy"] > 0 or scores["rightlobe_accuracy"] > 0:
            scores["correct_level"] = w_level // 3
            feedback.append("PARTIAL: No slice level reported but measurements found")
    
    # ============================================================
    # CRITERION 4: Ratio Calculation Correct (10 points)
    # ============================================================
    if agent_rightlobe > 0 and agent_caudate > 0:
        expected_ratio = agent_caudate / agent_rightlobe
        if agent_ratio > 0:
            ratio_error = abs(agent_ratio - expected_ratio)
            if ratio_error < 0.05:
                scores["ratio_correct"] = w_ratio
                feedback.append(f"PASS: Ratio calculated correctly ({agent_ratio:.3f})")
            else:
                feedback.append(f"FAIL: Ratio calculation error ({agent_ratio:.3f} vs expected {expected_ratio:.3f})")
        else:
            # Agent didn't provide ratio but we can compute it
            agent_ratio = expected_ratio
            scores["ratio_correct"] = w_ratio // 2
            feedback.append(f"PARTIAL: Ratio not reported, computed as {expected_ratio:.3f}")
    else:
        feedback.append("FAIL: Cannot verify ratio (invalid measurements)")
    
    # ============================================================
    # CRITERION 5: Classification Correct (15 points)
    # ============================================================
    def get_classification_category(ratio):
        if ratio >= 0.80:
            return "highly"
        elif ratio >= 0.65:
            return "suggestive"
        else:
            return "normal"
    
    agent_category = "unknown"
    if "highly" in agent_classification:
        agent_category = "highly"
    elif "suggestive" in agent_classification or "cirrhosis" in agent_classification:
        if "normal" not in agent_classification:
            agent_category = "suggestive"
        else:
            agent_category = "normal"
    elif "normal" in agent_classification:
        agent_category = "normal"
    
    gt_category = get_classification_category(gt_ratio) if gt_ratio > 0 else "unknown"
    
    # Also check against agent's own ratio
    agent_expected_category = get_classification_category(agent_ratio) if agent_ratio > 0 else "unknown"
    
    if agent_category == gt_category and gt_category != "unknown":
        scores["classification_correct"] = w_classification
        feedback.append(f"PASS: Classification correct ({agent_classification})")
    elif agent_category == agent_expected_category and agent_category != "unknown":
        # Classification matches agent's own measurements
        scores["classification_correct"] = w_classification // 2
        feedback.append(f"PARTIAL: Classification consistent with agent's ratio but differs from GT")
    elif agent_category != "unknown":
        feedback.append(f"FAIL: Classification incorrect ({agent_classification})")
    else:
        feedback.append(f"FAIL: Could not parse classification ({agent_classification})")
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    required_fields = 0
    if agent_caudate > 0:
        required_fields += 1
    if agent_rightlobe > 0:
        required_fields += 1
    if agent_ratio > 0:
        required_fields += 1
    if agent_category != "unknown":
        required_fields += 1
    
    if required_fields >= 4:
        scores["report_completeness"] = w_report
        feedback.append("PASS: Report contains all required fields")
    elif required_fields >= 2:
        scores["report_completeness"] = w_report // 2
        feedback.append(f"PARTIAL: Report missing some fields ({required_fields}/4)")
    else:
        feedback.append("FAIL: Report incomplete or missing")
    
    # ============================================================
    # CALCULATE FINAL SCORE
    # ============================================================
    total_score = sum(scores.values())
    
    # Pass criteria: 60+ points with at least one accurate measurement
    has_accurate_measurement = (
        scores["caudate_accuracy"] >= w_caudate * 0.8 or 
        scores["rightlobe_accuracy"] >= w_rightlobe * 0.8
    )
    
    passed = total_score >= 60 and has_accurate_measurement
    
    if passed:
        feedback.insert(0, f"TASK PASSED with score {total_score}/100")
    else:
        if total_score < 60:
            feedback.insert(0, f"TASK FAILED: Score {total_score}/100 below threshold (60)")
        else:
            feedback.insert(0, f"TASK FAILED: No accurate measurements despite score {total_score}/100")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "scores": scores,
        "details": {
            "agent_measurements": {
                "caudate_mm": agent_caudate,
                "rightlobe_mm": agent_rightlobe,
                "ratio": agent_ratio,
                "classification": agent_classification,
                "slice_mm": agent_slice
            },
            "ground_truth": {
                "caudate_mm": gt_caudate,
                "rightlobe_mm": gt_rightlobe,
                "ratio": gt_ratio,
                "classification": gt_classification,
                "slice_mm": gt_slice
            }
        }
    }