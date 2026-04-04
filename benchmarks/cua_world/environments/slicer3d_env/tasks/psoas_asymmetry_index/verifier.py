#!/usr/bin/env python3
"""
Verifier for Psoas Muscle Asymmetry Index task.

VERIFICATION STRATEGY:
1. Report file exists and is valid JSON (10 points)
2. Report was created during task - anti-gaming (implicit requirement)
3. Left psoas area accuracy (20 points)
4. Right psoas area accuracy (20 points)
5. Asymmetry index accuracy (20 points)
6. Classification correctness (15 points)
7. Smaller side identification (10 points)
8. Vertebral level documented (5 points)

Pass threshold: 60 points with at least one accurate area measurement
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_psoas_asymmetry(traj, env_info, task_info):
    """
    Verify psoas asymmetry assessment task completion.
    
    Uses copy_from_env to read results from container.
    
    Returns:
        dict with 'passed', 'score', 'feedback', and 'details'
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
    
    area_error_max_pct = thresholds.get('area_error_max_percent', 15)
    asymmetry_error_max = thresholds.get('asymmetry_error_max_points', 5)
    
    w_left = weights.get('left_psoas_area', 20)
    w_right = weights.get('right_psoas_area', 20)
    w_asymmetry = weights.get('asymmetry_index', 20)
    w_classification = weights.get('classification', 15)
    w_smaller = weights.get('smaller_side', 10)
    w_completeness = weights.get('report_completeness', 10)
    w_level = weights.get('vertebral_level', 5)
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/psoas_task_result.json", temp_result.name)
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
    
    # ================================================================
    # Copy ground truth from container
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/psoas_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Ground truth not available: {e}"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # ================================================================
    # Initialize scoring
    # ================================================================
    score = 0
    feedback_parts = []
    details = {
        "criteria": {},
        "ground_truth": {
            "left_area_mm2": gt.get('left_psoas_area_mm2', 0),
            "right_area_mm2": gt.get('right_psoas_area_mm2', 0),
            "asymmetry_pct": gt.get('asymmetry_index_percent', 0),
            "classification": gt.get('classification', ''),
            "smaller_side": gt.get('smaller_side', '')
        }
    }
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - task not attempted",
            "details": details
        }
    
    report_exists = result.get('report_exists', False)
    report_valid = result.get('report_valid', False)
    report_created = result.get('report_created_during_task', False)
    
    if not report_exists:
        feedback_parts.append("❌ No report file found")
        details["criteria"]["report_exists"] = {"score": 0, "max": w_completeness, "feedback": "Report not created"}
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    if not report_valid:
        feedback_parts.append("❌ Report file is not valid JSON")
        details["criteria"]["report_valid"] = {"score": 0, "max": w_completeness, "feedback": "Invalid JSON"}
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # Anti-gaming: Check if report was created during task
    if not report_created:
        feedback_parts.append("⚠️ Report may have existed before task started")
        # Don't fail immediately, but note it
    
    # ================================================================
    # Parse agent's report
    # ================================================================
    report = result.get('report_data', {})
    if isinstance(report, str):
        try:
            report = json.loads(report)
        except:
            report = {}
    
    details["agent_report"] = report
    
    # Ground truth values
    gt_left = gt.get('left_psoas_area_mm2', 0)
    gt_right = gt.get('right_psoas_area_mm2', 0)
    gt_asymmetry = gt.get('asymmetry_index_percent', 0)
    gt_class = gt.get('classification', '')
    gt_smaller = gt.get('smaller_side', '')
    
    # ================================================================
    # CRITERION 1: Left Psoas Area (20 points)
    # ================================================================
    agent_left = report.get('left_psoas_area_mm2', 0)
    if agent_left == 0:
        # Try alternate field names
        agent_left = report.get('left_area_mm2', 0) or report.get('left_psoas', 0) or report.get('left', 0)
    
    # Handle cm² to mm² conversion (if value is small, assume cm²)
    if 0 < agent_left < 50:
        agent_left = agent_left * 100  # Convert cm² to mm²
    
    left_score = 0
    if gt_left > 0 and agent_left > 0:
        left_error_pct = abs(agent_left - gt_left) / gt_left * 100
        details["left_error_pct"] = round(left_error_pct, 1)
        
        if left_error_pct <= area_error_max_pct:
            left_score = w_left
            left_feedback = f"✅ Left psoas: {agent_left:.0f} mm² (GT: {gt_left:.0f}, error: {left_error_pct:.1f}%)"
        elif left_error_pct <= area_error_max_pct * 1.5:
            left_score = int(w_left * 0.6)
            left_feedback = f"⚠️ Left psoas: {agent_left:.0f} mm² (GT: {gt_left:.0f}, error: {left_error_pct:.1f}%)"
        else:
            left_score = 0
            left_feedback = f"❌ Left psoas: {agent_left:.0f} mm² (GT: {gt_left:.0f}, error: {left_error_pct:.1f}%)"
    else:
        left_feedback = f"❌ Left psoas not measured (got: {agent_left})"
    
    score += left_score
    feedback_parts.append(left_feedback)
    details["criteria"]["left_psoas"] = {"score": left_score, "max": w_left, "feedback": left_feedback}
    
    # ================================================================
    # CRITERION 2: Right Psoas Area (20 points)
    # ================================================================
    agent_right = report.get('right_psoas_area_mm2', 0)
    if agent_right == 0:
        agent_right = report.get('right_area_mm2', 0) or report.get('right_psoas', 0) or report.get('right', 0)
    
    if 0 < agent_right < 50:
        agent_right = agent_right * 100
    
    right_score = 0
    if gt_right > 0 and agent_right > 0:
        right_error_pct = abs(agent_right - gt_right) / gt_right * 100
        details["right_error_pct"] = round(right_error_pct, 1)
        
        if right_error_pct <= area_error_max_pct:
            right_score = w_right
            right_feedback = f"✅ Right psoas: {agent_right:.0f} mm² (GT: {gt_right:.0f}, error: {right_error_pct:.1f}%)"
        elif right_error_pct <= area_error_max_pct * 1.5:
            right_score = int(w_right * 0.6)
            right_feedback = f"⚠️ Right psoas: {agent_right:.0f} mm² (GT: {gt_right:.0f}, error: {right_error_pct:.1f}%)"
        else:
            right_score = 0
            right_feedback = f"❌ Right psoas: {agent_right:.0f} mm² (GT: {gt_right:.0f}, error: {right_error_pct:.1f}%)"
    else:
        right_feedback = f"❌ Right psoas not measured (got: {agent_right})"
    
    score += right_score
    feedback_parts.append(right_feedback)
    details["criteria"]["right_psoas"] = {"score": right_score, "max": w_right, "feedback": right_feedback}
    
    # ================================================================
    # CRITERION 3: Asymmetry Index (20 points)
    # ================================================================
    agent_asymmetry = report.get('asymmetry_index_percent', -1)
    if agent_asymmetry < 0:
        agent_asymmetry = report.get('asymmetry_percent', -1) or report.get('pai', -1) or report.get('asymmetry', -1)
    
    asymmetry_score = 0
    if agent_asymmetry >= 0:
        asymmetry_error = abs(agent_asymmetry - gt_asymmetry)
        details["asymmetry_error_points"] = round(asymmetry_error, 1)
        
        if asymmetry_error <= asymmetry_error_max:
            asymmetry_score = w_asymmetry
            asymmetry_feedback = f"✅ Asymmetry: {agent_asymmetry:.1f}% (GT: {gt_asymmetry:.1f}%, diff: {asymmetry_error:.1f}pp)"
        elif asymmetry_error <= asymmetry_error_max * 2:
            asymmetry_score = int(w_asymmetry * 0.6)
            asymmetry_feedback = f"⚠️ Asymmetry: {agent_asymmetry:.1f}% (GT: {gt_asymmetry:.1f}%, diff: {asymmetry_error:.1f}pp)"
        else:
            asymmetry_score = 0
            asymmetry_feedback = f"❌ Asymmetry: {agent_asymmetry:.1f}% (GT: {gt_asymmetry:.1f}%, diff: {asymmetry_error:.1f}pp)"
    else:
        asymmetry_feedback = "❌ Asymmetry index not calculated"
    
    score += asymmetry_score
    feedback_parts.append(asymmetry_feedback)
    details["criteria"]["asymmetry_index"] = {"score": asymmetry_score, "max": w_asymmetry, "feedback": asymmetry_feedback}
    
    # ================================================================
    # CRITERION 4: Classification (15 points)
    # ================================================================
    agent_class = str(report.get('classification', '')).strip()
    
    # Normalize classification strings
    class_mapping = {
        "symmetric": "Symmetric",
        "normal": "Symmetric",
        "mild asymmetry": "Mild Asymmetry",
        "mild": "Mild Asymmetry",
        "moderate": "Mild Asymmetry",
        "significant asymmetry": "Significant Asymmetry",
        "significant": "Significant Asymmetry",
        "severe": "Significant Asymmetry",
        "severe asymmetry": "Significant Asymmetry"
    }
    
    agent_class_normalized = class_mapping.get(agent_class.lower(), agent_class)
    
    class_score = 0
    if agent_class_normalized == gt_class:
        class_score = w_classification
        class_feedback = f"✅ Classification: {agent_class_normalized}"
    elif agent_class_normalized:
        class_feedback = f"❌ Classification: {agent_class_normalized} (expected: {gt_class})"
    else:
        class_feedback = "❌ Classification not provided"
    
    score += class_score
    feedback_parts.append(class_feedback)
    details["criteria"]["classification"] = {"score": class_score, "max": w_classification, "feedback": class_feedback}
    
    # ================================================================
    # CRITERION 5: Smaller Side Identification (10 points)
    # ================================================================
    agent_smaller = str(report.get('smaller_side', '')).strip()
    
    smaller_mapping = {
        "left": "Left",
        "right": "Right",
        "equal": "Equal",
        "none": "Equal",
        "symmetric": "Equal",
        "n/a": "Equal"
    }
    
    agent_smaller_normalized = smaller_mapping.get(agent_smaller.lower(), agent_smaller)
    
    smaller_score = 0
    if gt_class == "Symmetric":
        # For symmetric cases, "Equal" or empty is acceptable
        if agent_smaller_normalized in ["Equal", ""] or not agent_smaller:
            smaller_score = w_smaller
            smaller_feedback = "✅ Correctly noted symmetric (no smaller side)"
        else:
            smaller_score = int(w_smaller * 0.5)
            smaller_feedback = f"⚠️ Noted {agent_smaller_normalized} (symmetric case)"
    else:
        if agent_smaller_normalized == gt_smaller:
            smaller_score = w_smaller
            smaller_feedback = f"✅ Smaller side: {agent_smaller_normalized}"
        elif agent_smaller_normalized:
            smaller_score = 0
            smaller_feedback = f"❌ Smaller side: {agent_smaller_normalized} (expected: {gt_smaller})"
        else:
            smaller_score = 0
            smaller_feedback = "❌ Smaller side not identified"
    
    score += smaller_score
    feedback_parts.append(smaller_feedback)
    details["criteria"]["smaller_side"] = {"score": smaller_score, "max": w_smaller, "feedback": smaller_feedback}
    
    # ================================================================
    # CRITERION 6: Report Completeness (10 points)
    # ================================================================
    required_fields = [
        'left_psoas_area_mm2',
        'right_psoas_area_mm2',
        'asymmetry_index_percent',
        'classification'
    ]
    
    # Check with alternate field names too
    def field_present(field):
        if field in report and report[field] is not None:
            return True
        # Check alternates
        alternates = {
            'left_psoas_area_mm2': ['left_area_mm2', 'left_psoas', 'left'],
            'right_psoas_area_mm2': ['right_area_mm2', 'right_psoas', 'right'],
            'asymmetry_index_percent': ['asymmetry_percent', 'pai', 'asymmetry'],
            'classification': ['class', 'category', 'assessment']
        }
        for alt in alternates.get(field, []):
            if alt in report and report[alt] is not None:
                return True
        return False
    
    present_count = sum(1 for f in required_fields if field_present(f))
    completeness_score = int(w_completeness * present_count / len(required_fields))
    
    score += completeness_score
    completeness_feedback = f"Report: {present_count}/{len(required_fields)} required fields"
    feedback_parts.append(completeness_feedback)
    details["criteria"]["completeness"] = {"score": completeness_score, "max": w_completeness, "feedback": completeness_feedback}
    
    # ================================================================
    # CRITERION 7: Vertebral Level (5 points)
    # ================================================================
    agent_level = str(report.get('vertebral_level', '')).upper()
    
    level_score = 0
    if 'L3' in agent_level or 'L4' in agent_level:
        level_score = w_level
        level_feedback = f"✅ Level: {agent_level}"
    elif agent_level:
        level_score = int(w_level * 0.4)
        level_feedback = f"⚠️ Level: {agent_level} (expected L3 or L3-L4)"
    else:
        level_feedback = "❌ Vertebral level not documented"
    
    score += level_score
    feedback_parts.append(level_feedback)
    details["criteria"]["vertebral_level"] = {"score": level_score, "max": w_level, "feedback": level_feedback}
    
    # ================================================================
    # Final Assessment
    # ================================================================
    details["total_score"] = score
    details["max_score"] = 100
    
    # Pass requires 60 points AND at least one accurate measurement
    has_accurate_measurement = (left_score >= w_left * 0.6 or right_score >= w_right * 0.6)
    passed = score >= 60 and has_accurate_measurement
    
    if passed:
        summary = f"✅ Task PASSED with {score}/100 points"
    else:
        if not has_accurate_measurement:
            summary = f"❌ Task FAILED: Score {score}/100, but no accurate muscle measurement achieved"
        else:
            summary = f"❌ Task FAILED with {score}/100 points (threshold: 60)"
    
    feedback_parts.insert(0, summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test mode - run with a sample result file
    import sys
    
    if len(sys.argv) > 1:
        result_file = sys.argv[1]
        if os.path.exists(result_file):
            with open(result_file) as f:
                result_data = json.load(f)
            
            # Mock env_info and task_info for testing
            class MockCopyFromEnv:
                def __init__(self, result_data):
                    self.result_data = result_data
                
                def __call__(self, src, dst):
                    if "task_result" in src:
                        with open(dst, 'w') as f:
                            json.dump(self.result_data, f)
                    elif "ground_truth" in src:
                        # Mock ground truth
                        gt = {
                            "left_psoas_area_mm2": 1480,
                            "right_psoas_area_mm2": 1295,
                            "asymmetry_index_percent": 12.5,
                            "classification": "Mild Asymmetry",
                            "smaller_side": "Right"
                        }
                        with open(dst, 'w') as f:
                            json.dump(gt, f)
            
            env_info = {'copy_from_env': MockCopyFromEnv(result_data)}
            task_info = {'metadata': {}}
            
            result = verify_psoas_asymmetry({}, env_info, task_info)
            print(json.dumps(result, indent=2))
    else:
        print("Usage: python verifier.py <result_file.json>")