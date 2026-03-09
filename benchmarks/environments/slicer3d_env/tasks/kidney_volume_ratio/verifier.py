#!/usr/bin/env python3
"""
Verifier for Bilateral Kidney Volume Ratio Analysis task.

VERIFICATION CRITERIA:
1. Report file exists (10 points) - file created at expected path
2. Right kidney volume correct (20 points) - within 10% of ground truth
3. Left kidney volume correct (20 points) - within 10% of ground truth
4. Volume ratio correct (20 points) - calculated correctly from reported volumes
5. Recommendation correct (20 points) - larger kidney correctly identified
6. Segment Statistics computed (10 points) - evidence of using the proper module

Pass threshold: 70 points with both volumes within tolerance
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_kidney_volume_ratio(traj, env_info, task_info):
    """
    Verify the kidney volume ratio analysis task.
    
    Uses multi-criteria scoring with anatomical plausibility checks.
    
    Args:
        traj: Trajectory data (list of observations)
        env_info: Environment info dict with copy_from_env function
        task_info: Task metadata dict
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
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
    volume_tolerance_pct = metadata.get('volume_tolerance_percent', 10)
    ratio_tolerance = metadata.get('ratio_tolerance', 0.05)
    
    weights = metadata.get('scoring_weights', {})
    w_report = weights.get('report_exists', 10)
    w_right = weights.get('right_volume_correct', 20)
    w_left = weights.get('left_volume_correct', 20)
    w_ratio = weights.get('ratio_correct', 20)
    w_recommendation = weights.get('recommendation_correct', 20)
    w_stats = weights.get('stats_computed', 10)

    feedback_parts = []
    details = {}
    total_points = 0
    max_points = 100

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("/tmp/kidney_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
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
    # Check if Slicer was running
    # ================================================================
    slicer_running = result_data.get('slicer_running', False)
    if slicer_running in ['true', True]:
        details['slicer_running'] = True
    else:
        details['slicer_running'] = False
        feedback_parts.append("Slicer was not running")

    # ================================================================
    # CRITERION 1: Report file exists (10 points)
    # ================================================================
    report_exists = result_data.get('report_exists', False)
    report_after_start = result_data.get('report_created_after_start', False)
    
    if report_exists in ['true', True]:
        if report_after_start in ['true', True]:
            total_points += w_report
            feedback_parts.append(f"Report file created (+{w_report})")
            details['report_exists'] = True
            details['report_created_during_task'] = True
        else:
            total_points += w_report // 2
            feedback_parts.append(f"Report exists but may predate task (+{w_report//2})")
            details['report_exists'] = True
            details['report_created_during_task'] = False
    else:
        feedback_parts.append("Report file not found (+0)")
        details['report_exists'] = False
        # Early exit - can't verify without report
        return {
            "passed": False,
            "score": total_points,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # Get ground truth values
    # ================================================================
    try:
        gt_right = float(result_data.get('gt_right_volume', 0))
        gt_left = float(result_data.get('gt_left_volume', 0))
        gt_ratio = float(result_data.get('gt_ratio', 1))
        gt_preserve = str(result_data.get('gt_preserve', '')).upper()
    except (ValueError, TypeError) as e:
        logger.warning(f"Could not parse ground truth: {e}")
        gt_right = 0
        gt_left = 0
        gt_ratio = 1
        gt_preserve = ""

    details['gt_right_ml'] = gt_right
    details['gt_left_ml'] = gt_left
    details['gt_ratio'] = gt_ratio
    details['gt_preserve'] = gt_preserve

    # ================================================================
    # Get reported values
    # ================================================================
    reported_right = 0.0
    reported_left = 0.0
    reported_ratio = 0.0
    reported_recommendation = ""
    
    try:
        val = result_data.get('right_volume_reported', '')
        if val:
            reported_right = float(val)
    except (ValueError, TypeError):
        pass
        
    try:
        val = result_data.get('left_volume_reported', '')
        if val:
            reported_left = float(val)
    except (ValueError, TypeError):
        pass
        
    try:
        val = result_data.get('ratio_reported', '')
        if val:
            reported_ratio = float(val)
    except (ValueError, TypeError):
        pass
        
    reported_recommendation = str(result_data.get('recommendation_reported', '')).upper()

    details['reported_right_ml'] = reported_right
    details['reported_left_ml'] = reported_left
    details['reported_ratio'] = reported_ratio
    details['reported_recommendation'] = reported_recommendation

    # ================================================================
    # CRITERION 2: Right kidney volume correct (20 points)
    # ================================================================
    right_volume_valid = False
    
    if reported_right > 0 and gt_right > 0:
        tolerance = gt_right * (volume_tolerance_pct / 100.0)
        error = abs(reported_right - gt_right)
        
        if error <= tolerance:
            total_points += w_right
            right_volume_valid = True
            feedback_parts.append(f"Right kidney: {reported_right:.1f} mL ✓ (+{w_right})")
        else:
            # Partial credit for plausible values
            if 80 <= reported_right <= 250:
                partial = w_right // 2
                total_points += partial
                feedback_parts.append(f"Right kidney: {reported_right:.1f} mL (expected ~{gt_right:.1f}) (+{partial})")
            else:
                feedback_parts.append(f"Right kidney: {reported_right:.1f} mL (expected ~{gt_right:.1f}) (+0)")
    else:
        feedback_parts.append(f"Right kidney volume not found or invalid (+0)")
    
    details['right_volume_valid'] = right_volume_valid

    # ================================================================
    # CRITERION 3: Left kidney volume correct (20 points)
    # ================================================================
    left_volume_valid = False
    
    if reported_left > 0 and gt_left > 0:
        tolerance = gt_left * (volume_tolerance_pct / 100.0)
        error = abs(reported_left - gt_left)
        
        if error <= tolerance:
            total_points += w_left
            left_volume_valid = True
            feedback_parts.append(f"Left kidney: {reported_left:.1f} mL ✓ (+{w_left})")
        else:
            # Partial credit for plausible values
            if 80 <= reported_left <= 250:
                partial = w_left // 2
                total_points += partial
                feedback_parts.append(f"Left kidney: {reported_left:.1f} mL (expected ~{gt_left:.1f}) (+{partial})")
            else:
                feedback_parts.append(f"Left kidney: {reported_left:.1f} mL (expected ~{gt_left:.1f}) (+0)")
    else:
        feedback_parts.append(f"Left kidney volume not found or invalid (+0)")
    
    details['left_volume_valid'] = left_volume_valid

    # ================================================================
    # CRITERION 4: Volume ratio correct (20 points)
    # ================================================================
    ratio_valid = False
    
    if reported_right > 0 and reported_left > 0:
        # Calculate expected ratio from reported values
        expected_ratio_from_reported = max(reported_right, reported_left) / min(reported_right, reported_left)
        
        if reported_ratio > 0:
            # Check if reported ratio matches the calculation
            ratio_error = abs(reported_ratio - expected_ratio_from_reported)
            
            if ratio_error <= ratio_tolerance:
                total_points += w_ratio
                ratio_valid = True
                feedback_parts.append(f"Volume ratio: {reported_ratio:.3f} ✓ (+{w_ratio})")
            else:
                # Partial credit if ratio is reasonable
                if 1.0 <= reported_ratio <= 2.0:
                    partial = w_ratio // 2
                    total_points += partial
                    feedback_parts.append(f"Volume ratio: {reported_ratio:.3f} (expected ~{expected_ratio_from_reported:.3f}) (+{partial})")
                else:
                    feedback_parts.append(f"Volume ratio: {reported_ratio:.3f} (incorrect calculation) (+0)")
        else:
            feedback_parts.append("Volume ratio not reported (+0)")
    else:
        feedback_parts.append("Cannot verify ratio (missing volume data) (+0)")
    
    details['ratio_valid'] = ratio_valid

    # ================================================================
    # CRITERION 5: Recommendation correct (20 points)
    # ================================================================
    recommendation_valid = False
    
    if reported_recommendation:
        # Determine which kidney should be preserved based on reported volumes
        if reported_right > 0 and reported_left > 0:
            expected_preserve = "RIGHT" if reported_right > reported_left else "LEFT"
        else:
            expected_preserve = gt_preserve
        
        if reported_recommendation == expected_preserve:
            total_points += w_recommendation
            recommendation_valid = True
            feedback_parts.append(f"Preserve {reported_recommendation} ✓ (+{w_recommendation})")
        elif reported_recommendation == gt_preserve:
            # Matches ground truth even if not matching reported values
            total_points += w_recommendation
            recommendation_valid = True
            feedback_parts.append(f"Preserve {reported_recommendation} ✓ (+{w_recommendation})")
        else:
            feedback_parts.append(f"Preserve {reported_recommendation} (should be {expected_preserve}) (+0)")
    else:
        feedback_parts.append("Preservation recommendation not found (+0)")
    
    details['recommendation_valid'] = recommendation_valid

    # ================================================================
    # CRITERION 6: Segment Statistics computed (10 points)
    # ================================================================
    stats_computed = result_data.get('stats_computed', False)
    stats_table_exists = result_data.get('stats_table_exists', False)
    
    if stats_computed in ['true', True] or stats_table_exists in ['true', True]:
        total_points += w_stats
        feedback_parts.append(f"Segment Statistics used ✓ (+{w_stats})")
        details['stats_computed'] = True
    else:
        # If values are correct, assume they used segment statistics
        if right_volume_valid and left_volume_valid:
            total_points += w_stats // 2
            feedback_parts.append(f"Stats likely used (correct values) (+{w_stats//2})")
            details['stats_computed'] = 'inferred'
        else:
            feedback_parts.append("No evidence of Segment Statistics use (+0)")
            details['stats_computed'] = False

    # ================================================================
    # Calculate final score and pass/fail
    # ================================================================
    score = total_points
    
    # Pass criteria: >= 70 points AND both volumes within tolerance
    key_criteria_met = right_volume_valid and left_volume_valid
    passed = score >= 70 and key_criteria_met

    if passed:
        summary = f"PASSED: Kidney volume analysis completed correctly ({score}/{max_points} points)"
    elif key_criteria_met:
        summary = f"PARTIAL: Volumes correct but missing other criteria ({score}/{max_points} points)"
    elif score >= 50:
        summary = f"FAILED: Partial completion ({score}/{max_points} points, need 70 with volumes correct)"
    else:
        summary = f"FAILED: Insufficient task completion ({score}/{max_points} points)"

    # Include report content in details for debugging
    report_content = result_data.get('report_content', '')
    if report_content:
        details['report_content'] = report_content[:500]  # Truncate if too long

    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test verification locally (mock mode)
    print("Kidney Volume Ratio Verifier")
    print("This verifier requires copy_from_env to be provided by the framework.")
    print("Run through the gym-anything framework for actual verification.")