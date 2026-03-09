#!/usr/bin/env python3
"""
Verifier for tumor principal axis analysis task.

VERIFICATION METRICS:
1. Centroid accuracy - distance from agent's centroid to ground truth
2. Principal axis measurements - comparison of major, intermediate, minor axes
3. Volume calculation - ellipsoid approximation correctness
4. Shape classification - correct classification based on ratios
5. Report completeness - all required fields present

Ground Truth: Computed from BraTS segmentation using PCA analysis
"""

import json
import os
import sys
import tempfile
import logging
import math
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    if isinstance(val, (np.integer, np.int32, np.int64)):
        return int(val)
    elif isinstance(val, (np.floating, np.float32, np.float64)):
        return float(val)
    elif isinstance(val, np.ndarray):
        return val.tolist()
    elif isinstance(val, np.bool_):
        return bool(val)
    elif isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def parse_centroid_from_markup(markup_data):
    """
    Extract centroid position from Slicer markup JSON format.
    
    Returns (R, A, S) coordinates or None if not found.
    """
    if not markup_data:
        return None
    
    # Slicer markup format
    if 'markups' in markup_data:
        for markup in markup_data['markups']:
            if 'controlPoints' in markup:
                for cp in markup['controlPoints']:
                    pos = cp.get('position', None)
                    if pos and len(pos) >= 3:
                        return [float(pos[0]), float(pos[1]), float(pos[2])]
    
    # Direct centroid_ras field
    if 'centroid_ras' in markup_data:
        pos = markup_data['centroid_ras']
        if pos and len(pos) >= 3:
            return [float(pos[0]), float(pos[1]), float(pos[2])]
    
    # Try position field directly
    if 'position' in markup_data:
        pos = markup_data['position']
        if pos and len(pos) >= 3:
            return [float(pos[0]), float(pos[1]), float(pos[2])]
    
    return None


def extract_measurements_from_summary(summary_data):
    """
    Extract measurements from Slicer markup summary.
    
    Returns dict with major/intermediate/minor axis lengths if available.
    """
    result = {}
    
    if not summary_data:
        return result
    
    measurements = summary_data.get('measurements', [])
    
    # Sort by length descending to identify major/intermediate/minor
    lengths = []
    for m in measurements:
        length = m.get('length_mm', 0)
        if length > 0:
            lengths.append(length)
    
    if lengths:
        lengths.sort(reverse=True)
        if len(lengths) >= 1:
            result['major_axis_mm'] = lengths[0]
        if len(lengths) >= 2:
            result['intermediate_axis_mm'] = lengths[1]
        if len(lengths) >= 3:
            result['minor_axis_mm'] = lengths[2]
    
    # Also try to extract centroid from summary
    centroid_info = summary_data.get('centroid', {})
    if centroid_info and 'centroid_ras' in centroid_info:
        result['centroid_ras'] = centroid_info['centroid_ras']
    
    return result


def calculate_ellipsoid_volume(a, b, c):
    """Calculate ellipsoid volume from semi-axes (diameters/2)."""
    return (4.0/3.0) * math.pi * (a/2) * (b/2) * (c/2) / 1000.0  # Convert to mL


def determine_shape_classification(elongation, flatness):
    """Determine shape classification from ratios."""
    max_ratio = max(elongation, flatness)
    if max_ratio < 1.5:
        return "Spherical"
    elif max_ratio <= 2.5:
        return "Ellipsoidal"
    else:
        return "Elongated"


