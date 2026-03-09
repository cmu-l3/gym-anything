#!/usr/bin/env python3
"""
Verifier for Optic Nerve Sheath Diameter (ONSD) Measurement Task.

VERIFICATION METRICS:
1. Right ONSD Accuracy - measurement within tolerance of ground truth
2. Left ONSD Accuracy - measurement within tolerance of ground truth
3. Measurement Location - placed in anatomically plausible orbital region
4. Bilateral Symmetry - both sides measured with reasonable symmetry
5. Mean ONSD Calculation - correctly calculated from bilateral values
6. ICP Assessment - threshold logic correctly applied
7. Report Completeness - all required JSON fields present

Scoring (100 points total):
- Right ONSD accuracy: 20 points
- Left ONSD accuracy: 20 points
- Measurement location: 15 points
- Bilateral symmetry: 10 points
- Mean ONSD correct: 10 points
- ICP assessment: 15 points
- Report completeness: 10 points

Pass threshold: 60 points with at least one accurate measurement
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


def extract_onsd_from_markup(markup_data):
    """
    Extract ONSD measurement value and coordinates from markup data.
    
    Handles various possible markup structures from Slicer.
    
    Returns:
        Tuple of (onsd_mm, center_coords) or (None, None) if extraction fails
    """
    if not markup_data:
        return None, None
    
    onsd = None
    center = None
    
    try:
        # Direct value
        if 'onsd_mm' in markup_data:
            onsd = float(markup_data['onsd_mm'])
        
        # From measurement sub-object
        if onsd is None and 'measurement' in markup_data:
            m = markup_data['measurement']
            if 'length_mm' in m:
                onsd = float(m['length_mm'])
            if 'center' in m:
                center = m['center']
            elif 'p1' in m and 'p2' in m:
                p1, p2 = m['p1'], m['p2']
                center = [(a + b) / 2 for a, b in zip(p1, p2)]
        
        # From Slicer native markup format
        if onsd is None and 'markups' in markup_data:
            for m in markup_data['markups']:
                if 'controlPoints' in m and len(m['controlPoints']) >= 2:
                    p1 = m['controlPoints'][0].get('position', [0, 0, 0])
                    p2 = m['controlPoints'][1].get('position', [0, 0, 0])
                    onsd = math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))
                    center = [(a + b) / 2 for a, b in zip(p1, p2)]
                    break
        
        # From controlPoints directly
        if onsd is None and 'controlPoints' in markup_data:
            points = markup_data['controlPoints']
            if len(points) >= 2:
                p1 = points[0].get('position', [0, 0, 0])
                p2 = points[1].get('position', [0, 0, 0])
                onsd = math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))
                center = [(a + b) / 2 for a, b in zip(p1, p2)]
        
        # From measurements array
        if onsd is None and 'measurements' in markup_data:
            for m in markup_data['measurements']:
                if 'length_mm' in m and m['length_mm'] > 0:
                    onsd = float(m['length_mm'])
                    if 'center' in m:
                        center = m['center']
                    break
        
        return onsd, center
        
    except Exception as e:
        logger.warning(f"Error extracting ONSD from markup: {e}")
        return None, None


def verify_optic_nerve_sheath_diameter(traj, env_info, task_info):
    """
    Verify ONSD measurement task completion.
    
    Uses multi-criteria scoring with anti-gaming checks.
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
    
    # Tolerance and thresholds
    tolerance = thresholds.get('onsd_error_max_mm', 1.0)
    asymmetry_max = thresholds.get('asymmetry_max_mm', 1.5)
    min_onsd = thresholds.get('min_onsd_mm', 2.0)
    max_onsd = thresholds.get('max_onsd_mm', 10.0)
    icp_threshold = metadata.get('icp_threshold_mm', 5.0)
    
    # Scoring weights
    w_right = weights.get('right_accuracy', 20)
    w_left = weights.get('left_accuracy', 20)
    w_location = weights.get('measurement_location', 15)
    w_symmetry = weights.get('bilateral_symmetry', 10)
    w_mean = weights.get('mean_correct', 10)
    w_icp = weights.get('icp_assessment', 15)
    w_report = weights.get('report_completeness', 10)
    
    # Initialize result
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # LOAD TASK RESULT
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/onsd_task_result.json", temp_result.name)
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
    
    # Check Slicer was running
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
    gt = {}
    try:
        copy_from_env("/tmp/onsd_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_right = gt.get('right_onsd_mm', 4.5)
    gt_left = gt.get('left_onsd_mm', 4.4)
    gt_mean = gt.get('mean_onsd_mm', (gt_right + gt_left) / 2)
    gt_icp = gt.get('elevated_icp', gt_mean > icp_threshold)
    
    details['ground_truth'] = {
        'right_onsd_mm': gt_right,
        'left_onsd_mm': gt_left,
        'mean_onsd_mm': gt_mean,
        'elevated_icp': gt_icp
    }
    
    # ================================================================
    # LOAD AGENT MEASUREMENTS
    # ================================================================
    right_onsd = None
    right_coords = None
    left_onsd = None
    left_coords = None
    
    # Try to load right ONSD
    try:
        temp_right = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/agent_right_onsd.json", temp_right.name)
        with open(temp_right.name, 'r') as f:
            right_data = json.load(f)
        right_onsd, right_coords = extract_onsd_from_markup(right_data)
        os.unlink(temp_right.name)
    except Exception as e:
        logger.debug(f"Could not load right ONSD: {e}")
    
    # Try to load left ONSD
    try:
        temp_left = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/agent_left_onsd.json", temp_left.name)
        with open(temp_left.name, 'r') as f:
            left_data = json.load(f)
        left_onsd, left_coords = extract_onsd_from_markup(left_data)
        os.unlink(temp_left.name)
    except Exception as e:
        logger.debug(f"Could not load left ONSD: {e}")
    
    # Fallback to values from result JSON
    if right_onsd is None:
        right_info = result.get('right_onsd', {})
        if right_info.get('exists') and right_info.get('value_mm'):
            try:
                right_onsd = float(right_info['value_mm'])
            except (ValueError, TypeError):
                pass
    
    if left_onsd is None:
        left_info = result.get('left_onsd', {})
        if left_info.get('exists') and left_info.get('value_mm'):
            try:
                left_onsd = float(left_info['value_mm'])
            except (ValueError, TypeError):
                pass
    
    details['agent_measurements'] = {
        'right_onsd_mm': right_onsd,
        'right_coords': right_coords,
        'left_onsd_mm': left_onsd,
        'left_coords': left_coords
    }
    
    # ================================================================
    # LOAD AGENT REPORT
    # ================================================================
    report = {}
    try:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/agent_onsd_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report = json.load(f)
        os.unlink(temp_report.name)
    except Exception as e:
        logger.debug(f"Could not load report: {e}")
        # Try from result JSON
        report_info = result.get('report', {})
        if report_info.get('exists'):
            report = {
                'right_onsd_mm': report_info.get('right_onsd_mm'),
                'left_onsd_mm': report_info.get('left_onsd_mm'),
                'mean_onsd_mm': report_info.get('mean_onsd_mm'),
                'elevated_icp_suspected': report_info.get('elevated_icp_suspected')
            }
    
    details['agent_report'] = report
    
    # ================================================================
    # CRITERION 1: Right ONSD Accuracy (20 points)
    # ================================================================
    right_accurate = False
    if right_onsd is not None:
        # Check physiological plausibility
        if min_onsd <= right_onsd <= max_onsd:
            error = abs(right_onsd - gt_right)
            if error <= tolerance:
                score += w_right
                right_accurate = True
                feedback_parts.append(f"✓ Right ONSD: {right_onsd:.1f}mm (GT: {gt_right:.1f}mm, error: {error:.2f}mm)")
            else:
                # Partial credit for close measurements
                partial = max(0, w_right * (1 - error / 3))
                score += int(partial)
                feedback_parts.append(f"△ Right ONSD: {right_onsd:.1f}mm (GT: {gt_right:.1f}mm, error: {error:.2f}mm) - partial credit")
        else:
            feedback_parts.append(f"✗ Right ONSD: {right_onsd:.1f}mm - outside physiological range ({min_onsd}-{max_onsd}mm)")
    else:
        feedback_parts.append("✗ Right ONSD: No valid measurement found")
    
    # ================================================================
    # CRITERION 2: Left ONSD Accuracy (20 points)
    # ================================================================
    left_accurate = False
    if left_onsd is not None:
        if min_onsd <= left_onsd <= max_onsd:
            error = abs(left_onsd - gt_left)
            if error <= tolerance:
                score += w_left
                left_accurate = True
                feedback_parts.append(f"✓ Left ONSD: {left_onsd:.1f}mm (GT: {gt_left:.1f}mm, error: {error:.2f}mm)")
            else:
                partial = max(0, w_left * (1 - error / 3))
                score += int(partial)
                feedback_parts.append(f"△ Left ONSD: {left_onsd:.1f}mm (GT: {gt_left:.1f}mm, error: {error:.2f}mm) - partial credit")
        else:
            feedback_parts.append(f"✗ Left ONSD: {left_onsd:.1f}mm - outside physiological range ({min_onsd}-{max_onsd}mm)")
    else:
        feedback_parts.append("✗ Left ONSD: No valid measurement found")
    
    # ================================================================
    # CRITERION 3: Measurement Location (15 points)
    # ================================================================
    location_valid = False
    if right_onsd and left_onsd:
        # Check values are in physiological range
        if (min_onsd <= right_onsd <= max_onsd) and (min_onsd <= left_onsd <= max_onsd):
            # If we have coordinates, verify they're on opposite sides
            if right_coords and left_coords:
                # In RAS coordinates, positive X is patient right
                # Right orbit should have positive X, left should have negative
                right_x = right_coords[0] if len(right_coords) > 0 else 0
                left_x = left_coords[0] if len(left_coords) > 0 else 0
                
                # Check they're on opposite sides
                if (right_x > 0 and left_x < 0) or (right_x > left_x):
                    location_valid = True
                    score += w_location
                    feedback_parts.append("✓ Measurement location: Anatomically plausible (bilateral orbital region)")
                else:
                    # Still give partial credit if measurements exist
                    score += w_location // 2
                    feedback_parts.append("△ Measurement location: Coordinates may not be correctly lateralized")
            else:
                # No coordinates but values are reasonable
                location_valid = True
                score += w_location
                feedback_parts.append("✓ Measurement location: Values in physiological range")
    else:
        feedback_parts.append("✗ Measurement location: Cannot verify (missing measurements)")
    
    # ================================================================
    # CRITERION 4: Bilateral Symmetry (10 points)
    # ================================================================
    if right_onsd and left_onsd:
        asymmetry = abs(right_onsd - left_onsd)
        if asymmetry <= asymmetry_max:
            score += w_symmetry
            feedback_parts.append(f"✓ Bilateral symmetry: {asymmetry:.2f}mm difference (within normal)")
        else:
            # Unusual but not necessarily wrong
            score += w_symmetry // 2
            feedback_parts.append(f"△ Bilateral symmetry: {asymmetry:.2f}mm difference (>{asymmetry_max}mm)")
    else:
        feedback_parts.append("✗ Bilateral symmetry: Cannot assess (missing measurements)")
    
    # ================================================================
    # CRITERION 5: Mean ONSD Calculation (10 points)
    # ================================================================
    reported_mean = None
    if 'mean_onsd_mm' in report:
        try:
            reported_mean = float(report['mean_onsd_mm'])
        except (ValueError, TypeError):
            pass
    
    if reported_mean is not None and right_onsd and left_onsd:
        expected_mean = (right_onsd + left_onsd) / 2
        mean_error = abs(reported_mean - expected_mean)
        if mean_error <= 0.2:
            score += w_mean
            feedback_parts.append(f"✓ Mean ONSD: {reported_mean:.2f}mm (correctly calculated)")
        else:
            feedback_parts.append(f"△ Mean ONSD: {reported_mean:.2f}mm (expected {expected_mean:.2f}mm)")
    elif right_onsd and left_onsd:
        # Calculate mean from measurements even if not reported
        calculated_mean = (right_onsd + left_onsd) / 2
        score += w_mean // 2
        feedback_parts.append(f"△ Mean ONSD: Not reported (calculated: {calculated_mean:.2f}mm)")
    else:
        feedback_parts.append("✗ Mean ONSD: Cannot calculate (missing measurements)")
    
    # ================================================================
    # CRITERION 6: ICP Assessment (15 points)
    # ================================================================
    reported_icp = None
    if 'elevated_icp_suspected' in report:
        val = report['elevated_icp_suspected']
        if isinstance(val, bool):
            reported_icp = val
        elif isinstance(val, str):
            reported_icp = val.lower() in ['true', 'yes', '1']
    
    if reported_icp is not None:
        # Determine expected ICP status based on agent's measurements
        if right_onsd and left_onsd:
            agent_mean = (right_onsd + left_onsd) / 2
            expected_icp = agent_mean > icp_threshold
            
            if reported_icp == expected_icp:
                score += w_icp
                icp_str = "Elevated" if reported_icp else "Normal"
                feedback_parts.append(f"✓ ICP assessment: {icp_str} (consistent with {icp_threshold}mm threshold)")
            else:
                feedback_parts.append(f"✗ ICP assessment: Inconsistent with measurements (mean={agent_mean:.1f}mm, threshold={icp_threshold}mm)")
        else:
            # Check against ground truth if no measurements
            if reported_icp == gt_icp:
                score += w_icp
                feedback_parts.append("✓ ICP assessment: Correct (matches ground truth)")
            else:
                feedback_parts.append("✗ ICP assessment: Incorrect")
    else:
        feedback_parts.append("✗ ICP assessment: Not reported")
    
    # ================================================================
    # CRITERION 7: Report Completeness (10 points)
    # ================================================================
    required_fields = [
        'right_onsd_mm',
        'left_onsd_mm', 
        'mean_onsd_mm',
        'elevated_icp_suspected',
        'clinical_assessment'
    ]
    
    if report:
        fields_present = sum(1 for f in required_fields if f in report and report[f] is not None)
        completeness_score = int(w_report * fields_present / len(required_fields))
        score += completeness_score
        feedback_parts.append(f"{'✓' if fields_present == len(required_fields) else '△'} Report completeness: {fields_present}/{len(required_fields)} fields present")
    else:
        feedback_parts.append("✗ Report completeness: No report found")
    
    # ================================================================
    # ANTI-GAMING CHECKS
    # ================================================================
    right_info = result.get('right_onsd', {})
    left_info = result.get('left_onsd', {})
    
    # Check timestamps
    if right_info.get('exists') and not right_info.get('created_during_task', True):
        feedback_parts.append("⚠ Warning: Right measurement may have existed before task")
    if left_info.get('exists') and not left_info.get('created_during_task', True):
        feedback_parts.append("⚠ Warning: Left measurement may have existed before task")
    
    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    has_accurate_measurement = right_accurate or left_accurate
    passed = (score >= 60) and has_accurate_measurement
    
    # Summary
    feedback_parts.append("")
    feedback_parts.append(f"Final Score: {score}/100")
    feedback_parts.append(f"Passed: {passed}")
    if passed:
        feedback_parts.append("Task completed successfully!")
    else:
        if score < 60:
            feedback_parts.append("Score below 60% threshold")
        if not has_accurate_measurement:
            feedback_parts.append("No accurate ONSD measurement achieved")
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": " | ".join([p for p in feedback_parts if p]),
        "details": details
    })


if __name__ == "__main__":
    # Test verification with mock data
    import sys
    
    # Create mock trajectory and env_info
    mock_traj = {"frames": [], "steps": []}
    mock_env_info = {"copy_from_env": None}
    mock_task_info = {"metadata": {}}
    
    result = verify_optic_nerve_sheath_diameter(mock_traj, mock_env_info, mock_task_info)
    print(json.dumps(result, indent=2))