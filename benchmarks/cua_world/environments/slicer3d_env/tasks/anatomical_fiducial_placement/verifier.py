#!/usr/bin/env python3
"""
Verifier for anatomical landmark fiducial placement task.

VERIFICATION STRATEGY:
1. Check that markup file exists and was created during task
2. Verify 4 fiducial points are present
3. Check that points have meaningful labels (not default F-1, F-2, etc.)
4. Compare each placed position to expected anatomical location
5. Check bilateral symmetry of tragus points

Ground truth is computed from volume geometry - expected positions are
approximate based on typical brain anatomy relative to volume extent.

Scoring (100 points total):
- Markup file created: 15 points
- Four points present: 15 points
- Points labeled: 10 points
- Nasion accuracy: 15 points (within tolerance)
- Inion accuracy: 15 points (within tolerance)
- Left tragus accuracy: 10 points
- Right tragus accuracy: 10 points
- Bilateral symmetry: 8 points
- Screenshot created: 2 points
"""

import json
import os
import sys
import tempfile
import logging
import math
from typing import Dict, List, Tuple, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def euclidean_distance(p1: List[float], p2: List[float]) -> float:
    """Calculate 3D Euclidean distance between two points."""
    if len(p1) != 3 or len(p2) != 3:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


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


def parse_slicer_markup(markup_data: dict) -> List[Dict[str, Any]]:
    """
    Parse Slicer markup JSON format to extract fiducial points.
    
    Slicer markup format:
    {
        "markups": [{
            "type": "Fiducial",
            "controlPoints": [
                {"label": "F-1", "position": [x, y, z]},
                ...
            ]
        }]
    }
    """
    fiducials = []
    
    # Handle Slicer markup format
    if "markups" in markup_data:
        for markup in markup_data.get("markups", []):
            for cp in markup.get("controlPoints", []):
                fid = {
                    "label": cp.get("label", ""),
                    "position": cp.get("position", [0, 0, 0])
                }
                fiducials.append(fid)
    
    # Handle consolidated format from export script
    elif "fiducials" in markup_data:
        for fid in markup_data["fiducials"]:
            fiducials.append({
                "label": fid.get("label", fid.get("name", "")),
                "position": fid.get("position", fid.get("position_ras", [0, 0, 0]))
            })
    
    # Handle simple list format
    elif isinstance(markup_data, list):
        for item in markup_data:
            if isinstance(item, dict):
                fiducials.append({
                    "label": item.get("label", ""),
                    "position": item.get("position", item.get("position_ras", [0, 0, 0]))
                })
    
    return fiducials


def match_fiducial_to_landmark(
    fiducials: List[Dict],
    landmark_name: str,
    expected_pos: List[float],
    tolerance: float
) -> Tuple[Optional[Dict], float, bool]:
    """
    Find the fiducial that best matches a landmark.
    
    First tries to match by label (case-insensitive partial match),
    then by position if no label match.
    
    Returns: (matched_fiducial, distance, within_tolerance)
    """
    # Normalize landmark name for matching
    landmark_lower = landmark_name.lower().replace("_", "").replace("-", "").replace(" ", "")
    
    # First try to match by label
    for fid in fiducials:
        label = fid.get("label", "").lower().replace("_", "").replace("-", "").replace(" ", "")
        
        # Check for various matching patterns
        if landmark_lower in label or label in landmark_lower:
            pos = fid.get("position", [0, 0, 0])
            dist = euclidean_distance(pos, expected_pos)
            return fid, dist, dist <= tolerance
        
        # Also check common abbreviations
        abbrevs = {
            "nasion": ["nas", "n"],
            "inion": ["ini", "in", "i"],
            "lefttragus": ["lt", "ltragus", "lefttrag", "leftear"],
            "righttragus": ["rt", "rtragus", "righttrag", "rightear"]
        }
        
        if landmark_lower in abbrevs:
            for abbrev in abbrevs[landmark_lower]:
                if abbrev in label or label == abbrev:
                    pos = fid.get("position", [0, 0, 0])
                    dist = euclidean_distance(pos, expected_pos)
                    return fid, dist, dist <= tolerance
    
    # If no label match, find closest point by position
    best_fid = None
    best_dist = float('inf')
    
    for fid in fiducials:
        pos = fid.get("position", [0, 0, 0])
        dist = euclidean_distance(pos, expected_pos)
        if dist < best_dist:
            best_dist = dist
            best_fid = fid
    
    if best_fid:
        return best_fid, best_dist, best_dist <= tolerance
    
    return None, float('inf'), False


def check_labels_meaningful(fiducials: List[Dict]) -> Tuple[bool, int]:
    """
    Check if fiducials have meaningful labels (not default F-1, F-2, etc.)
    
    Returns: (all_meaningful, count_meaningful)
    """
    default_patterns = ["f-", "f_", "point", "markup", "fiducial"]
    meaningful_count = 0
    
    for fid in fiducials:
        label = fid.get("label", "").lower().strip()
        
        # Check if label is empty or matches default patterns
        is_default = False
        if not label:
            is_default = True
        else:
            for pattern in default_patterns:
                if label.startswith(pattern) and len(label) <= len(pattern) + 2:
                    is_default = True
                    break
            
            # Also check if it's just a number
            if label.isdigit():
                is_default = True
        
        if not is_default:
            meaningful_count += 1
    
    return meaningful_count == len(fiducials), meaningful_count