def verify_tumor_principal_axis(traj, env_info, task_info):
    """
    Verify tumor principal axis analysis task.
    
    Scoring (100 points total):
    - Centroid accuracy: 30 points (within 10mm)
    - Major axis: 15 points (within 20% or 5mm)
    - Intermediate axis: 10 points
    - Minor axis: 10 points
    - Volume calculation: 10 points
    - Shape classification: 10 points
    - Report completeness: 10 points
    - Centroid file exists: 5 points
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
    
    centroid_error_max = thresholds.get('centroid_error_max_mm', 10.0)
    axis_error_percent = thresholds.get('axis_error_max_percent', 20.0)
    axis_error_mm = thresholds.get('axis_error_max_mm', 5.0)
    
    w_centroid = weights.get('centroid_accuracy', 30)
    w_major = weights.get('major_axis', 15)
    w_intermediate = weights.get('intermediate_axis', 10)
    w_minor = weights.get('minor_axis', 10)
    w_volume = weights.get('volume_calculation', 10)
    w_classification = weights.get('shape_classification', 10)
    w_report = weights.get('report_completeness', 10)
    w_file = weights.get('centroid_file_exists', 5)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # LOAD TASK RESULT
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/principal_axis_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/gt_geometry.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_centroid = gt_data.get('centroid_ras', [0, 0, 0])
    gt_major = gt_data.get('major_axis_mm', 0)
    gt_intermediate = gt_data.get('intermediate_axis_mm', 0)
    gt_minor = gt_data.get('minor_axis_mm', 0)
    gt_classification = gt_data.get('shape_classification', '')
    gt_volume = gt_data.get('ellipsoid_volume_ml', 0)
    
    details['gt_centroid_ras'] = gt_centroid
    details['gt_major_axis_mm'] = gt_major
    details['gt_intermediate_axis_mm'] = gt_intermediate
    details['gt_minor_axis_mm'] = gt_minor
    details['gt_classification'] = gt_classification
    details['gt_ellipsoid_volume_ml'] = gt_volume
    
    # ================================================================
    # LOAD AGENT OUTPUTS
    # ================================================================
    
    # Try to load centroid markup
    agent_centroid = None
    temp_centroid = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_centroid.json", temp_centroid.name)
        with open(temp_centroid.name, 'r') as f:
            centroid_data = json.load(f)
        agent_centroid = parse_centroid_from_markup(centroid_data)
    except Exception as e:
        logger.debug(f"Could not load centroid markup: {e}")
    finally:
        if os.path.exists(temp_centroid.name):
            os.unlink(temp_centroid.name)
    
    # Try to load agent report
    agent_report = {}
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
    except Exception as e:
        logger.debug(f"Could not load agent report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # Try to load Slicer markup summary
    slicer_summary = {}
    temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_slicer_summary.json", temp_summary.name)
        with open(temp_summary.name, 'r') as f:
            slicer_summary = json.load(f)
    except Exception as e:
        logger.debug(f"Could not load Slicer summary: {e}")
    finally:
        if os.path.exists(temp_summary.name):
            os.unlink(temp_summary.name)
    
    # Extract measurements from various sources
    summary_measurements = extract_measurements_from_summary(slicer_summary)
    
    # Combine data sources - prefer agent report, fall back to Slicer summary
    if not agent_centroid and 'centroid_ras' in summary_measurements:
        agent_centroid = summary_measurements['centroid_ras']
    if not agent_centroid and 'centroid_ras' in agent_report:
        agent_centroid = agent_report['centroid_ras']
    
    # ================================================================
    # CRITERION 1: CENTROID FILE EXISTS (5 points)
    # ================================================================
    centroid_file_exists = result.get('centroid_file_exists', False)
    centroid_created_during_task = result.get('centroid_created_during_task', False)
    
    if centroid_file_exists and centroid_created_during_task:
        score += w_file
        feedback_parts.append(f"Centroid file created (+{w_file})")
    elif centroid_file_exists:
        score += w_file // 2
        feedback_parts.append(f"Centroid file exists but may not be new (+{w_file // 2})")
    else:
        feedback_parts.append("Centroid file not found")
    
    details['centroid_file_exists'] = centroid_file_exists
    details['centroid_created_during_task'] = centroid_created_during_task
    
    # ================================================================
    # CRITERION 2: CENTROID ACCURACY (30 points)
    # ================================================================
    centroid_error = float('inf')
    
    if agent_centroid and len(agent_centroid) >= 3:
        try:
            agent_c = np.array([float(x) for x in agent_centroid[:3]])
            gt_c = np.array([float(x) for x in gt_centroid[:3]])
            centroid_error = float(np.linalg.norm(agent_c - gt_c))
            
            details['agent_centroid_ras'] = agent_c.tolist()
            details['centroid_error_mm'] = centroid_error
            
            if centroid_error <= centroid_error_max:
                score += w_centroid
                feedback_parts.append(f"Centroid accurate: {centroid_error:.1f}mm (+{w_centroid})")
            elif centroid_error <= centroid_error_max * 2:
                partial = w_centroid // 2
                score += partial
                feedback_parts.append(f"Centroid partially accurate: {centroid_error:.1f}mm (+{partial})")
            else:
                feedback_parts.append(f"Centroid inaccurate: {centroid_error:.1f}mm (>{centroid_error_max}mm)")
        except Exception as e:
            feedback_parts.append(f"Could not parse centroid: {e}")
    else:
        # Try parsing from result string
        centroid_str = result.get('centroid_ras_str', '')
        if centroid_str:
            try:
                coords = [float(x) for x in centroid_str.split(',')]
                if len(coords) >= 3:
                    agent_c = np.array(coords[:3])
                    gt_c = np.array([float(x) for x in gt_centroid[:3]])
                    centroid_error = float(np.linalg.norm(agent_c - gt_c))
                    
                    details['agent_centroid_ras'] = coords[:3]
                    details['centroid_error_mm'] = centroid_error
                    
                    if centroid_error <= centroid_error_max:
                        score += w_centroid
                        feedback_parts.append(f"Centroid accurate: {centroid_error:.1f}mm (+{w_centroid})")
                    elif centroid_error <= centroid_error_max * 2:
                        partial = w_centroid // 2
                        score += partial
                        feedback_parts.append(f"Centroid partially accurate: {centroid_error:.1f}mm (+{partial})")
            except:
                pass
        
        if centroid_error == float('inf'):
            feedback_parts.append("No centroid placement found")
    
    # ================================================================
    # CRITERION 3-5: AXIS MEASUREMENTS (35 points total)
    # ================================================================
    
    # Get agent's axis measurements
    agent_major = agent_report.get('major_axis_mm', summary_measurements.get('major_axis_mm', 0))
    agent_intermediate = agent_report.get('intermediate_axis_mm', summary_measurements.get('intermediate_axis_mm', 0))
    agent_minor = agent_report.get('minor_axis_mm', summary_measurements.get('minor_axis_mm', 0))
    
    details['agent_major_axis_mm'] = agent_major
    details['agent_intermediate_axis_mm'] = agent_intermediate
    details['agent_minor_axis_mm'] = agent_minor
    
    def check_axis(agent_val, gt_val, axis_name, points):
        """Check if axis measurement is within tolerance."""
        nonlocal score
        if agent_val > 0 and gt_val > 0:
            error_abs = abs(agent_val - gt_val)
            error_pct = (error_abs / gt_val) * 100 if gt_val > 0 else 100
            
            if error_abs <= axis_error_mm or error_pct <= axis_error_percent:
                score += points
                feedback_parts.append(f"{axis_name}: {agent_val:.1f}mm (error: {error_abs:.1f}mm) (+{points})")
                return True
            elif error_abs <= axis_error_mm * 2 or error_pct <= axis_error_percent * 2:
                partial = points // 2
                score += partial
                feedback_parts.append(f"{axis_name}: {agent_val:.1f}mm (error: {error_abs:.1f}mm) (+{partial})")
                return False
            else:
                feedback_parts.append(f"{axis_name}: {agent_val:.1f}mm (error: {error_abs:.1f}mm, too large)")
                return False
        elif agent_val > 0:
            feedback_parts.append(f"{axis_name}: {agent_val:.1f}mm (no GT for comparison)")
            return False
        else:
            feedback_parts.append(f"{axis_name}: not measured")
            return False
    
    check_axis(agent_major, gt_major, "Major axis", w_major)
    check_axis(agent_intermediate, gt_intermediate, "Intermediate axis", w_intermediate)
    check_axis(agent_minor, gt_minor, "Minor axis", w_minor)
    
    # ================================================================
    # CRITERION 6: VOLUME CALCULATION (10 points)
    # ================================================================
    agent_volume = agent_report.get('ellipsoid_volume_ml', 0)
    
    # If not in report, calculate from axes
    if agent_volume == 0 and agent_major > 0 and agent_intermediate > 0 and agent_minor > 0:
        agent_volume = calculate_ellipsoid_volume(agent_major, agent_intermediate, agent_minor)
    
    details['agent_ellipsoid_volume_ml'] = agent_volume
    
    if agent_volume > 0 and gt_volume > 0:
        volume_error_pct = abs(agent_volume - gt_volume) / gt_volume * 100 if gt_volume > 0 else 100
        
        if volume_error_pct <= 30:
            score += w_volume
            feedback_parts.append(f"Volume: {agent_volume:.1f}mL (error: {volume_error_pct:.0f}%) (+{w_volume})")
        elif volume_error_pct <= 50:
            partial = w_volume // 2
            score += partial
            feedback_parts.append(f"Volume: {agent_volume:.1f}mL (error: {volume_error_pct:.0f}%) (+{partial})")
        else:
            feedback_parts.append(f"Volume: {agent_volume:.1f}mL (error: {volume_error_pct:.0f}%, too large)")
    else:
        feedback_parts.append("Volume not calculated")
    
    # ================================================================
    # CRITERION 7: SHAPE CLASSIFICATION (10 points)
    # ================================================================
    agent_classification = agent_report.get('shape_classification', '')
    
    # If not in report, calculate from axes
    if not agent_classification and agent_major > 0 and agent_intermediate > 0 and agent_minor > 0:
        elongation = agent_major / agent_intermediate if agent_intermediate > 0 else 1
        flatness = agent_intermediate / agent_minor if agent_minor > 0 else 1
        agent_classification = determine_shape_classification(elongation, flatness)
    
    details['agent_classification'] = agent_classification
    
    if agent_classification and gt_classification:
        if agent_classification.lower() == gt_classification.lower():
            score += w_classification
            feedback_parts.append(f"Classification: {agent_classification} (correct) (+{w_classification})")
        else:
            feedback_parts.append(f"Classification: {agent_classification} (expected: {gt_classification})")
    else:
        feedback_parts.append("Classification not provided")
    
    # ================================================================
    # CRITERION 8: REPORT COMPLETENESS (10 points)
    # ================================================================
    report_exists = result.get('report_file_exists', False)
    report_created_during_task = result.get('report_created_during_task', False)
    
    required_fields = ['centroid_ras', 'major_axis_mm', 'intermediate_axis_mm', 'minor_axis_mm',
                       'ellipsoid_volume_ml', 'elongation_ratio', 'flatness_ratio', 'shape_classification']
    
    fields_present = sum(1 for f in required_fields if f in agent_report and agent_report[f])
    
    details['report_exists'] = report_exists
    details['report_fields_present'] = fields_present
    details['report_fields_required'] = len(required_fields)
    
    if report_exists and report_created_during_task:
        if fields_present >= len(required_fields) - 1:  # Allow 1 missing field
            score += w_report
            feedback_parts.append(f"Report complete ({fields_present}/{len(required_fields)} fields) (+{w_report})")
        elif fields_present >= len(required_fields) // 2:
            partial = w_report // 2
            score += partial
            feedback_parts.append(f"Report partial ({fields_present}/{len(required_fields)} fields) (+{partial})")
        else:
            feedback_parts.append(f"Report incomplete ({fields_present}/{len(required_fields)} fields)")
    elif report_exists:
        partial = w_report // 3
        score += partial
        feedback_parts.append(f"Report exists but may not be new (+{partial})")
    else:
        feedback_parts.append("Report file not found")
    
    # ================================================================
    # FINAL RESULT
    # ================================================================
    
    # Key criteria for passing: centroid placed with reasonable accuracy
    key_criteria_met = (
        centroid_file_exists and
        centroid_error <= centroid_error_max * 2  # Within 2x threshold
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Convert any numpy types in details
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }