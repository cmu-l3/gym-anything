#!/usr/bin/env python3
"""
Verifier for hippocampal volume asymmetry assessment task.

VERIFICATION CRITERIA:
1. Left hippocampus segment present (15 points)
2. Right hippocampus segment present (15 points)
3. Left segment in correct anatomical location (10 points)
4. Right segment in correct anatomical location (10 points)
5. Volume plausibility (both within 1.5-6.0 mL) (10 points)
6. No midline crossover (segments stay in correct hemispheres) (10 points)
7. Asymmetry index calculated correctly (10 points)
8. Classification matches HAI thresholds (10 points)
9. Report complete with all required fields (10 points)

Pass threshold: 60 points with both hippocampi present
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


def calculate_hai(left_vol: float, right_vol: float) -> float:
    """Calculate Hippocampal Asymmetry Index."""
    if left_vol <= 0 or right_vol <= 0:
        return 0.0
    mean_vol = (left_vol + right_vol) / 2.0
    if mean_vol == 0:
        return 0.0
    return abs(left_vol - right_vol) / mean_vol * 100.0


def classify_hai(hai: float) -> str:
    """Classify HAI according to clinical thresholds."""
    if hai < 10:
        return "Normal"
    elif hai < 15:
        return "Borderline"
    else:
        return "Significant"


def check_anatomical_location(rel_x: float, rel_y: float, rel_z: float, side: str) -> tuple:
    """
    Check if segment centroid is in expected anatomical location.
    
    Hippocampus expected location:
    - Left: x in [0.2, 0.45] (left side of image)
    - Right: x in [0.55, 0.8] (right side of image)
    - Y (A-P): [0.35, 0.65] (mid brain)
    - Z (S-I): [0.25, 0.50] (inferior portion)
    
    Returns: (is_correct, feedback)
    """
    bounds = {
        'left': {'x': (0.15, 0.50), 'y': (0.25, 0.75), 'z': (0.20, 0.60)},
        'right': {'x': (0.50, 0.85), 'y': (0.25, 0.75), 'z': (0.20, 0.60)}
    }
    
    if side not in bounds:
        return False, f"Unknown side: {side}"
    
    b = bounds[side]
    issues = []
    
    # Check x (left-right)
    if not (b['x'][0] <= rel_x <= b['x'][1]):
        issues.append(f"x={rel_x:.2f} outside [{b['x'][0]:.2f}, {b['x'][1]:.2f}]")
    
    # Check y (anterior-posterior) - more lenient
    if not (b['y'][0] <= rel_y <= b['y'][1]):
        issues.append(f"y={rel_y:.2f} outside [{b['y'][0]:.2f}, {b['y'][1]:.2f}]")
    
    # Check z (superior-inferior) - more lenient
    if not (b['z'][0] <= rel_z <= b['z'][1]):
        issues.append(f"z={rel_z:.2f} outside [{b['z'][0]:.2f}, {b['z'][1]:.2f}]")
    
    if issues:
        return False, "; ".join(issues)
    return True, "Location OK"


def verify_hippocampal_asymmetry(traj, env_info, task_info):
    """
    Verify hippocampal volume asymmetry assessment task.
    
    Scoring (100 points total):
    - Left segment present: 15 points
    - Right segment present: 15 points
    - Left location correct: 10 points
    - Right location correct: 10 points
    - Volume plausibility: 10 points
    - No midline crossover: 10 points
    - Asymmetry calculated: 10 points
    - Classification correct: 10 points
    - Report complete: 10 points
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
    
    w_left_present = weights.get('left_segment_present', 15)
    w_right_present = weights.get('right_segment_present', 15)
    w_left_location = weights.get('left_location_correct', 10)
    w_right_location = weights.get('right_location_correct', 10)
    w_volume_plausible = weights.get('volume_plausibility', 10)
    w_no_crossover = weights.get('no_midline_crossover', 10)
    w_hai_calc = weights.get('asymmetry_calculated', 10)
    w_classification = weights.get('classification_correct', 10)
    w_report = weights.get('report_complete', 10)
    
    anatomical = metadata.get('anatomical_bounds', {})
    vol_min = anatomical.get('volume_min_ml', 1.5)
    vol_max = anatomical.get('volume_max_ml', 6.0)
    ratio_min = anatomical.get('volume_ratio_min', 0.5)
    ratio_max = anatomical.get('volume_ratio_max', 2.0)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/hippocampal_task_result.json", temp_result.name)
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
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    if not result.get('segmentation_exists', False):
        feedback_parts.append("No segmentation file created")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "Segmentation not found",
            "details": to_python_type(details)
        }
    
    # Anti-gaming: Check if segmentation was created during task
    if not result.get('segmentation_created_during_task', False):
        feedback_parts.append("WARNING: Segmentation may not have been created during task")
    
    # Parse segmentation analysis
    seg_analysis = result.get('segmentation_analysis', {})
    if isinstance(seg_analysis, str):
        try:
            seg_analysis = json.loads(seg_analysis)
        except:
            seg_analysis = {}
    
    segments = seg_analysis.get('segments', [])
    details['num_segments'] = len(segments)
    
    # Identify left and right segments
    left_seg = None
    right_seg = None
    
    for seg in segments:
        side = seg.get('side', '')
        if side == 'left' and left_seg is None:
            left_seg = seg
        elif side == 'right' and right_seg is None:
            right_seg = seg
    
    # ================================================================
    # CRITERION 1 & 2: Segments present (15 + 15 points)
    # ================================================================
    left_present = left_seg is not None
    right_present = right_seg is not None
    
    if left_present:
        score += w_left_present
        feedback_parts.append("✓ Left hippocampus segment found")
        details['left_segment'] = left_seg
    else:
        feedback_parts.append("✗ Left hippocampus segment NOT found")
    
    if right_present:
        score += w_right_present
        feedback_parts.append("✓ Right hippocampus segment found")
        details['right_segment'] = right_seg
    else:
        feedback_parts.append("✗ Right hippocampus segment NOT found")
    
    # Early exit if neither segment found
    if not left_present and not right_present:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    # ================================================================
    # CRITERION 3 & 4: Anatomical location (10 + 10 points)
    # ================================================================
    if left_present:
        rel_pos = left_seg.get('relative_position', {})
        rel_x = rel_pos.get('x', 0.5)
        rel_y = rel_pos.get('y', 0.5)
        rel_z = rel_pos.get('z', 0.5)
        
        loc_ok, loc_feedback = check_anatomical_location(rel_x, rel_y, rel_z, 'left')
        if loc_ok:
            score += w_left_location
            feedback_parts.append("✓ Left segment in correct location")
        else:
            feedback_parts.append(f"✗ Left segment location issue: {loc_feedback}")
        details['left_location_check'] = {'ok': loc_ok, 'feedback': loc_feedback}
    
    if right_present:
        rel_pos = right_seg.get('relative_position', {})
        rel_x = rel_pos.get('x', 0.5)
        rel_y = rel_pos.get('y', 0.5)
        rel_z = rel_pos.get('z', 0.5)
        
        loc_ok, loc_feedback = check_anatomical_location(rel_x, rel_y, rel_z, 'right')
        if loc_ok:
            score += w_right_location
            feedback_parts.append("✓ Right segment in correct location")
        else:
            feedback_parts.append(f"✗ Right segment location issue: {loc_feedback}")
        details['right_location_check'] = {'ok': loc_ok, 'feedback': loc_feedback}
    
    # ================================================================
    # CRITERION 5: Volume plausibility (10 points)
    # ================================================================
    left_vol = left_seg.get('volume_ml', 0) if left_seg else 0
    right_vol = right_seg.get('volume_ml', 0) if right_seg else 0
    
    details['left_volume_ml'] = left_vol
    details['right_volume_ml'] = right_vol
    
    vol_issues = []
    if left_present:
        if not (vol_min <= left_vol <= vol_max):
            vol_issues.append(f"Left vol {left_vol:.2f} mL outside [{vol_min}, {vol_max}]")
    if right_present:
        if not (vol_min <= right_vol <= vol_max):
            vol_issues.append(f"Right vol {right_vol:.2f} mL outside [{vol_min}, {vol_max}]")
    
    if left_present and right_present and left_vol > 0 and right_vol > 0:
        ratio = left_vol / right_vol
        if not (ratio_min <= ratio <= ratio_max):
            vol_issues.append(f"L/R ratio {ratio:.2f} outside [{ratio_min}, {ratio_max}]")
    
    if not vol_issues:
        score += w_volume_plausible
        feedback_parts.append(f"✓ Volumes plausible (L={left_vol:.2f}, R={right_vol:.2f} mL)")
    else:
        feedback_parts.append(f"✗ Volume issues: {'; '.join(vol_issues)}")
    details['volume_issues'] = vol_issues
    
    # ================================================================
    # CRITERION 6: No midline crossover (10 points)
    # ================================================================
    crossover = False
    if left_present:
        rel_x = left_seg.get('relative_position', {}).get('x', 0)
        if rel_x > 0.55:  # Left segment crossing to right side
            crossover = True
            feedback_parts.append("✗ Left segment crosses midline")
    if right_present:
        rel_x = right_seg.get('relative_position', {}).get('x', 1)
        if rel_x < 0.45:  # Right segment crossing to left side
            crossover = True
            feedback_parts.append("✗ Right segment crosses midline")
    
    if not crossover:
        score += w_no_crossover
        feedback_parts.append("✓ No midline crossover")
    details['midline_crossover'] = crossover
    
    # ================================================================
    # CRITERION 7: Asymmetry index calculated (10 points)
    # ================================================================
    reported_hai_str = result.get('reported_hai_percent', '')
    reported_hai = None
    if reported_hai_str:
        try:
            reported_hai = float(reported_hai_str)
        except:
            pass
    
    # Calculate expected HAI from segment volumes
    if left_vol > 0 and right_vol > 0:
        expected_hai = calculate_hai(left_vol, right_vol)
        details['expected_hai'] = expected_hai
        
        if reported_hai is not None:
            hai_error = abs(reported_hai - expected_hai)
            if hai_error < 5.0:  # Within 5% tolerance
                score += w_hai_calc
                feedback_parts.append(f"✓ HAI calculated correctly ({reported_hai:.1f}%)")
            else:
                feedback_parts.append(f"✗ HAI error: reported {reported_hai:.1f}%, expected {expected_hai:.1f}%")
            details['reported_hai'] = reported_hai
            details['hai_error'] = hai_error
        else:
            feedback_parts.append("✗ HAI not reported")
    else:
        feedback_parts.append("Cannot verify HAI - missing volumes")
    
    # ================================================================
    # CRITERION 8: Classification correct (10 points)
    # ================================================================
    reported_class = result.get('reported_classification', '').strip().lower()
    
    if left_vol > 0 and right_vol > 0:
        hai_for_class = reported_hai if reported_hai is not None else calculate_hai(left_vol, right_vol)
        expected_class = classify_hai(hai_for_class).lower()
        details['expected_classification'] = expected_class
        
        if reported_class:
            if reported_class == expected_class or reported_class in expected_class or expected_class in reported_class:
                score += w_classification
                feedback_parts.append(f"✓ Classification correct ({expected_class.title()})")
            else:
                feedback_parts.append(f"✗ Classification mismatch: reported '{reported_class}', expected '{expected_class}'")
            details['reported_classification'] = reported_class
        else:
            feedback_parts.append("✗ Classification not reported")
    
    # ================================================================
    # CRITERION 9: Report completeness (10 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        required_fields = ['reported_left_volume_ml', 'reported_right_volume_ml', 
                          'reported_hai_percent', 'reported_classification']
        present_fields = sum(1 for f in required_fields if result.get(f))
        
        if present_fields >= 3:  # At least 3 of 4 fields
            score += w_report
            feedback_parts.append(f"✓ Report complete ({present_fields}/4 fields)")
        else:
            feedback_parts.append(f"✗ Report incomplete ({present_fields}/4 fields)")
        details['report_fields_present'] = present_fields
    else:
        feedback_parts.append("✗ No report file created")
    
    # ================================================================
    # Final determination
    # ================================================================
    key_criteria_met = left_present and right_present
    passed = score >= 60 and key_criteria_met
    
    details['score_breakdown'] = {
        'left_present': w_left_present if left_present else 0,
        'right_present': w_right_present if right_present else 0,
        'total': score
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }