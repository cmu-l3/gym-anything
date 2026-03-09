#!/usr/bin/env python3
"""
Verifier for Thoracic Kyphosis Cobb Angle Measurement task.

VERIFICATION STRATEGY:
1. Angle Accuracy (35 pts) - Measured angle within 8° of ground truth
2. Superior Vertebra Level (10 pts) - Correct or within acceptable range
3. Inferior Vertebra Level (10 pts) - Correct or within acceptable range
4. Anatomical Placement (15 pts) - Landmarks/markups were created
5. Classification Correct (15 pts) - Correct category based on angle
6. Report Completeness (10 pts) - JSON with all required fields
7. Visualization (5 pts) - Screenshot evidence

Pass threshold: 60 points AND angle accuracy criterion met
"""

import json
import os
import re
import sys
import tempfile
import logging
from typing import Any, Dict, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vertebra_level(level_str: str) -> Tuple[str, int]:
    """
    Parse vertebra level string (e.g., 'T4', 'L1') into region and number.
    
    Returns:
        Tuple of (region letter, level number) or ("", 0) if invalid
    """
    if not level_str:
        return "", 0
    
    level_str = str(level_str).strip().upper()
    # Match patterns like T4, T12, L1, C7
    match = re.match(r'([TCLSCO])(\d+)', level_str)
    if match:
        return match.group(1), int(match.group(2))
    return "", 0


def vertebra_in_range(level: str, acceptable: list) -> bool:
    """Check if a vertebra level is within acceptable range."""
    if not level or not acceptable:
        return False
    
    level = str(level).strip().upper()
    acceptable_upper = [str(a).strip().upper() for a in acceptable]
    return level in acceptable_upper


def vertebra_distance(v1: str, v2: str) -> int:
    """
    Calculate distance between two vertebrae in the same region.
    Returns large number if different regions or invalid.
    """
    r1, n1 = parse_vertebra_level(v1)
    r2, n2 = parse_vertebra_level(v2)
    
    if r1 != r2 or not r1:
        return 100  # Different regions or invalid
    
    return abs(n1 - n2)


def classify_kyphosis(angle: float) -> str:
    """Classify kyphosis based on Cobb angle."""
    if angle < 20:
        return "Hypokyphotic"
    elif angle <= 45:
        return "Normal"
    else:
        return "Hyperkyphotic"


def normalize_classification(classification: str) -> str:
    """Normalize classification string for comparison."""
    if not classification:
        return ""
    
    c = str(classification).lower().strip()
    c = c.replace('-', '').replace('_', '').replace(' ', '')
    
    # Map common variations
    if 'hypo' in c and 'kypho' in c:
        return 'hypokyphotic'
    elif 'hyper' in c and 'kypho' in c:
        return 'hyperkyphotic'
    elif c in ['normal', 'normalkyphosis', 'normalkyphotic']:
        return 'normal'
    
    return c


