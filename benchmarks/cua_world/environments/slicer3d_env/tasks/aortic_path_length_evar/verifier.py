#!/usr/bin/env python3
"""
Verifier for Aortic Path Length EVAR Planning task.

VERIFICATION METRICS:
1. Path length accuracy - curve length vs ground truth centerline
2. Straight length accuracy - endpoint distance measurement
3. Tortuosity ratio - path/straight calculation
4. Endpoint locations - curve spans appropriate anatomical range
5. Curve quality - sufficient control points, proper placement
6. Report completeness - all required fields present

Scoring (100 points total):
- Path length accuracy: 30 points (within 15mm)
- Straight length accuracy: 15 points (within 10mm)
- Tortuosity ratio: 10 points (within 0.03)
- Superior endpoint: 10 points (reasonable z-level)
- Inferior endpoint: 10 points (reasonable z-level)
- Centerline fidelity: 10 points (curve spans adequate range)
- Sufficient points: 5 points (>= 8 control points)
- Report completeness: 10 points (all required fields)
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


def load_json_file(filepath):
    """Load and parse a JSON file."""
    if not os.path.exists(filepath):
        return None, f"File not found: {filepath}"
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
        return data, None
    except json.JSONDecodeError as e:
        return None, f"Invalid JSON: {e}"
    except Exception as e:
        return None, f"Error reading file: {e}"


def extract_curve_info(curve_data):
    """Extract curve length and control points from Slicer markup JSON."""
    try:
        markups = curve_data.get("markups", [])
        if not markups:
            return 0.0, 0, [], "No markups found"
        
        markup = markups[0]
        
        # Get control points
        control_points = markup.get("controlPoints", [])
        num_points = len(control_points)
        
        # Extract point positions
        positions = []
        for cp in control_points:
            pos = cp.get("position", [0, 0, 0])
            positions.append(pos)
        
        # Get curve length from measurements
        curve_length = 0.0
        measurements = markup.get("measurements", [])
        for m in measurements:
            name = m.get("name", "").lower()
            if "length" in name or "curve" in name:
                curve_length = float(m.get("value", 0))
                break
        
        # If no length measurement, compute from points
        if curve_length == 0 and len(positions) >= 2:
            total = 0
            for i in range(1, len(positions)):
                p1 = positions[i-1]
                p2 = positions[i]
                dist = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
                total += dist
            curve_length = total
        
        return curve_length, num_points, positions, None
        
    except Exception as e:
        return 0.0, 0, [], str(e)


def extract_line_length(line_data):
    """Extract length from a ruler/line markup."""
    try:
        markups = line_data.get("markups", [])
        if not markups:
            return 0.0, [], "No markups found"
        
        markup = markups[0]
        control_points = markup.get("controlPoints", [])
        
        if len(control_points) >= 2:
            p1 = control_points[0].get("position", [0, 0, 0])
            p2 = control_points[-1].get("position", [0, 0, 0])
            length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
            return length, [p1, p2], None
        
        return 0.0, [], "Insufficient control points"
    except Exception as e:
        return 0.0, [], str(e)


def verify_aortic_path_length(traj, env_info, task_info):
    """
    Verify aortic path length measurement task completion.
    
    Uses copy_from_env to read exported results from container.
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
    path_error_max = thresholds.get('path_length_error_max_mm', 15.0)
    straight_error_max = thresholds.get('straight_length_error_max_mm', 10.0)
    tort_error_max = thresholds.get('tortuosity_error_max', 0.03)
    endpoint_error_max = thresholds.get('endpoint_error_max_mm', 25.0)
    min_points = thresholds.get('min_curve_points', 6)
    
    # Weights
    w_path = weights.get('path_length_accuracy', 30)
    w_straight = weights.get('straight_length_accuracy', 15)
    w_tortuosity = weights.get('tortuosity_ratio', 10)
    w_superior = weights.get('superior_endpoint', 10)
    w_inferior = weights.get('inferior_endpoint', 10)
    w_fidelity = weights.get('centerline_fidelity', 10)
    w_points = weights.get('sufficient_points', 5)
    w_report = weights.get('report_completeness', 10)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # COPY AND LOAD TASK RESULT
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
            "feedback": f"Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check if Slicer was running
    if not result.get('slicer_running', False):
        feedback_parts.append("FAIL: Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    feedback_parts.append("Slicer was running")
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/centerline_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use default values
        gt_data = {
            "path_length_mm": 180.0,
            "straight_length_mm": 165.0,
            "tortuosity_ratio": 1.091,
            "z_span_mm": 150.0
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_path_length = gt_data.get('path_length_mm', 180.0)
    gt_straight_length = gt_data.get('straight_length_mm', 165.0)
    gt_tortuosity = gt_data.get('tortuosity_ratio', 1.091)
    gt_z_span = gt_data.get('z_span_mm', 150.0)
    
    details['ground_truth'] = {
        'path_length_mm': gt_path_length,
        'straight_length_mm': gt_straight_length,
        'tortuosity_ratio': gt_tortuosity,
        'z_span_mm': gt_z_span
    }
    
    feedback_parts.append(f"Ground truth: path={gt_path_length:.1f}mm, straight={gt_straight_length:.1f}mm, tort={gt_tortuosity:.4f}")
    
    # ================================================================
    # CRITERION 1: CURVE EXISTS AND PATH LENGTH ACCURACY (30 points)
    # ================================================================
    agent_path_length = 0.0
    curve_points = 0
    curve_positions = []
    
    if result.get('curve_exists') and result.get('curve_valid'):
        temp_curve = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_curve.mrk.json", temp_curve.name)
            with open(temp_curve.name, 'r') as f:
                curve_data = json.load(f)
            agent_path_length, curve_points, curve_positions, error = extract_curve_info(curve_data)
            
            if error:
                feedback_parts.append(f"Curve parse warning: {error}")
            
            details['agent_curve'] = {
                'path_length_mm': agent_path_length,
                'num_points': curve_points
            }
            
            # Score path length accuracy
            path_error = abs(agent_path_length - gt_path_length)
            if path_error <= path_error_max:
                score += w_path
                feedback_parts.append(f"PASS: Path length {agent_path_length:.1f}mm (error={path_error:.1f}mm <= {path_error_max}mm)")
            elif path_error <= path_error_max * 1.5:
                partial = int(w_path * 0.6)
                score += partial
                feedback_parts.append(f"PARTIAL: Path length {agent_path_length:.1f}mm (error={path_error:.1f}mm)")
            elif path_error <= path_error_max * 2.5:
                partial = int(w_path * 0.3)
                score += partial
                feedback_parts.append(f"PARTIAL: Path length {agent_path_length:.1f}mm (error={path_error:.1f}mm, large)")
            else:
                feedback_parts.append(f"FAIL: Path length {agent_path_length:.1f}mm (error={path_error:.1f}mm too large)")
                
        except Exception as e:
            feedback_parts.append(f"Could not read curve file: {e}")
        finally:
            if os.path.exists(temp_curve.name):
                os.unlink(temp_curve.name)
    else:
        # Try to get from result data
        curve_length_str = result.get('curve_length_mm', '')
        if curve_length_str:
            try:
                agent_path_length = float(curve_length_str)
                curve_points = result.get('curve_points', 0)
                
                path_error = abs(agent_path_length - gt_path_length)
                if path_error <= path_error_max:
                    score += w_path
                    feedback_parts.append(f"PASS: Path length {agent_path_length:.1f}mm (from export)")
                elif path_error <= path_error_max * 2:
                    score += int(w_path * 0.5)
                    feedback_parts.append(f"PARTIAL: Path length {agent_path_length:.1f}mm (from export)")
                else:
                    feedback_parts.append(f"FAIL: Path length error too large")
            except:
                feedback_parts.append("FAIL: No valid curve found")
        else:
            feedback_parts.append("FAIL: No curve markup created")
    
    # ================================================================
    # CRITERION 2: STRAIGHT LENGTH ACCURACY (15 points)
    # ================================================================
    agent_straight_length = 0.0
    
    if result.get('straight_exists') and result.get('straight_valid'):
        temp_straight = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_straight.mrk.json", temp_straight.name)
            with open(temp_straight.name, 'r') as f:
                straight_data = json.load(f)
            agent_straight_length, endpoints, error = extract_line_length(straight_data)
            
            details['agent_straight'] = {
                'length_mm': agent_straight_length
            }
            
            straight_error = abs(agent_straight_length - gt_straight_length)
            if straight_error <= straight_error_max:
                score += w_straight
                feedback_parts.append(f"PASS: Straight length {agent_straight_length:.1f}mm (error={straight_error:.1f}mm)")
            elif straight_error <= straight_error_max * 2:
                partial = int(w_straight * 0.6)
                score += partial
                feedback_parts.append(f"PARTIAL: Straight length {agent_straight_length:.1f}mm")
            else:
                feedback_parts.append(f"FAIL: Straight length error too large ({straight_error:.1f}mm)")
                
        except Exception as e:
            feedback_parts.append(f"Could not read straight line: {e}")
        finally:
            if os.path.exists(temp_straight.name):
                os.unlink(temp_straight.name)
    else:
        # Try from result
        straight_str = result.get('straight_length_mm', '')
        if straight_str:
            try:
                agent_straight_length = float(straight_str)
                straight_error = abs(agent_straight_length - gt_straight_length)
                if straight_error <= straight_error_max:
                    score += w_straight
                    feedback_parts.append(f"PASS: Straight length {agent_straight_length:.1f}mm")
                elif straight_error <= straight_error_max * 2:
                    score += int(w_straight * 0.5)
                    feedback_parts.append(f"PARTIAL: Straight length {agent_straight_length:.1f}mm")
            except:
                feedback_parts.append("FAIL: No valid straight line")
        else:
            feedback_parts.append("FAIL: No straight line measurement")
    
    # ================================================================
    # CRITERION 3: TORTUOSITY RATIO (10 points)
    # ================================================================
    agent_tortuosity = 0.0
    
    # Calculate from measurements if available
    if agent_path_length > 0 and agent_straight_length > 0:
        agent_tortuosity = agent_path_length / agent_straight_length
        details['calculated_tortuosity'] = agent_tortuosity
        
        tort_error = abs(agent_tortuosity - gt_tortuosity)
        if tort_error <= tort_error_max:
            score += w_tortuosity
            feedback_parts.append(f"PASS: Tortuosity ratio {agent_tortuosity:.4f} (error={tort_error:.4f})")
        elif tort_error <= tort_error_max * 2:
            score += int(w_tortuosity * 0.6)
            feedback_parts.append(f"PARTIAL: Tortuosity ratio {agent_tortuosity:.4f}")
        elif 1.0 <= agent_tortuosity <= 1.3:
            score += int(w_tortuosity * 0.3)
            feedback_parts.append(f"PARTIAL: Tortuosity ratio in reasonable range ({agent_tortuosity:.4f})")
        else:
            feedback_parts.append(f"FAIL: Tortuosity ratio inaccurate ({agent_tortuosity:.4f})")
    else:
        # Check from report
        reported_tort = result.get('reported_tortuosity', '')
        if reported_tort:
            try:
                agent_tortuosity = float(reported_tort)
                if 1.0 <= agent_tortuosity <= 1.3:
                    score += int(w_tortuosity * 0.5)
                    feedback_parts.append(f"PARTIAL: Reported tortuosity {agent_tortuosity:.4f}")
            except:
                pass
    
    # ================================================================
    # CRITERION 4 & 5: ENDPOINT ACCURACY (10 + 10 points)
    # ================================================================
    if curve_positions and len(curve_positions) >= 2:
        start_z = curve_positions[0][2] if len(curve_positions[0]) > 2 else 0
        end_z = curve_positions[-1][2] if len(curve_positions[-1]) > 2 else 0
        agent_z_span = abs(end_z - start_z)
        
        details['curve_z_span'] = agent_z_span
        
        # Check if spans adequate z-range (compare to ground truth)
        if agent_z_span >= gt_z_span * 0.7:
            score += w_superior
            score += w_inferior
            feedback_parts.append(f"PASS: Curve spans adequate z-range ({agent_z_span:.1f}mm vs {gt_z_span:.1f}mm expected)")
        elif agent_z_span >= gt_z_span * 0.5:
            score += int((w_superior + w_inferior) * 0.5)
            feedback_parts.append(f"PARTIAL: Curve z-span somewhat short ({agent_z_span:.1f}mm)")
        elif agent_z_span >= 50:
            score += int((w_superior + w_inferior) * 0.3)
            feedback_parts.append(f"PARTIAL: Curve z-span minimal ({agent_z_span:.1f}mm)")
        else:
            feedback_parts.append(f"FAIL: Curve z-span too short ({agent_z_span:.1f}mm)")
    else:
        # Partial credit if curve exists but can't analyze positions
        if result.get('curve_exists'):
            score += int((w_superior + w_inferior) * 0.3)
            feedback_parts.append("PARTIAL: Curve exists but endpoints not analyzable")
        else:
            feedback_parts.append("FAIL: Cannot verify endpoint locations")
    
    # ================================================================
    # CRITERION 6: CENTERLINE FIDELITY (10 points)
    # Combined with z-span check above
    # ================================================================
    if curve_positions and len(curve_positions) >= 2:
        score += w_fidelity
        feedback_parts.append(f"PASS: Centerline traced with {len(curve_positions)} points")
    elif result.get('curve_exists'):
        score += int(w_fidelity * 0.5)
        feedback_parts.append("PARTIAL: Curve exists")
    
    # ================================================================
    # CRITERION 7: SUFFICIENT POINTS (5 points)
    # ================================================================
    if curve_points >= min_points + 2:
        score += w_points
        feedback_parts.append(f"PASS: Sufficient control points ({curve_points} >= {min_points})")
    elif curve_points >= min_points:
        score += w_points
        feedback_parts.append(f"PASS: Adequate control points ({curve_points})")
    elif curve_points >= min_points - 2:
        score += int(w_points * 0.6)
        feedback_parts.append(f"PARTIAL: Few control points ({curve_points})")
    elif curve_points > 0:
        score += int(w_points * 0.3)
        feedback_parts.append(f"PARTIAL: Minimal control points ({curve_points})")
    else:
        feedback_parts.append(f"FAIL: No control points found")
    
    # ================================================================
    # CRITERION 8: REPORT COMPLETENESS (10 points)
    # ================================================================
    if result.get('report_exists') and result.get('report_valid'):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_data = json.load(f)
            
            required_fields = ["path_length_mm", "straight_length_mm", "tortuosity_ratio"]
            present = sum(1 for f in required_fields if f in report_data or 
                         f.replace('_mm', '') in report_data or
                         f.replace('_ratio', '') in report_data)
            
            details['report_fields_present'] = present
            
            if present == len(required_fields):
                score += w_report
                feedback_parts.append(f"PASS: Report contains all {len(required_fields)} required fields")
            elif present > 0:
                partial = int(w_report * present / len(required_fields))
                score += partial
                feedback_parts.append(f"PARTIAL: Report has {present}/{len(required_fields)} required fields")
            else:
                feedback_parts.append("FAIL: Report missing required fields")
                
        except Exception as e:
            feedback_parts.append(f"Could not read report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        # Check if there's reported data
        if result.get('reported_path_length_mm') or result.get('reported_tortuosity'):
            score += int(w_report * 0.5)
            feedback_parts.append("PARTIAL: Some report data found")
        else:
            feedback_parts.append("FAIL: No report file created")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    score = min(100, max(0, score))
    
    # Determine pass/fail - need path length accuracy for pass
    path_length_achieved = False
    if agent_path_length > 0:
        path_error = abs(agent_path_length - gt_path_length)
        path_length_achieved = path_error <= path_error_max * 1.5
    
    passed = score >= 60 and path_length_achieved
    status = "PASSED" if passed else "FAILED"
    
    # Build final feedback
    summary = f"=== Aortic Path Length EVAR Task: {status} ({score:.0f}/100) ==="
    feedback = summary + "\n" + " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    })


if __name__ == "__main__":
    # Test mode
    score, feedback = verify_aortic_path_length({}, {}, {})
    print(feedback)
    print(f"\nFinal Score: {score}/100")
    sys.exit(0 if score >= 60 else 1)