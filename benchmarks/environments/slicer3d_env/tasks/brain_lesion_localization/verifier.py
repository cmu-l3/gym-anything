#!/usr/bin/env python3
"""
Verifier for brain lesion localization task.

VERIFICATION METRICS:
1. Centroid accuracy - Euclidean distance from agent's fiducial to ground truth centroid
2. Fiducial placed - Did agent create a markup point
3. Screenshots exist - All three orthogonal views captured
4. Laterality correct - Left/right/midline matches ground truth
5. Midline distance - Accuracy of reported distance from midline
6. Report completeness - All required fields present

Scoring (100 points total):
- Centroid accuracy: 30 points (within 15mm)
- Fiducial placed: 10 points
- Axial screenshot: 10 points
- Coronal screenshot: 10 points
- Sagittal screenshot: 10 points
- Laterality correct: 10 points
- Midline distance: 10 points
- Report complete: 10 points

Pass threshold: 60 points with centroid accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import numpy
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    if HAS_NUMPY:
        if isinstance(val, (np.integer, np.int32, np.int64)):
            return int(val)
        elif isinstance(val, (np.floating, np.float32, np.float64)):
            return float(val)
        elif isinstance(val, np.ndarray):
            return val.tolist()
        elif isinstance(val, np.bool_):
            return bool(val)
    if isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def parse_coordinate(val):
    """Parse a coordinate value that may be string or number."""
    if val is None or val == "":
        return None
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


def euclidean_distance(p1, p2):
    """Calculate Euclidean distance between two 3D points."""
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


def verify_brain_lesion_localization(traj, env_info, task_info):
    """
    Verify brain lesion localization task completion.
    
    Uses multiple independent signals to prevent gaming.
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
    
    centroid_error_max = thresholds.get('centroid_error_max_mm', 15.0)
    midline_tolerance = thresholds.get('midline_distance_tolerance_mm', 10.0)
    
    w_centroid = weights.get('centroid_accuracy', 30)
    w_fiducial = weights.get('fiducial_placed', 10)
    w_axial = weights.get('axial_screenshot', 10)
    w_coronal = weights.get('coronal_screenshot', 10)
    w_sagittal = weights.get('sagittal_screenshot', 10)
    w_laterality = weights.get('laterality_correct', 10)
    w_midline = weights.get('midline_distance', 10)
    w_report = weights.get('report_complete', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lesion_localization_result.json", temp_result.name)
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
        copy_from_env("/tmp/ground_truth_centroid.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_centroid_ras = gt_data.get('centroid_ras', {})
    gt_R = gt_centroid_ras.get('R', 0)
    gt_A = gt_centroid_ras.get('A', 0)
    gt_S = gt_centroid_ras.get('S', 0)
    gt_laterality = gt_data.get('laterality', '')
    gt_midline = gt_data.get('midline_distance_mm', 0)
    
    details['gt_centroid'] = {'R': gt_R, 'A': gt_A, 'S': gt_S}
    details['gt_laterality'] = gt_laterality
    details['gt_midline_mm'] = gt_midline
    
    # ============================================================
    # CRITERION 1: FIDUCIAL PLACED (10 points)
    # ============================================================
    fiducial_exists = result.get('fiducial_exists', False)
    fiducial_coords = result.get('fiducial_coords', {})
    
    agent_R = parse_coordinate(fiducial_coords.get('R'))
    agent_A = parse_coordinate(fiducial_coords.get('A'))
    agent_S = parse_coordinate(fiducial_coords.get('S'))
    
    # Also check reported coords as fallback
    reported_coords = result.get('reported_coords', {})
    if agent_R is None:
        agent_R = parse_coordinate(reported_coords.get('R'))
    if agent_A is None:
        agent_A = parse_coordinate(reported_coords.get('A'))
    if agent_S is None:
        agent_S = parse_coordinate(reported_coords.get('S'))
    
    has_valid_coords = all(c is not None for c in [agent_R, agent_A, agent_S])
    
    if fiducial_exists and has_valid_coords:
        score += w_fiducial
        feedback_parts.append(f"✓ Fiducial placed at R={agent_R:.1f}, A={agent_A:.1f}, S={agent_S:.1f}")
        details['agent_centroid'] = {'R': agent_R, 'A': agent_A, 'S': agent_S}
    elif fiducial_exists:
        score += w_fiducial // 2
        feedback_parts.append("△ Fiducial file exists but coordinates not extracted")
    else:
        feedback_parts.append("✗ No fiducial marker placed")
    
    # ============================================================
    # CRITERION 2: CENTROID ACCURACY (30 points)
    # ============================================================
    centroid_accurate = False
    centroid_error = float('inf')
    
    if has_valid_coords and gt_R and gt_A and gt_S:
        agent_point = [agent_R, agent_A, agent_S]
        gt_point = [gt_R, gt_A, gt_S]
        centroid_error = euclidean_distance(agent_point, gt_point)
        details['centroid_error_mm'] = round(centroid_error, 2)
        
        if centroid_error <= centroid_error_max:
            score += w_centroid
            centroid_accurate = True
            feedback_parts.append(f"✓ Centroid accuracy: {centroid_error:.1f}mm (within {centroid_error_max}mm)")
        elif centroid_error <= centroid_error_max * 2:
            # Partial credit for close placement
            partial = int(w_centroid * (1 - centroid_error / (centroid_error_max * 2)))
            score += max(partial, 5)
            feedback_parts.append(f"△ Centroid placement: {centroid_error:.1f}mm (partial credit)")
        else:
            feedback_parts.append(f"✗ Centroid too far: {centroid_error:.1f}mm (max allowed: {centroid_error_max}mm)")
    else:
        feedback_parts.append("✗ Cannot verify centroid accuracy - missing coordinates")
    
    # ============================================================
    # CRITERION 3: SCREENSHOTS (30 points total - 10 each)
    # ============================================================
    axial_exists = result.get('axial_screenshot_exists', False)
    coronal_exists = result.get('coronal_screenshot_exists', False)
    sagittal_exists = result.get('sagittal_screenshot_exists', False)
    
    # Check screenshot files exist with reasonable size
    screenshot_checks = []
    for name, exists_flag, weight in [
        ('axial', axial_exists, w_axial),
        ('coronal', coronal_exists, w_coronal),
        ('sagittal', sagittal_exists, w_sagittal)
    ]:
        if exists_flag:
            # Try to verify screenshot is valid (not empty)
            try:
                temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                copy_from_env(f"/tmp/agent_outputs/{name}.png", temp_img.name)
                img_size = os.path.getsize(temp_img.name)
                os.unlink(temp_img.name)
                
                if img_size > 10000:  # At least 10KB
                    score += weight
                    feedback_parts.append(f"✓ {name.capitalize()} screenshot captured ({img_size // 1024}KB)")
                    screenshot_checks.append((name, True))
                else:
                    score += weight // 2
                    feedback_parts.append(f"△ {name.capitalize()} screenshot small ({img_size} bytes)")
                    screenshot_checks.append((name, False))
            except Exception:
                score += weight // 2
                feedback_parts.append(f"△ {name.capitalize()} screenshot exists (unverified)")
                screenshot_checks.append((name, True))
        else:
            feedback_parts.append(f"✗ {name.capitalize()} screenshot not found")
            screenshot_checks.append((name, False))
    
    details['screenshots'] = {name: ok for name, ok in screenshot_checks}
    
    # ============================================================
    # CRITERION 4: LATERALITY CORRECT (10 points)
    # ============================================================
    reported_laterality = result.get('reported_laterality', '').lower().strip()
    
    if reported_laterality and gt_laterality:
        if reported_laterality == gt_laterality.lower():
            score += w_laterality
            feedback_parts.append(f"✓ Laterality correct: {gt_laterality}")
        else:
            feedback_parts.append(f"✗ Laterality incorrect: reported '{reported_laterality}', expected '{gt_laterality}'")
        details['reported_laterality'] = reported_laterality
    elif has_valid_coords:
        # Infer laterality from coordinates
        inferred_lat = "right" if agent_R > 5 else ("left" if agent_R < -5 else "midline")
        if inferred_lat == gt_laterality.lower():
            score += w_laterality // 2
            feedback_parts.append(f"△ Laterality inferred correctly from coordinates: {inferred_lat}")
    else:
        feedback_parts.append("✗ Laterality not reported")
    
    # ============================================================
    # CRITERION 5: MIDLINE DISTANCE (10 points)
    # ============================================================
    reported_midline_str = result.get('reported_midline_mm', '')
    reported_midline = parse_coordinate(reported_midline_str)
    
    if reported_midline is not None and gt_midline:
        midline_error = abs(reported_midline - gt_midline)
        details['reported_midline_mm'] = reported_midline
        details['midline_error_mm'] = round(midline_error, 2)
        
        if midline_error <= midline_tolerance:
            score += w_midline
            feedback_parts.append(f"✓ Midline distance: {reported_midline:.1f}mm (error: {midline_error:.1f}mm)")
        elif midline_error <= midline_tolerance * 2:
            score += w_midline // 2
            feedback_parts.append(f"△ Midline distance: {reported_midline:.1f}mm (error: {midline_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Midline distance incorrect: {reported_midline:.1f}mm (expected ~{gt_midline:.1f}mm)")
    elif has_valid_coords:
        # Calculate from coordinates
        inferred_midline = abs(agent_R) if agent_R is not None else 0
        midline_error = abs(inferred_midline - gt_midline)
        if midline_error <= midline_tolerance:
            score += w_midline // 2
            feedback_parts.append(f"△ Midline distance inferred from R coordinate: {inferred_midline:.1f}mm")
    else:
        feedback_parts.append("✗ Midline distance not reported")
    
    # ============================================================
    # CRITERION 6: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        # Check for required fields
        has_centroid = has_valid_coords or (reported_coords.get('R') is not None)
        has_lat = bool(reported_laterality)
        has_midline = reported_midline is not None
        
        fields_present = sum([has_centroid, has_lat, has_midline])
        
        if fields_present >= 3:
            score += w_report
            feedback_parts.append("✓ Report complete with all required fields")
        elif fields_present >= 2:
            score += int(w_report * 0.7)
            feedback_parts.append(f"△ Report partially complete ({fields_present}/3 fields)")
        else:
            score += int(w_report * 0.3)
            feedback_parts.append(f"△ Report incomplete ({fields_present}/3 fields)")
        
        details['report_fields'] = {
            'has_centroid': has_centroid,
            'has_laterality': has_lat,
            'has_midline': has_midline
        }
    else:
        feedback_parts.append("✗ Localization report not found")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Key criteria: centroid accuracy is required for passing
    key_criteria_met = centroid_accurate
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED ({score}/100): {feedback}"
    else:
        if not key_criteria_met and score >= 60:
            feedback = f"FAILED (centroid not accurate): {feedback}"
        else:
            feedback = f"FAILED ({score}/100): {feedback}"
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details,
        "subscores": {
            "centroid_accuracy": w_centroid if centroid_accurate else 0,
            "fiducial_placed": w_fiducial if fiducial_exists and has_valid_coords else 0,
            "axial_screenshot": w_axial if axial_exists else 0,
            "coronal_screenshot": w_coronal if coronal_exists else 0,
            "sagittal_screenshot": w_sagittal if sagittal_exists else 0,
            "laterality_correct": w_laterality if reported_laterality == gt_laterality.lower() else 0,
            "midline_distance": details.get('midline_error_mm', float('inf')) <= midline_tolerance,
            "report_complete": report_exists
        }
    })