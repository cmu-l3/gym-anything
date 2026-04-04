#!/usr/bin/env python3
"""
Verifier for pre-operative subcutaneous fat thickness assessment task.

VERIFICATION CRITERIA (100 points total):
1. Measurement exists (15 points) - ruler markup file created
2. Anatomical level (15 points) - measurement at L2-L4 level
3. Measurement accuracy (30 points) - within 8mm of ground truth
4. Measurement plausible (10 points) - value in reasonable range (5-150mm)
5. Category correct (15 points) - surgical planning category matches
6. Report complete (15 points) - JSON with all required fields

Pass threshold: 60 points with measurement accuracy achieved
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_preop_fat_thickness(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the pre-operative fat thickness measurement task.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task configuration with metadata
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
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
    
    # Thresholds
    acceptable_error_mm = thresholds.get('measurement_error_max_mm', 8.0)
    level_tolerance = thresholds.get('level_tolerance', 1)
    
    # Scoring weights
    w_measurement_exists = weights.get('measurement_exists', 15)
    w_anatomical_level = weights.get('anatomical_level', 15)
    w_measurement_accuracy = weights.get('measurement_accuracy', 30)
    w_measurement_plausible = weights.get('measurement_plausible', 10)
    w_category_correct = weights.get('category_correct', 15)
    w_report_complete = weights.get('report_complete', 15)
    
    # Initialize results
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Load task result from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fat_task_result.json", temp_result.name)
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
    
    details['result'] = result
    case_id = result.get('case_id', 'amos_0001')
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("✗ Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/fat_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use defaults
        gt_data = {
            "fat_thickness_mm": 35.0,
            "vertebral_level": "L3",
            "surgical_category": "Average"
        }
        feedback_parts.append(f"Warning: Using default ground truth ({e})")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_thickness = gt_data.get('fat_thickness_mm', 35.0)
    gt_level = gt_data.get('vertebral_level', 'L3')
    gt_category = gt_data.get('surgical_category', 'Average')
    
    details['ground_truth'] = {
        'thickness_mm': gt_thickness,
        'vertebral_level': gt_level,
        'surgical_category': gt_category
    }
    
    # ================================================================
    # CRITERION 1: Measurement file exists (15 points)
    # ================================================================
    measurement_exists = result.get('measurement_file_exists', False)
    measurement_created = result.get('measurement_created_during_task', False)
    
    if measurement_exists:
        if measurement_created:
            score += w_measurement_exists
            feedback_parts.append(f"✓ Measurement file created during task ({w_measurement_exists} pts)")
        else:
            # Partial credit if file exists but wasn't created during task
            partial = w_measurement_exists // 2
            score += partial
            feedback_parts.append(f"△ Measurement file exists but may be pre-existing ({partial} pts)")
        details['measurement_exists'] = True
        details['measurement_created_during_task'] = measurement_created
    else:
        feedback_parts.append(f"✗ No measurement file found (0 pts)")
        details['measurement_exists'] = False
    
    # ================================================================
    # CRITERION 2: Measurement accuracy (30 points)
    # ================================================================
    agent_measurement_str = result.get('measurement_mm', '0')
    try:
        agent_measurement = float(agent_measurement_str) if agent_measurement_str else 0.0
    except (ValueError, TypeError):
        agent_measurement = 0.0
    
    details['agent_measurement_mm'] = agent_measurement
    measurement_accurate = False
    
    if agent_measurement > 0:
        measurement_error = abs(agent_measurement - gt_thickness)
        details['measurement_error_mm'] = round(measurement_error, 1)
        
        if measurement_error <= acceptable_error_mm:
            score += w_measurement_accuracy
            feedback_parts.append(
                f"✓ Measurement accurate: {agent_measurement:.1f}mm vs GT {gt_thickness:.1f}mm "
                f"(error: {measurement_error:.1f}mm ≤ {acceptable_error_mm}mm) ({w_measurement_accuracy} pts)"
            )
            measurement_accurate = True
            details['measurement_accurate'] = True
        elif measurement_error <= acceptable_error_mm * 2:
            # Partial credit for close measurements
            partial = w_measurement_accuracy // 2
            score += partial
            feedback_parts.append(
                f"△ Measurement close: {agent_measurement:.1f}mm vs GT {gt_thickness:.1f}mm "
                f"(error: {measurement_error:.1f}mm) ({partial} pts)"
            )
            details['measurement_accurate'] = False
        else:
            feedback_parts.append(
                f"✗ Measurement inaccurate: {agent_measurement:.1f}mm vs GT {gt_thickness:.1f}mm "
                f"(error: {measurement_error:.1f}mm > {acceptable_error_mm}mm) (0 pts)"
            )
            details['measurement_accurate'] = False
    else:
        feedback_parts.append(f"✗ No valid measurement value extracted (0 pts)")
        details['measurement_accurate'] = False
    
    # ================================================================
    # CRITERION 3: Anatomical level (15 points)
    # ================================================================
    agent_level = result.get('report_vertebral_level', '')
    details['agent_level'] = agent_level
    
    # Define vertebral level order for comparison
    level_order = ["T12", "L1", "L2", "L3", "L4", "L5", "S1"]
    
    def level_distance(l1, l2):
        """Calculate distance between vertebral levels."""
        try:
            l1_clean = l1.upper().strip() if l1 else ""
            l2_clean = l2.upper().strip() if l2 else ""
            idx1 = level_order.index(l1_clean)
            idx2 = level_order.index(l2_clean)
            return abs(idx1 - idx2)
        except (ValueError, AttributeError):
            return 999
    
    if agent_level:
        dist = level_distance(agent_level, gt_level)
        if dist == 0:
            score += w_anatomical_level
            feedback_parts.append(f"✓ Anatomical level correct: {agent_level} ({w_anatomical_level} pts)")
            details['level_correct'] = True
        elif dist <= level_tolerance:
            partial = w_anatomical_level * 2 // 3
            score += partial
            feedback_parts.append(
                f"△ Anatomical level close: {agent_level} vs GT {gt_level} ({partial} pts)"
            )
            details['level_correct'] = False
        else:
            feedback_parts.append(
                f"✗ Anatomical level incorrect: {agent_level} vs GT {gt_level} (0 pts)"
            )
            details['level_correct'] = False
    else:
        feedback_parts.append(f"✗ No anatomical level reported (0 pts)")
        details['level_correct'] = False
    
    # ================================================================
    # CRITERION 4: Measurement plausible (10 points)
    # ================================================================
    plausible_range = metadata.get('plausible_range_mm', [5, 150])
    
    if measurement_exists and agent_measurement > 0:
        if plausible_range[0] <= agent_measurement <= plausible_range[1]:
            score += w_measurement_plausible
            feedback_parts.append(
                f"✓ Measurement plausible ({agent_measurement:.1f}mm in {plausible_range[0]}-{plausible_range[1]}mm range) ({w_measurement_plausible} pts)"
            )
            details['measurement_plausible'] = True
        else:
            feedback_parts.append(
                f"✗ Measurement implausible ({agent_measurement:.1f}mm outside {plausible_range[0]}-{plausible_range[1]}mm) (0 pts)"
            )
            details['measurement_plausible'] = False
    else:
        details['measurement_plausible'] = False
    
    # ================================================================
    # CRITERION 5: Surgical category correct (15 points)
    # ================================================================
    agent_category = result.get('report_category', '')
    details['agent_category'] = agent_category
    
    def get_category(thickness):
        """Determine surgical category from thickness."""
        categories = metadata.get('surgical_categories', {
            "Thin": {"min": 0, "max": 20},
            "Average": {"min": 20, "max": 40},
            "Thick": {"min": 40, "max": 60},
            "Very Thick": {"min": 60, "max": 999}
        })
        for cat_name, bounds in categories.items():
            if bounds['min'] <= thickness < bounds['max']:
                return cat_name
        return "Average"
    
    if agent_category:
        # Normalize category strings for comparison
        agent_cat_norm = agent_category.lower().strip().replace("_", " ").replace("-", " ")
        gt_cat_norm = gt_category.lower().strip().replace("_", " ").replace("-", " ")
        
        if agent_cat_norm == gt_cat_norm:
            score += w_category_correct
            feedback_parts.append(
                f"✓ Surgical category correct: {agent_category} ({w_category_correct} pts)"
            )
            details['category_correct'] = True
        else:
            # Check if category is at least internally consistent with agent's measurement
            if agent_measurement > 0:
                expected_from_agent = get_category(agent_measurement)
                if agent_cat_norm == expected_from_agent.lower():
                    partial = w_category_correct // 2
                    score += partial
                    feedback_parts.append(
                        f"△ Category consistent with agent measurement but not GT: "
                        f"{agent_category} (expected {gt_category}) ({partial} pts)"
                    )
                else:
                    feedback_parts.append(
                        f"✗ Surgical category incorrect: {agent_category} vs GT {gt_category} (0 pts)"
                    )
            else:
                feedback_parts.append(
                    f"✗ Surgical category incorrect: {agent_category} vs GT {gt_category} (0 pts)"
                )
            details['category_correct'] = False
    else:
        feedback_parts.append(f"✗ No surgical category reported (0 pts)")
        details['category_correct'] = False
    
    # ================================================================
    # CRITERION 6: Report completeness (15 points)
    # ================================================================
    report_exists = result.get('report_file_exists', False)
    report_thickness = result.get('report_thickness_mm', '')
    report_created = result.get('report_created_during_task', False)
    
    completeness_score = 0
    completeness_items = []
    
    if report_exists:
        completeness_score += 1
        completeness_items.append("file exists")
    if report_thickness:
        try:
            if float(report_thickness) > 0:
                completeness_score += 1
                completeness_items.append("thickness")
        except (ValueError, TypeError):
            pass
    if agent_level:
        completeness_score += 1
        completeness_items.append("level")
    if agent_category:
        completeness_score += 1
        completeness_items.append("category")
    
    details['report_completeness'] = completeness_score
    details['report_items'] = completeness_items
    
    if completeness_score >= 4:
        if report_created:
            score += w_report_complete
            feedback_parts.append(f"✓ Report complete with all fields ({w_report_complete} pts)")
        else:
            partial = w_report_complete * 3 // 4
            score += partial
            feedback_parts.append(f"△ Report complete but may be pre-existing ({partial} pts)")
    elif completeness_score >= 3:
        partial = w_report_complete * 2 // 3
        score += partial
        feedback_parts.append(f"△ Report partially complete ({completeness_score}/4 fields: {', '.join(completeness_items)}) ({partial} pts)")
    elif completeness_score >= 1:
        partial = w_report_complete // 3
        score += partial
        feedback_parts.append(f"△ Report minimal ({completeness_score}/4 fields) ({partial} pts)")
    else:
        feedback_parts.append(f"✗ No valid report created (0 pts)")
    
    # ================================================================
    # Final score and pass/fail determination
    # ================================================================
    details['final_score'] = round(score, 1)
    
    # Pass requires: score >= 60 AND measurement accuracy achieved
    passed = score >= 60 and measurement_accurate
    details['passed'] = passed
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nFinal Score: {score}/100"
    feedback += f"\nStatus: {'PASSED' if passed else 'FAILED'}"
    if not passed:
        if score < 60:
            feedback += f"\n(Pass requires ≥60 points)"
        if not measurement_accurate:
            feedback += f"\n(Pass requires measurement accuracy ≤{acceptable_error_mm}mm)"
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }


if __name__ == "__main__":
    # Test mode - print module info
    print("Pre-operative Fat Thickness Verification Module")
    print("=" * 50)
    print("Verification Criteria:")
    print("  1. Measurement exists (15 pts)")
    print("  2. Anatomical level correct (15 pts)")
    print("  3. Measurement accuracy (30 pts)")
    print("  4. Measurement plausible (10 pts)")
    print("  5. Category correct (15 pts)")
    print("  6. Report complete (15 pts)")
    print("=" * 50)
    print("Pass threshold: 60 points AND measurement accuracy ≤8mm")
    print("\nRun with: verify_preop_fat_thickness(traj, env_info, task_info)")