def verify_thoracic_kyphosis_cobb(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Verify the thoracic kyphosis Cobb angle measurement task.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        Dictionary with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
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
    thresholds = metadata.get('passing_thresholds', {})
    
    # Scoring weights
    w_angle = weights.get('angle_accuracy', 35)
    w_sup_level = weights.get('superior_level', 10)
    w_inf_level = weights.get('inferior_level', 10)
    w_placement = weights.get('anatomical_placement', 15)
    w_classification = weights.get('classification', 15)
    w_report = weights.get('report_complete', 10)
    w_vis = weights.get('visualization', 5)
    
    # Thresholds
    angle_tolerance = thresholds.get('angle_error_max_degrees', 8)
    min_pass_score = thresholds.get('min_score', 60)
    
    acceptable_superior = metadata.get('acceptable_superior_vertebrae', ['T3', 'T4', 'T5'])
    acceptable_inferior = metadata.get('acceptable_inferior_vertebrae', ['T10', 'T11', 'T12'])
    
    feedback_parts = []
    scores = {
        'angle_accuracy': 0,
        'superior_level': 0,
        'inferior_level': 0,
        'anatomical_placement': 0,
        'classification': 0,
        'report_complete': 0,
        'visualization': 0
    }
    details = {}
    
    # ================================================================
    # LOAD TASK RESULT
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
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
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/kyphosis_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Try alternative path
        try:
            copy_from_env("/var/lib/slicer/ground_truth/LIDC-IDRI-0003_kyphosis_gt.json", temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                gt_data = json.load(f)
        except Exception:
            pass
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    if not gt_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Ground truth file not found - cannot verify"
        }
    
    gt_angle = gt_data.get('cobb_angle_degrees', 0)
    gt_classification = gt_data.get('classification', '')
    gt_superior = gt_data.get('superior_vertebra', 'T4')
    gt_inferior = gt_data.get('inferior_vertebra', 'T12')
    
    # Use acceptable ranges from ground truth if available
    if 'acceptable_superior_range' in gt_data:
        acceptable_superior = gt_data['acceptable_superior_range']
    if 'acceptable_inferior_range' in gt_data:
        acceptable_inferior = gt_data['acceptable_inferior_range']
    
    details['ground_truth'] = {
        'cobb_angle': gt_angle,
        'classification': gt_classification,
        'superior_vertebra': gt_superior,
        'inferior_vertebra': gt_inferior
    }
    
    feedback_parts.append(f"Ground truth: {gt_angle}° ({gt_classification}), {gt_superior} to {gt_inferior}")
    
    # ================================================================
    # CHECK BASIC TASK COMPLETION
    # ================================================================
    if not result.get('slicer_was_running', False):
        feedback_parts.append("FAIL: 3D Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts)
        }
    
    # Anti-gaming: Check timestamps
    task_start = result.get('task_start_time', 0)
    export_time = result.get('export_time', 0)
    
    if task_start > 0 and export_time > 0:
        task_duration = export_time - task_start
        if task_duration < 10:
            feedback_parts.append(f"WARNING: Task completed very quickly ({task_duration}s)")
    
    # ================================================================
    # CRITERION 1: LANDMARKS/ANATOMICAL PLACEMENT (15 pts)
    # ================================================================
    landmarks_valid = result.get('landmarks_file_valid', False)
    markup_count = result.get('markup_count', 0)
    
    if landmarks_valid and markup_count >= 4:
        # 4+ markups suggests two lines with 2 points each
        scores['anatomical_placement'] = w_placement
        feedback_parts.append(f"✓ Landmarks: {markup_count} markups created")
    elif landmarks_valid and markup_count >= 2:
        scores['anatomical_placement'] = w_placement * 2 // 3
        feedback_parts.append(f"~ Landmarks: {markup_count} markups (expected 4+ for two lines)")
    elif result.get('landmarks_file_exists', False):
        scores['anatomical_placement'] = w_placement // 3
        feedback_parts.append("~ Landmarks file exists but may not be valid")
    else:
        feedback_parts.append("✗ No landmarks file created")
    
    # ================================================================
    # CRITERION 2: REPORT COMPLETENESS (10 pts)
    # ================================================================
    report_valid = result.get('report_file_valid', False)
    
    if not report_valid and not result.get('report_file_exists', False):
        feedback_parts.append("✗ No report file created")
        # Can't evaluate other criteria without report
        total_score = sum(scores.values())
        return {
            "passed": False,
            "score": total_score,
            "feedback": "\n".join(feedback_parts),
            "details": details
        }
    
    # Parse agent measurements
    agent_angle_str = result.get('agent_cobb_angle', '')
    agent_classification = result.get('agent_classification', '').strip()
    agent_superior = result.get('agent_superior_vertebra', '').strip()
    agent_inferior = result.get('agent_inferior_vertebra', '').strip()
    
    details['agent_measurements'] = {
        'cobb_angle_raw': agent_angle_str,
        'classification': agent_classification,
        'superior_vertebra': agent_superior,
        'inferior_vertebra': agent_inferior
    }
    
    # Parse angle
    agent_angle = None
    try:
        if isinstance(agent_angle_str, (int, float)):
            agent_angle = float(agent_angle_str)
        elif agent_angle_str:
            # Remove degree symbol and other non-numeric chars
            cleaned = str(agent_angle_str).replace('°', '').replace('degrees', '').strip()
            agent_angle = float(cleaned)
    except (ValueError, TypeError):
        agent_angle = None
    
    details['agent_measurements']['cobb_angle_parsed'] = agent_angle
    
    # Check report completeness
    fields_present = sum([
        agent_angle is not None,
        len(agent_classification) > 0,
        len(agent_superior) > 0,
        len(agent_inferior) > 0
    ])
    
    if fields_present == 4:
        scores['report_complete'] = w_report
        feedback_parts.append("✓ Report contains all required fields")
    elif fields_present >= 2:
        scores['report_complete'] = w_report * fields_present // 4
        feedback_parts.append(f"~ Report has {fields_present}/4 required fields")
    else:
        feedback_parts.append("✗ Report missing most required fields")
    
    # ================================================================
    # CRITERION 3: ANGLE ACCURACY (35 pts)
    # ================================================================
    angle_achieved = False
    
    if agent_angle is not None:
        angle_error = abs(agent_angle - gt_angle)
        details['angle_error'] = angle_error
        
        feedback_parts.append(f"Agent measured: {agent_angle}° (GT: {gt_angle}°, error: {angle_error:.1f}°)")
        
        if angle_error <= angle_tolerance:
            scores['angle_accuracy'] = w_angle
            angle_achieved = True
            feedback_parts.append(f"✓ Angle within {angle_tolerance}° tolerance")
        elif angle_error <= angle_tolerance * 1.5:
            scores['angle_accuracy'] = w_angle * 2 // 3
            feedback_parts.append(f"~ Angle within extended tolerance ({angle_tolerance * 1.5}°)")
        elif angle_error <= angle_tolerance * 2:
            scores['angle_accuracy'] = w_angle // 3
            feedback_parts.append(f"~ Angle moderately off ({angle_error:.1f}° error)")
        else:
            feedback_parts.append(f"✗ Angle error ({angle_error:.1f}°) exceeds tolerance ({angle_tolerance}°)")
    else:
        feedback_parts.append("✗ No Cobb angle measurement found in report")
    
    # ================================================================
    # CRITERION 4: SUPERIOR VERTEBRA LEVEL (10 pts)
    # ================================================================
    if agent_superior:
        if vertebra_in_range(agent_superior, acceptable_superior):
            scores['superior_level'] = w_sup_level
            feedback_parts.append(f"✓ Superior vertebra {agent_superior} is acceptable")
        else:
            dist = vertebra_distance(agent_superior, gt_superior)
            if dist <= 2:
                scores['superior_level'] = w_sup_level // 2
                feedback_parts.append(f"~ Superior vertebra {agent_superior} within 2 levels of expected")
            else:
                feedback_parts.append(f"✗ Superior vertebra {agent_superior} not in acceptable range {acceptable_superior}")
    else:
        feedback_parts.append("✗ Superior vertebra not specified")
    
    # ================================================================
    # CRITERION 5: INFERIOR VERTEBRA LEVEL (10 pts)
    # ================================================================
    if agent_inferior:
        if vertebra_in_range(agent_inferior, acceptable_inferior):
            scores['inferior_level'] = w_inf_level
            feedback_parts.append(f"✓ Inferior vertebra {agent_inferior} is acceptable")
        else:
            dist = vertebra_distance(agent_inferior, gt_inferior)
            if dist <= 2:
                scores['inferior_level'] = w_inf_level // 2
                feedback_parts.append(f"~ Inferior vertebra {agent_inferior} within 2 levels of expected")
            else:
                feedback_parts.append(f"✗ Inferior vertebra {agent_inferior} not in acceptable range {acceptable_inferior}")
    else:
        feedback_parts.append("✗ Inferior vertebra not specified")
    
    # ================================================================
    # CRITERION 6: CLASSIFICATION (15 pts)
    # ================================================================
    if agent_classification:
        agent_class_norm = normalize_classification(agent_classification)
        gt_class_norm = normalize_classification(gt_classification)
        
        if agent_class_norm == gt_class_norm:
            scores['classification'] = w_classification
            feedback_parts.append(f"✓ Classification '{agent_classification}' is correct")
        else:
            # Check if internally consistent with reported angle
            if agent_angle is not None:
                expected_from_angle = classify_kyphosis(agent_angle)
                expected_norm = normalize_classification(expected_from_angle)
                
                if agent_class_norm == expected_norm:
                    scores['classification'] = w_classification // 2
                    feedback_parts.append(f"~ Classification matches agent's angle but not ground truth")
                else:
                    feedback_parts.append(f"✗ Classification '{agent_classification}' incorrect (expected: {gt_classification})")
            else:
                feedback_parts.append(f"✗ Classification '{agent_classification}' incorrect (expected: {gt_classification})")
    else:
        feedback_parts.append("✗ No classification provided")
    
    # ================================================================
    # CRITERION 7: VISUALIZATION (5 pts)
    # ================================================================
    vis_screenshot = result.get('visualization_screenshot', '')
    screenshot_count = result.get('agent_screenshot_count', 0)
    
    if vis_screenshot:
        scores['visualization'] = w_vis
        feedback_parts.append("✓ Visualization screenshot created")
    elif screenshot_count > 0:
        scores['visualization'] = w_vis // 2
        feedback_parts.append(f"~ {screenshot_count} screenshots found (partial credit)")
    elif result.get('screenshot_exists', False):
        scores['visualization'] = w_vis // 3
        feedback_parts.append("~ Final screenshot exists")
    else:
        feedback_parts.append("✗ No visualization screenshots")
    
    # ================================================================
    # CALCULATE FINAL SCORE
    # ================================================================
    total_score = sum(scores.values())
    max_score = w_angle + w_sup_level + w_inf_level + w_placement + w_classification + w_report + w_vis
    
    # Pass criteria: >= 60 points AND angle accuracy achieved (partial or full)
    angle_criterion_met = scores['angle_accuracy'] >= w_angle // 2
    passed = total_score >= min_pass_score and angle_criterion_met
    
    # Score breakdown
    feedback_parts.append("")
    feedback_parts.append("=== Score Breakdown ===")
    feedback_parts.append(f"  Angle Accuracy: {scores['angle_accuracy']}/{w_angle}")
    feedback_parts.append(f"  Superior Level: {scores['superior_level']}/{w_sup_level}")
    feedback_parts.append(f"  Inferior Level: {scores['inferior_level']}/{w_inf_level}")
    feedback_parts.append(f"  Anatomical Placement: {scores['anatomical_placement']}/{w_placement}")
    feedback_parts.append(f"  Classification: {scores['classification']}/{w_classification}")
    feedback_parts.append(f"  Report Complete: {scores['report_complete']}/{w_report}")
    feedback_parts.append(f"  Visualization: {scores['visualization']}/{w_vis}")
    feedback_parts.append(f"  TOTAL: {total_score}/{max_score}")
    feedback_parts.append("")
    feedback_parts.append(f"Pass threshold: {min_pass_score} points with angle accuracy")
    feedback_parts.append(f"Angle criterion met: {angle_criterion_met}")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_parts),
        "details": {
            "scores": scores,
            "max_scores": {
                'angle_accuracy': w_angle,
                'superior_level': w_sup_level,
                'inferior_level': w_inf_level,
                'anatomical_placement': w_placement,
                'classification': w_classification,
                'report_complete': w_report,
                'visualization': w_vis
            },
            "agent_measurements": details.get('agent_measurements', {}),
            "ground_truth": details.get('ground_truth', {}),
            "angle_error": details.get('angle_error'),
            "angle_criterion_met": angle_criterion_met
        }
    }


def main():
    """Main entry point for standalone verification testing."""
    result_file = "/tmp/task_result.json"
    gt_file = "/tmp/kyphosis_ground_truth.json"
    
    if not os.path.exists(result_file):
        print(json.dumps({
            "passed": False,
            "score": 0,
            "feedback": "No result file found. Run export_result.sh first."
        }, indent=2))
        return
    
    with open(result_file, 'r') as f:
        result_data = json.load(f)
    
    gt_data = {}
    if os.path.exists(gt_file):
        with open(gt_file, 'r') as f:
            gt_data = json.load(f)
    
    # Mock verification for testing
    print(json.dumps({
        "result_data": result_data,
        "ground_truth": gt_data,
        "note": "Run through framework for full verification"
    }, indent=2))


if __name__ == "__main__":
    main()