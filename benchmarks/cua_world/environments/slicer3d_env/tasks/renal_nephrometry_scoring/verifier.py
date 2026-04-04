#!/usr/bin/env python3
"""
Verifier for Renal Mass RENAL Nephrometry Scoring task.

VERIFICATION STRATEGY:
1. R Score: Check diameter measurement and score (15 points)
2. E Score: Check exophytic assessment (15 points)
3. N Score: Check nearness measurement and score (15 points)
4. A Location: Check anterior/posterior determination (10 points)
5. L Score: Check polar line assessment (15 points)
6. Total Score: Check overall score accuracy (15 points)
7. Complexity: Check clinical classification (10 points)
8. Report Completeness: All required fields present (5 points)

Pass threshold: 60 points AND at least 3/5 individual scores correct
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_json_safe(filepath: str) -> Tuple[bool, Dict[str, Any]]:
    """Safely load and parse a JSON file."""
    try:
        with open(filepath, 'r') as f:
            return True, json.load(f)
    except FileNotFoundError:
        return False, {"error": "File not found"}
    except json.JSONDecodeError as e:
        return False, {"error": f"Invalid JSON: {e}"}
    except Exception as e:
        return False, {"error": str(e)}


def verify_r_score(agent: Dict, gt: Dict, tolerance_cm: float = 1.0) -> Tuple[int, str, bool]:
    """
    Verify R (Radius/diameter) score.
    Returns: (points, feedback, score_correct)
    """
    points = 0
    feedback_parts = []
    score_correct = False
    
    agent_diam = agent.get('R_diameter_cm')
    gt_diam = gt.get('R_diameter_cm', 0)
    agent_score = agent.get('R_score')
    gt_score = gt.get('R_score', 0)
    
    if agent_diam is None:
        return 0, "R: No diameter measurement provided", False
    
    try:
        agent_diam = float(agent_diam)
    except (ValueError, TypeError):
        return 0, f"R: Invalid diameter value '{agent_diam}'", False
    
    diam_error = abs(agent_diam - gt_diam)
    
    # Points for diameter accuracy
    if diam_error <= tolerance_cm:
        points += 8
        feedback_parts.append(f"R diameter: {agent_diam}cm (GT: {gt_diam}cm, error: {diam_error:.1f}cm) ✓")
    elif diam_error <= tolerance_cm * 2:
        points += 4
        feedback_parts.append(f"R diameter: {agent_diam}cm (GT: {gt_diam}cm, error: {diam_error:.1f}cm) ~")
    else:
        feedback_parts.append(f"R diameter: {agent_diam}cm (GT: {gt_diam}cm, error: {diam_error:.1f}cm) ✗")
    
    # Points for score
    if agent_score is not None:
        try:
            agent_score = int(agent_score)
            if agent_score == gt_score:
                points += 7
                score_correct = True
                feedback_parts.append(f"R score: {agent_score} ✓")
            else:
                feedback_parts.append(f"R score: {agent_score} (expected {gt_score}) ✗")
        except (ValueError, TypeError):
            feedback_parts.append(f"R score: invalid value '{agent_score}'")
    else:
        feedback_parts.append("R score: not provided")
    
    return points, "; ".join(feedback_parts), score_correct


def verify_e_score(agent: Dict, gt: Dict) -> Tuple[int, str, bool]:
    """Verify E (Exophytic) score."""
    points = 0
    score_correct = False
    
    agent_score = agent.get('E_score')
    gt_score = gt.get('E_score', 0)
    
    if agent_score is None:
        return 0, "E: No exophytic score provided", False
    
    try:
        agent_score = int(agent_score)
    except (ValueError, TypeError):
        return 0, f"E: Invalid score value '{agent_score}'", False
    
    score_diff = abs(agent_score - gt_score)
    
    if score_diff == 0:
        points = 15
        score_correct = True
        feedback = f"E score: {agent_score} ✓"
    elif score_diff == 1:
        points = 8
        feedback = f"E score: {agent_score} (GT: {gt_score}, within ±1) ~"
    else:
        feedback = f"E score: {agent_score} (expected {gt_score}) ✗"
    
    return points, feedback, score_correct


def verify_n_score(agent: Dict, gt: Dict, tolerance_mm: float = 3.0) -> Tuple[int, str, bool]:
    """Verify N (Nearness) score."""
    points = 0
    feedback_parts = []
    score_correct = False
    
    agent_dist = agent.get('N_distance_mm')
    gt_dist = gt.get('N_distance_mm', 0)
    agent_score = agent.get('N_score')
    gt_score = gt.get('N_score', 0)
    
    if agent_dist is None:
        return 0, "N: No distance measurement provided", False
    
    try:
        agent_dist = float(agent_dist)
    except (ValueError, TypeError):
        return 0, f"N: Invalid distance value '{agent_dist}'", False
    
    dist_error = abs(agent_dist - gt_dist)
    
    # Points for distance accuracy
    if dist_error <= tolerance_mm:
        points += 8
        feedback_parts.append(f"N distance: {agent_dist}mm (GT: {gt_dist}mm, error: {dist_error:.1f}mm) ✓")
    elif dist_error <= tolerance_mm * 2:
        points += 4
        feedback_parts.append(f"N distance: {agent_dist}mm (GT: {gt_dist}mm, error: {dist_error:.1f}mm) ~")
    else:
        feedback_parts.append(f"N distance: {agent_dist}mm (GT: {gt_dist}mm, error: {dist_error:.1f}mm) ✗")
    
    # Points for score
    if agent_score is not None:
        try:
            agent_score = int(agent_score)
            score_diff = abs(agent_score - gt_score)
            if score_diff == 0:
                points += 7
                score_correct = True
                feedback_parts.append(f"N score: {agent_score} ✓")
            elif score_diff == 1:
                points += 4
                feedback_parts.append(f"N score: {agent_score} (GT: {gt_score}, within ±1) ~")
            else:
                feedback_parts.append(f"N score: {agent_score} (expected {gt_score}) ✗")
        except (ValueError, TypeError):
            feedback_parts.append(f"N score: invalid value '{agent_score}'")
    else:
        feedback_parts.append("N score: not provided")
    
    return points, "; ".join(feedback_parts), score_correct


def verify_a_location(agent: Dict, gt: Dict) -> Tuple[int, str, bool]:
    """Verify A (Anterior/Posterior) location."""
    agent_loc = str(agent.get('A_location', '')).lower().strip()
    gt_loc = str(gt.get('A_location', '')).lower().strip()
    
    if not agent_loc:
        return 0, "A: No location provided", False
    
    # Normalize values
    agent_loc = agent_loc[0] if agent_loc else ''
    gt_loc = gt_loc[0] if gt_loc else ''
    
    if agent_loc == gt_loc:
        return 10, f"A location: {agent_loc} ✓", True
    else:
        return 0, f"A location: {agent_loc} (expected {gt_loc}) ✗", False


def verify_l_score(agent: Dict, gt: Dict) -> Tuple[int, str, bool]:
    """Verify L (Location/polar lines) score."""
    agent_score = agent.get('L_score')
    gt_score = gt.get('L_score', 0)
    
    if agent_score is None:
        return 0, "L: No score provided", False
    
    try:
        agent_score = int(agent_score)
    except (ValueError, TypeError):
        return 0, f"L: Invalid score value '{agent_score}'", False
    
    score_diff = abs(agent_score - gt_score)
    
    if score_diff == 0:
        return 15, f"L score: {agent_score} ✓", True
    elif score_diff == 1:
        return 8, f"L score: {agent_score} (GT: {gt_score}, within ±1) ~", False
    else:
        return 0, f"L score: {agent_score} (expected {gt_score}) ✗", False


def verify_total_and_complexity(agent: Dict, gt: Dict) -> Tuple[int, str]:
    """Verify total score and complexity classification."""
    points = 0
    feedback_parts = []
    
    agent_total = agent.get('total_score')
    gt_total = gt.get('total_score', 0)
    agent_complexity = str(agent.get('complexity', '')).lower().strip()
    gt_complexity = str(gt.get('complexity', '')).lower().strip()
    
    # Total score (15 points)
    if agent_total is not None:
        try:
            agent_total = int(agent_total)
            total_diff = abs(agent_total - gt_total)
            if total_diff <= 1:
                points += 15
                feedback_parts.append(f"Total score: {agent_total} (GT: {gt_total}) ✓")
            elif total_diff <= 2:
                points += 10
                feedback_parts.append(f"Total score: {agent_total} (GT: {gt_total}, diff: {total_diff}) ~")
            else:
                feedback_parts.append(f"Total score: {agent_total} (GT: {gt_total}, diff: {total_diff}) ✗")
        except (ValueError, TypeError):
            feedback_parts.append(f"Total score: invalid value '{agent_total}'")
    else:
        feedback_parts.append("Total score: not provided")
    
    # Complexity (10 points)
    if agent_complexity:
        if agent_complexity == gt_complexity:
            points += 10
            feedback_parts.append(f"Complexity: {agent_complexity.title()} ✓")
        else:
            feedback_parts.append(f"Complexity: {agent_complexity.title()} (expected {gt_complexity.title()}) ✗")
    else:
        feedback_parts.append("Complexity: not provided")
    
    return points, "; ".join(feedback_parts)


def verify_report_completeness(agent: Dict) -> Tuple[int, str]:
    """Check if all required fields are present."""
    required_fields = [
        'tumor_side', 'R_diameter_cm', 'R_score', 'E_score',
        'N_distance_mm', 'N_score', 'A_location', 'L_score',
        'total_score', 'complexity'
    ]
    
    present = sum(1 for f in required_fields if f in agent and agent[f] is not None and str(agent[f]).strip())
    total = len(required_fields)
    
    if present == total:
        return 5, f"Report completeness: {present}/{total} fields ✓"
    elif present >= total * 0.7:
        return 3, f"Report completeness: {present}/{total} fields ~"
    elif present >= total * 0.5:
        return 1, f"Report completeness: {present}/{total} fields"
    else:
        return 0, f"Report completeness: {present}/{total} fields ✗"


def verify_renal_nephrometry(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification function for RENAL nephrometry scoring task.
    
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
    
    diameter_tolerance = thresholds.get('diameter_error_max_cm', 1.0)
    distance_tolerance = thresholds.get('distance_error_max_mm', 3.0)
    min_correct_scores = thresholds.get('min_correct_scores', 3)
    
    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/renal_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check basic requirements
    if not result.get('report_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Agent did not create renal_score_report.json - no RENAL score submitted"
        }
    
    if not result.get('report_valid', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Agent's report file is not valid JSON"
        }
    
    # Anti-gaming check
    if not result.get('report_created_during_task', False):
        logger.warning("Report file may have existed before task - checking carefully")
    
    # Load agent's report
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent = {}
    try:
        copy_from_env("/tmp/agent_renal_report.json", temp_agent.name)
        with open(temp_agent.name, 'r') as f:
            agent = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load agent's report: {e}"
        }
    finally:
        if os.path.exists(temp_agent.name):
            os.unlink(temp_agent.name)
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/renal_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load ground truth: {e}"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Verify each component
    total_score = 0
    all_feedback = []
    correct_scores = 0
    
    # R Score (15 points)
    pts, fb, correct = verify_r_score(agent, gt, diameter_tolerance)
    total_score += pts
    all_feedback.append(fb)
    if correct:
        correct_scores += 1
    
    # E Score (15 points)
    pts, fb, correct = verify_e_score(agent, gt)
    total_score += pts
    all_feedback.append(fb)
    if correct:
        correct_scores += 1
    
    # N Score (15 points)
    pts, fb, correct = verify_n_score(agent, gt, distance_tolerance)
    total_score += pts
    all_feedback.append(fb)
    if correct:
        correct_scores += 1
    
    # A Location (10 points)
    pts, fb, correct = verify_a_location(agent, gt)
    total_score += pts
    all_feedback.append(fb)
    if correct:
        correct_scores += 1
    
    # L Score (15 points)
    pts, fb, correct = verify_l_score(agent, gt)
    total_score += pts
    all_feedback.append(fb)
    if correct:
        correct_scores += 1
    
    # Total and Complexity (25 points)
    pts, fb = verify_total_and_complexity(agent, gt)
    total_score += pts
    all_feedback.append(fb)
    
    # Report completeness (5 points)
    pts, fb = verify_report_completeness(agent)
    total_score += pts
    all_feedback.append(fb)
    
    # Determine pass/fail
    # Pass threshold: 60 points AND at least 3/5 individual scores correct
    passed = total_score >= 60 and correct_scores >= min_correct_scores
    
    # Build detailed feedback
    summary = f"Score: {total_score}/100 | Individual scores correct: {correct_scores}/5"
    if passed:
        summary = f"✓ PASSED - {summary}"
    else:
        if total_score < 60:
            summary = f"✗ FAILED (score < 60) - {summary}"
        else:
            summary = f"✗ FAILED (need {min_correct_scores}+ correct scores) - {summary}"
    
    # Output result
    output = {
        "passed": passed,
        "score": total_score,
        "feedback": summary + " || " + " | ".join(all_feedback),
        "details": {
            "individual_scores_correct": correct_scores,
            "min_required_correct": min_correct_scores,
            "agent_total_score": agent.get('total_score', 'N/A'),
            "ground_truth_total": gt.get('total_score', 'N/A'),
            "agent_complexity": agent.get('complexity', 'N/A'),
            "ground_truth_complexity": gt.get('complexity', 'N/A'),
            "slicer_was_running": result.get('slicer_was_running', False),
            "report_created_during_task": result.get('report_created_during_task', False)
        }
    }
    
    logger.info(f"Verification complete: passed={passed}, score={total_score}")
    return output


if __name__ == "__main__":
    # Test mode
    print("Renal Nephrometry Verifier - Test Mode")
    print("This verifier should be called by the gym-anything framework")