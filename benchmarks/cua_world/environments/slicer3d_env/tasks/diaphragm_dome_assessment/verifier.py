#!/usr/bin/env python3
"""
Verifier for Diaphragm Dome Position and Symmetry Assessment Task.

VERIFICATION STRATEGY:
1. Primary: Compare agent's dome positions to ground truth (file-based)
2. Secondary: Verify vertebral level assignments
3. Tertiary: Check clinical interpretation consistency
4. Anti-gaming: Verify files were created during task execution

SCORING (100 points total):
- Right dome position accuracy: 20 points (within 10mm)
- Left dome position accuracy: 20 points (within 10mm)
- Height difference calculation: 15 points (within 5mm)
- Vertebral level assignments: 15 points (within 1 level each)
- Fiducial markers placed: 10 points
- Report completeness: 10 points
- Clinical interpretation: 10 points

Pass threshold: 60 points with both dome positions acceptable
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_json_file(filepath: str) -> Dict[str, Any]:
    """Load and parse a JSON file."""
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load {filepath}: {e}")
        return {"error": str(e)}


def extract_marker_positions(marker_data: Dict) -> Dict[str, float]:
    """
    Extract dome positions from Slicer markup JSON.
    
    Returns dict with 'right_z' and 'left_z' if found.
    """
    positions = {}
    
    try:
        markups = marker_data.get("markups", [{}])
        if not markups:
            return positions
        
        control_points = markups[0].get("controlPoints", [])
        
        for cp in control_points:
            label = cp.get("label", "").lower().strip()
            pos = cp.get("position", [0, 0, 0])
            z_pos = pos[2] if len(pos) > 2 else 0
            
            # Try to identify which dome this marker represents
            if "right" in label or label == "r":
                positions["right_z"] = z_pos
                positions["right_label"] = cp.get("label", "")
            elif "left" in label or label == "l":
                positions["left_z"] = z_pos
                positions["left_label"] = cp.get("label", "")
            elif len(positions) == 0:
                # First unlabeled marker
                positions["first_z"] = z_pos
                positions["first_label"] = cp.get("label", "")
            elif "first_z" in positions and "second_z" not in positions:
                # Second unlabeled marker
                positions["second_z"] = z_pos
                positions["second_label"] = cp.get("label", "")
        
        # If markers aren't explicitly labeled, infer based on position
        # (right dome is typically higher = larger Z in standard orientation)
        if "right_z" not in positions and "left_z" not in positions:
            if "first_z" in positions and "second_z" in positions:
                # Assume higher Z is right dome (normal anatomy)
                if positions["first_z"] > positions["second_z"]:
                    positions["right_z"] = positions["first_z"]
                    positions["left_z"] = positions["second_z"]
                else:
                    positions["right_z"] = positions["second_z"]
                    positions["left_z"] = positions["first_z"]
                positions["inferred"] = True
                
    except Exception as e:
        positions["error"] = str(e)
        logger.error(f"Error extracting marker positions: {e}")
    
    return positions


def verify_dome_position(agent_z: float, gt_z: float, tolerance: float = 10.0) -> Tuple[bool, float]:
    """
    Verify a single dome position against ground truth.
    
    Returns (passed, error_mm)
    """
    error = abs(agent_z - gt_z)
    passed = error <= tolerance
    return passed, error


def verify_vertebral_level(agent_level: str, gt_level: str) -> Tuple[bool, int]:
    """
    Verify vertebral level assignment.
    
    Returns (passed, level_difference)
    """
    level_order = ["T8", "T9", "T10", "T11", "T12", "L1", "L2", "L3", "L4"]
    
    try:
        # Normalize input
        agent_clean = agent_level.upper().strip()
        gt_clean = gt_level.upper().strip()
        
        agent_idx = level_order.index(agent_clean)
        gt_idx = level_order.index(gt_clean)
        diff = abs(agent_idx - gt_idx)
        passed = diff <= 1  # Within 1 vertebral level is acceptable
        return passed, diff
    except ValueError:
        return False, -1


def verify_diaphragm_assessment(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification function for diaphragm dome assessment task.
    
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
    
    position_error_max = thresholds.get('position_error_max_mm', 10.0)
    height_diff_error_max = thresholds.get('height_diff_error_max_mm', 5.0)
    
    w_right_pos = weights.get('right_dome_position', 20)
    w_left_pos = weights.get('left_dome_position', 20)
    w_height_diff = weights.get('height_difference', 15)
    w_vertebral = weights.get('vertebral_levels', 15)
    w_markers = weights.get('markers_placed', 10)
    w_report = weights.get('report_complete', 10)
    w_interp = weights.get('clinical_interpretation', 10)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # LOAD RESULT FILE
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check basic task execution
    if not result.get('slicer_was_running', False):
        feedback_parts.append("FAIL: 3D Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts)
        }
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/diaphragm_ground_truth.json", temp_gt.name)
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
    
    gt_right_z = gt.get('right_dome_z_mm', 0)
    gt_left_z = gt.get('left_dome_z_mm', 0)
    gt_right_level = gt.get('right_dome_vertebral_level', 'T10')
    gt_left_level = gt.get('left_dome_vertebral_level', 'T11')
    gt_height_diff = gt.get('height_difference_mm', 0)
    gt_is_normal = gt.get('is_normal', True)
    
    feedback_parts.append(f"Ground truth - Right: {gt_right_level} ({gt_right_z:.1f}mm), Left: {gt_left_level} ({gt_left_z:.1f}mm)")
    details['gt_right_z'] = gt_right_z
    details['gt_left_z'] = gt_left_z
    details['gt_height_diff'] = gt_height_diff
    
    # ================================================================
    # CHECK MARKER FILE
    # ================================================================
    markers_exist = result.get('markers_file_exists', False)
    markers_modified = result.get('markers_created_during_task', False)
    marker_count = result.get('marker_count', 0)
    
    marker_positions = {}
    
    if not markers_exist:
        feedback_parts.append("FAIL: No marker file found at expected path")
    else:
        if not markers_modified:
            feedback_parts.append("WARNING: Marker file may not have been created during this task session")
        else:
            feedback_parts.append("OK: Marker file exists and was created during task")
        
        # Load and parse markers
        temp_markers = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_markers.json", temp_markers.name)
            with open(temp_markers.name, 'r') as f:
                marker_data = json.load(f)
            marker_positions = extract_marker_positions(marker_data)
            
            if marker_count >= 2:
                score += w_markers
                feedback_parts.append(f"OK: {marker_count} fiducial markers placed (+{w_markers})")
            elif marker_count == 1:
                score += w_markers // 2
                feedback_parts.append(f"PARTIAL: Only {marker_count} marker placed (+{w_markers//2})")
            else:
                feedback_parts.append("FAIL: No markers found in file")
                
        except Exception as e:
            logger.warning(f"Could not load markers: {e}")
            feedback_parts.append(f"WARNING: Could not parse marker file: {e}")
        finally:
            if os.path.exists(temp_markers.name):
                os.unlink(temp_markers.name)
    
    details['marker_positions'] = marker_positions
    
    # ================================================================
    # VERIFY DOME POSITIONS
    # ================================================================
    agent_right_z = marker_positions.get('right_z')
    agent_left_z = marker_positions.get('left_z')
    
    if marker_positions.get('inferred'):
        feedback_parts.append("INFO: Markers not explicitly labeled, positions inferred from height")
    
    # Verify right dome position
    right_dome_score = 0
    if agent_right_z is not None:
        right_pass, right_error = verify_dome_position(agent_right_z, gt_right_z, position_error_max)
        details['agent_right_z'] = agent_right_z
        details['right_error_mm'] = right_error
        
        if right_pass:
            right_dome_score = w_right_pos
            feedback_parts.append(f"OK: Right dome position accurate (error: {right_error:.1f}mm) (+{w_right_pos})")
        elif right_error <= position_error_max * 2:
            right_dome_score = w_right_pos // 2
            feedback_parts.append(f"PARTIAL: Right dome position close (error: {right_error:.1f}mm) (+{w_right_pos//2})")
        else:
            feedback_parts.append(f"FAIL: Right dome position incorrect (error: {right_error:.1f}mm)")
    else:
        feedback_parts.append("FAIL: Right dome position not found in markers")
    score += right_dome_score
    
    # Verify left dome position
    left_dome_score = 0
    if agent_left_z is not None:
        left_pass, left_error = verify_dome_position(agent_left_z, gt_left_z, position_error_max)
        details['agent_left_z'] = agent_left_z
        details['left_error_mm'] = left_error
        
        if left_pass:
            left_dome_score = w_left_pos
            feedback_parts.append(f"OK: Left dome position accurate (error: {left_error:.1f}mm) (+{w_left_pos})")
        elif left_error <= position_error_max * 2:
            left_dome_score = w_left_pos // 2
            feedback_parts.append(f"PARTIAL: Left dome position close (error: {left_error:.1f}mm) (+{w_left_pos//2})")
        else:
            feedback_parts.append(f"FAIL: Left dome position incorrect (error: {left_error:.1f}mm)")
    else:
        feedback_parts.append("FAIL: Left dome position not found in markers")
    score += left_dome_score
    
    # ================================================================
    # VERIFY HEIGHT DIFFERENCE
    # ================================================================
    if agent_right_z is not None and agent_left_z is not None:
        agent_diff = agent_right_z - agent_left_z
        diff_error = abs(agent_diff - gt_height_diff)
        details['agent_height_diff'] = agent_diff
        details['height_diff_error'] = diff_error
        
        if diff_error <= height_diff_error_max:
            score += w_height_diff
            feedback_parts.append(f"OK: Height difference accurate ({agent_diff:.1f}mm, error: {diff_error:.1f}mm) (+{w_height_diff})")
        elif diff_error <= height_diff_error_max * 2:
            score += w_height_diff // 2
            feedback_parts.append(f"PARTIAL: Height difference close ({agent_diff:.1f}mm, error: {diff_error:.1f}mm) (+{w_height_diff//2})")
        else:
            feedback_parts.append(f"FAIL: Height difference incorrect ({agent_diff:.1f}mm, error: {diff_error:.1f}mm)")
    
    # ================================================================
    # CHECK REPORT FILE
    # ================================================================
    report_exists = result.get('report_file_exists', False)
    report_modified = result.get('report_created_during_task', False)
    
    if not report_exists:
        feedback_parts.append("FAIL: Report file not found")
    else:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        report = {}
        try:
            copy_from_env("/tmp/agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load report: {e}")
            feedback_parts.append(f"WARNING: Could not parse report file: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
        
        if report:
            # Check required fields
            required_fields = [
                "right_dome_vertebral_level",
                "left_dome_vertebral_level",
                "height_difference_mm",
                "clinical_interpretation"
            ]
            
            present_fields = sum(1 for f in required_fields if f in report)
            
            if present_fields == len(required_fields):
                score += w_report
                feedback_parts.append(f"OK: Report contains all required fields (+{w_report})")
            elif present_fields > 0:
                partial_score = (w_report * present_fields) // len(required_fields)
                score += partial_score
                feedback_parts.append(f"PARTIAL: Report has {present_fields}/{len(required_fields)} required fields (+{partial_score})")
            else:
                feedback_parts.append("FAIL: Report missing required fields")
            
            details['report'] = report
            
            # Verify vertebral levels in report
            agent_right_level = report.get('right_dome_vertebral_level', '')
            agent_left_level = report.get('left_dome_vertebral_level', '')
            
            level_score = 0
            if agent_right_level:
                right_level_pass, right_level_diff = verify_vertebral_level(agent_right_level, gt_right_level)
                if right_level_pass:
                    level_score += w_vertebral // 2
                    feedback_parts.append(f"OK: Right vertebral level correct ({agent_right_level})")
                else:
                    feedback_parts.append(f"FAIL: Right vertebral level incorrect ({agent_right_level} vs {gt_right_level})")
            
            if agent_left_level:
                left_level_pass, left_level_diff = verify_vertebral_level(agent_left_level, gt_left_level)
                if left_level_pass:
                    level_score += w_vertebral // 2
                    feedback_parts.append(f"OK: Left vertebral level correct ({agent_left_level})")
                else:
                    feedback_parts.append(f"FAIL: Left vertebral level incorrect ({agent_left_level} vs {gt_left_level})")
            
            score += level_score
            
            # Verify clinical interpretation
            interpretation = report.get('clinical_interpretation', '').lower()
            
            if gt_is_normal:
                if 'normal' in interpretation:
                    score += w_interp
                    feedback_parts.append(f"OK: Clinical interpretation correct (normal) (+{w_interp})")
                elif 'mild' in interpretation or 'variant' in interpretation:
                    score += w_interp // 2
                    feedback_parts.append(f"PARTIAL: Interpretation reasonable but imprecise (+{w_interp//2})")
                else:
                    feedback_parts.append("FAIL: Interpretation suggests abnormality when findings are normal")
            else:
                if any(word in interpretation for word in ['abnormal', 'elevated', 'palsy', 'asymmetry', 'patholog']):
                    score += w_interp
                    feedback_parts.append(f"OK: Clinical interpretation correctly identifies abnormality (+{w_interp})")
                else:
                    feedback_parts.append("FAIL: Interpretation misses abnormal findings")
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    # Pass requires: score >= 60 AND both dome positions reasonably accurate
    key_criteria_met = (right_dome_score >= w_right_pos // 2) and (left_dome_score >= w_left_pos // 2)
    passed = score >= 60 and key_criteria_met
    
    feedback_parts.append("")
    feedback_parts.append(f"=== FINAL SCORE: {score}/100 ===")
    feedback_parts.append(f"Pass threshold: 60 points with both dome positions acceptable")
    feedback_parts.append(f"Key criteria met: {key_criteria_met}")
    feedback_parts.append(f"Result: {'PASS' if passed else 'FAIL'}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # For standalone testing
    print("Diaphragm Assessment Verifier")
    print("This verifier requires the gym-anything framework to run.")
    print("Use: verify_diaphragm_assessment(traj, env_info, task_info)")