def verify_anatomical_fiducial_placement(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Verify anatomical landmark fiducial placement task.
    
    Multi-criteria scoring:
    - Markup file created: 15 points
    - Four points present: 15 points  
    - Points labeled: 10 points
    - Nasion accuracy: 15 points
    - Inion accuracy: 15 points
    - Left tragus accuracy: 10 points
    - Right tragus accuracy: 10 points
    - Bilateral symmetry: 8 points
    - Screenshot created: 2 points
    
    Pass threshold: 60 points with at least 2 landmarks correctly placed
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
    position_tolerance = metadata.get('position_tolerance_mm', 20.0)
    symmetry_tolerance = metadata.get('symmetry_tolerance_mm', 10.0)
    weights = metadata.get('scoring_weights', {})
    
    w_markup = weights.get('markup_file_created', 15)
    w_points = weights.get('four_points_present', 15)
    w_labels = weights.get('points_labeled', 10)
    w_nasion = weights.get('nasion_accuracy', 15)
    w_inion = weights.get('inion_accuracy', 15)
    w_left = weights.get('left_tragus_accuracy', 10)
    w_right = weights.get('right_tragus_accuracy', 10)
    w_symmetry = weights.get('bilateral_symmetry', 8)
    w_screenshot = weights.get('screenshot_created', 2)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    landmarks_correct = 0
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fiducial_task_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # CRITERION 1: Markup file exists (15 points)
    # ================================================================
    markup_exists = result.get('markup_exists', False)
    markup_created_during_task = result.get('markup_created_during_task', False)
    
    if markup_exists:
        if markup_created_during_task:
            score += w_markup
            feedback_parts.append(f"✓ Markup file created during task (+{w_markup})")
        else:
            score += w_markup // 2
            feedback_parts.append(f"△ Markup file exists but may pre-date task (+{w_markup // 2})")
    else:
        feedback_parts.append("✗ No markup file found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"markup_exists": False}
        }
    
    # ================================================================
    # Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/landmarks_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        feedback_parts.append("△ Ground truth not available - using relaxed verification")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    expected_landmarks = gt_data.get('expected_landmarks', {})
    details['ground_truth'] = expected_landmarks
    
    # ================================================================
    # Load agent markup
    # ================================================================
    temp_markup = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    markup_data = {}
    fiducials = []
    
    try:
        copy_from_env("/tmp/agent_landmarks.mrk.json", temp_markup.name)
        with open(temp_markup.name, 'r') as f:
            markup_data = json.load(f)
        fiducials = parse_slicer_markup(markup_data)
    except Exception as e:
        logger.warning(f"Failed to parse markup: {e}")
        # Try using fiducial data from result
        fiducials = result.get('fiducial_data', [])
        if isinstance(fiducials, str):
            try:
                fiducials = json.loads(fiducials)
            except:
                fiducials = []
    finally:
        if os.path.exists(temp_markup.name):
            os.unlink(temp_markup.name)
    
    details['fiducials_found'] = len(fiducials)
    details['fiducials'] = fiducials
    
    # ================================================================
    # CRITERION 2: Four points present (15 points)
    # ================================================================
    num_fiducials = len(fiducials)
    
    if num_fiducials >= 4:
        score += w_points
        feedback_parts.append(f"✓ {num_fiducials} fiducial points placed (+{w_points})")
    elif num_fiducials >= 2:
        partial = (w_points * num_fiducials) // 4
        score += partial
        feedback_parts.append(f"△ Only {num_fiducials}/4 points placed (+{partial})")
    else:
        feedback_parts.append(f"✗ Only {num_fiducials}/4 points placed")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    # ================================================================
    # CRITERION 3: Points have meaningful labels (10 points)
    # ================================================================
    all_labeled, labeled_count = check_labels_meaningful(fiducials)
    
    if all_labeled:
        score += w_labels
        feedback_parts.append(f"✓ All points have anatomical labels (+{w_labels})")
    elif labeled_count > 0:
        partial = (w_labels * labeled_count) // len(fiducials)
        score += partial
        feedback_parts.append(f"△ {labeled_count}/{len(fiducials)} points labeled (+{partial})")
    else:
        feedback_parts.append("✗ Points have default labels")
    
    details['labeled_count'] = labeled_count
    
    # ================================================================
    # CRITERIA 4-7: Landmark position accuracy
    # ================================================================
    landmark_results = {}
    
    # Match each expected landmark
    landmark_weights = {
        "Nasion": w_nasion,
        "Inion": w_inion,
        "Left_Tragus": w_left,
        "Right_Tragus": w_right
    }
    
    matched_positions = {}
    
    for landmark_name, weight in landmark_weights.items():
        if landmark_name not in expected_landmarks:
            feedback_parts.append(f"△ No ground truth for {landmark_name}")
            continue
        
        expected_pos = expected_landmarks[landmark_name].get('position_ras', [0, 0, 0])
        
        matched_fid, distance, within_tolerance = match_fiducial_to_landmark(
            fiducials, landmark_name, expected_pos, position_tolerance
        )
        
        landmark_results[landmark_name] = {
            "expected": expected_pos,
            "matched": matched_fid,
            "distance_mm": round(distance, 1) if distance != float('inf') else None,
            "within_tolerance": within_tolerance
        }
        
        if matched_fid:
            matched_positions[landmark_name] = matched_fid.get('position', [0, 0, 0])
        
        if within_tolerance:
            score += weight
            landmarks_correct += 1
            feedback_parts.append(f"✓ {landmark_name}: {distance:.1f}mm from expected (+{weight})")
        elif matched_fid and distance < position_tolerance * 2:
            # Partial credit for close but not within tolerance
            partial = weight // 2
            score += partial
            feedback_parts.append(f"△ {landmark_name}: {distance:.1f}mm (outside {position_tolerance}mm tolerance) (+{partial})")
        elif matched_fid:
            feedback_parts.append(f"✗ {landmark_name}: {distance:.1f}mm from expected")
        else:
            feedback_parts.append(f"✗ {landmark_name}: not identified")
    
    details['landmark_results'] = landmark_results
    
    # ================================================================
    # CRITERION 8: Bilateral symmetry check (8 points)
    # ================================================================
    if 'Left_Tragus' in matched_positions and 'Right_Tragus' in matched_positions:
        left_pos = matched_positions['Left_Tragus']
        right_pos = matched_positions['Right_Tragus']
        
        # Check X-axis symmetry (should be roughly equal distance from midline)
        # In RAS, X is left-right, with positive being right
        left_x = left_pos[0]
        right_x = right_pos[0]
        
        # The midline X should be approximately at 0 or center
        # Left should be negative, right should be positive (or both positive/negative but opposite)
        symmetry_diff = abs(abs(left_x) - abs(right_x))
        
        # Also check Y and Z are similar (both should be at ear level)
        y_diff = abs(left_pos[1] - right_pos[1])
        z_diff = abs(left_pos[2] - right_pos[2])
        
        is_symmetric = (symmetry_diff < symmetry_tolerance and 
                       y_diff < symmetry_tolerance * 2 and 
                       z_diff < symmetry_tolerance * 2)
        
        details['symmetry_check'] = {
            "x_symmetry_diff": round(symmetry_diff, 1),
            "y_diff": round(y_diff, 1),
            "z_diff": round(z_diff, 1),
            "symmetric": is_symmetric
        }
        
        if is_symmetric:
            score += w_symmetry
            feedback_parts.append(f"✓ Tragus points are bilaterally symmetric (+{w_symmetry})")
        else:
            feedback_parts.append(f"✗ Tragus points not symmetric (X diff: {symmetry_diff:.1f}mm)")
    else:
        feedback_parts.append("△ Cannot check symmetry - missing tragus points")
    
    # ================================================================
    # CRITERION 9: Screenshot created (2 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    
    if screenshot_exists:
        score += w_screenshot
        feedback_parts.append(f"✓ Screenshot created (+{w_screenshot})")
    else:
        feedback_parts.append("✗ No screenshot")
    
    # ================================================================
    # Final assessment
    # ================================================================
    details['landmarks_correct'] = landmarks_correct
    details['score_breakdown'] = {
        'markup_file': w_markup if markup_exists else 0,
        'points_present': w_points if num_fiducials >= 4 else (w_points * num_fiducials) // 4,
        'labels': w_labels if all_labeled else (w_labels * labeled_count) // max(len(fiducials), 1),
        'position_accuracy': sum(
            landmark_weights[lm] if landmark_results.get(lm, {}).get('within_tolerance') else 0
            for lm in landmark_weights
        ),
        'symmetry': w_symmetry if details.get('symmetry_check', {}).get('symmetric') else 0,
        'screenshot': w_screenshot if screenshot_exists else 0
    }
    
    # Pass requires: score >= 60 AND at least 2 landmarks correctly placed
    passed = score >= 60 and landmarks_correct >= 2
    
    # Generate final feedback
    feedback_summary = f"Score: {score}/100 | Landmarks correct: {landmarks_correct}/4"
    if passed:
        feedback_summary = f"✓ PASSED - {feedback_summary}"
    else:
        if landmarks_correct < 2:
            feedback_summary = f"✗ FAILED (need ≥2 correct landmarks) - {feedback_summary}"
        else:
            feedback_summary = f"✗ FAILED (need ≥60 points) - {feedback_summary}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_summary + " | " + " | ".join(feedback_parts),
        "details": to_python_type(details)
    }