#!/usr/bin/env python3
"""
Verifier for aortic tortuosity index assessment task.

VERIFICATION METRICS:
1. Tortuosity Index accuracy - within 5 percentage points of ground truth
2. Arc length accuracy - within 15% of ground truth
3. Chord length accuracy - within 10% of ground truth
4. Classification correctness - correct category (Normal/Mild/Moderate/Severe)
5. Centerline quality - adequate points, proper distribution
6. Report completeness - all required fields present

Ground Truth: Synthetic aorta with known sinusoidal tortuosity
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


def calculate_tortuosity_from_points(points):
    """
    Calculate tortuosity metrics from a list of 3D points.
    
    Args:
        points: List of [x, y, z] coordinates in mm
    
    Returns:
        dict with chord_length, arc_length, tortuosity_index, or None if insufficient points
    """
    if len(points) < 2:
        return None
    
    # Sort by z-coordinate (superior to inferior)
    sorted_points = sorted(points, key=lambda p: p[2], reverse=True)
    
    # Chord length
    first_pt = sorted_points[0]
    last_pt = sorted_points[-1]
    chord_length = math.sqrt(sum((a-b)**2 for a, b in zip(first_pt, last_pt)))
    
    # Arc length
    arc_length = 0.0
    for i in range(1, len(sorted_points)):
        p1 = sorted_points[i-1]
        p2 = sorted_points[i]
        arc_length += math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
    
    # Tortuosity Index
    if chord_length > 0:
        ti = ((arc_length - chord_length) / chord_length) * 100.0
    else:
        ti = 0.0
    
    return {
        "chord_length_mm": chord_length,
        "arc_length_mm": arc_length,
        "tortuosity_index_percent": ti
    }


def get_classification(ti):
    """Get tortuosity classification from index value."""
    if ti < 10:
        return "Normal"
    elif ti < 20:
        return "Mild Tortuosity"
    elif ti < 35:
        return "Moderate Tortuosity"
    else:
        return "Severe Tortuosity"


def verify_aortic_tortuosity(traj, env_info, task_info):
    """
    Verify aortic tortuosity index assessment task.
    
    Scoring (100 points total):
    - Tortuosity Index accuracy: 30 points (within 5 percentage points)
    - Arc length accuracy: 20 points (within 15%)
    - Chord length accuracy: 15 points (within 10%)
    - Classification correct: 15 points
    - Centerline quality: 10 points (adequate points, distribution)
    - Report completeness: 10 points
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
    
    ti_error_max = thresholds.get('ti_error_max_percent', 5.0)
    arc_error_max = thresholds.get('arc_length_error_max_percent', 15.0)
    chord_error_max = thresholds.get('chord_length_error_max_percent', 10.0)
    min_points = thresholds.get('min_centerline_points', 8)
    
    w_ti = weights.get('tortuosity_index_accuracy', 30)
    w_arc = weights.get('arc_length_accuracy', 20)
    w_chord = weights.get('chord_length_accuracy', 15)
    w_class = weights.get('classification_correct', 15)
    w_quality = weights.get('centerline_quality', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tortuosity_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/tortuosity_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_chord = gt_data.get('chord_length_mm', 0)
    gt_arc = gt_data.get('arc_length_mm', 0)
    gt_ti = gt_data.get('tortuosity_index_percent', 0)
    gt_class = gt_data.get('classification', '')
    
    details['gt_chord_mm'] = gt_chord
    details['gt_arc_mm'] = gt_arc
    details['gt_ti_percent'] = gt_ti
    details['gt_classification'] = gt_class
    
    if gt_chord == 0 or gt_arc == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Ground truth data missing or invalid"
        }
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    agent_chord = 0.0
    agent_arc = 0.0
    agent_ti = 0.0
    agent_class = ''
    num_points = result.get('num_centerline_points', 0)
    
    # Try from agent_measurements in result
    agent_meas = result.get('agent_measurements', {})
    
    # Parse numeric values
    try:
        chord_str = agent_meas.get('chord_length_mm', '')
        if chord_str:
            agent_chord = float(chord_str)
    except (ValueError, TypeError):
        pass
    
    try:
        arc_str = agent_meas.get('arc_length_mm', '')
        if arc_str:
            agent_arc = float(arc_str)
    except (ValueError, TypeError):
        pass
    
    try:
        ti_str = agent_meas.get('tortuosity_index_percent', '')
        if ti_str:
            agent_ti = float(ti_str)
    except (ValueError, TypeError):
        pass
    
    agent_class = agent_meas.get('classification', '')
    
    # If we couldn't get measurements from export, try to load centerline and calculate
    if agent_chord == 0 or agent_arc == 0:
        temp_centerline = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_centerline.json", temp_centerline.name)
            with open(temp_centerline.name, 'r') as f:
                cl_data = json.load(f)
            
            # Extract points
            points = []
            if 'centerline_points' in cl_data:
                for pt in cl_data['centerline_points']:
                    pos = pt.get('position_mm', pt.get('position', []))
                    if len(pos) >= 3:
                        points.append(pos)
            elif 'markups' in cl_data:
                for markup in cl_data.get('markups', []):
                    for cp in markup.get('controlPoints', []):
                        pos = cp.get('position', [])
                        if len(pos) >= 3:
                            points.append(pos)
            
            if points:
                num_points = len(points)
                calc = calculate_tortuosity_from_points(points)
                if calc:
                    agent_chord = calc['chord_length_mm']
                    agent_arc = calc['arc_length_mm']
                    agent_ti = calc['tortuosity_index_percent']
                    agent_class = get_classification(agent_ti)
                    logger.info(f"Calculated from {num_points} centerline points")
        except Exception as e:
            logger.warning(f"Could not load agent centerline: {e}")
        finally:
            if os.path.exists(temp_centerline.name):
                os.unlink(temp_centerline.name)
    
    details['agent_chord_mm'] = agent_chord
    details['agent_arc_mm'] = agent_arc
    details['agent_ti_percent'] = agent_ti
    details['agent_classification'] = agent_class
    details['num_centerline_points'] = num_points
    
    # ============================================================
    # CRITERION 1: Tortuosity Index Accuracy (30 points)
    # ============================================================
    ti_error = abs(agent_ti - gt_ti)
    details['ti_error'] = ti_error
    
    if agent_ti > 0:
        if ti_error <= ti_error_max:
            score += w_ti
            feedback_parts.append(f"TI accurate: {agent_ti:.1f}% vs {gt_ti:.1f}% (error: {ti_error:.1f}%)")
        elif ti_error <= ti_error_max * 2:
            score += w_ti * 0.5
            feedback_parts.append(f"TI close: {agent_ti:.1f}% vs {gt_ti:.1f}% (error: {ti_error:.1f}%)")
        else:
            feedback_parts.append(f"TI inaccurate: {agent_ti:.1f}% vs {gt_ti:.1f}% (error: {ti_error:.1f}%)")
    else:
        feedback_parts.append("No tortuosity index calculated")
    
    # ============================================================
    # CRITERION 2: Arc Length Accuracy (20 points)
    # ============================================================
    if agent_arc > 0 and gt_arc > 0:
        arc_error_pct = abs(agent_arc - gt_arc) / gt_arc * 100
        details['arc_error_percent'] = arc_error_pct
        
        if arc_error_pct <= arc_error_max:
            score += w_arc
            feedback_parts.append(f"Arc length accurate: {agent_arc:.1f}mm vs {gt_arc:.1f}mm")
        elif arc_error_pct <= arc_error_max * 2:
            score += w_arc * 0.5
            feedback_parts.append(f"Arc length close: {agent_arc:.1f}mm vs {gt_arc:.1f}mm")
        else:
            feedback_parts.append(f"Arc length inaccurate: {agent_arc:.1f}mm vs {gt_arc:.1f}mm")
    else:
        feedback_parts.append("No arc length calculated")
    
    # ============================================================
    # CRITERION 3: Chord Length Accuracy (15 points)
    # ============================================================
    if agent_chord > 0 and gt_chord > 0:
        chord_error_pct = abs(agent_chord - gt_chord) / gt_chord * 100
        details['chord_error_percent'] = chord_error_pct
        
        if chord_error_pct <= chord_error_max:
            score += w_chord
            feedback_parts.append(f"Chord length accurate: {agent_chord:.1f}mm vs {gt_chord:.1f}mm")
        elif chord_error_pct <= chord_error_max * 2:
            score += w_chord * 0.5
            feedback_parts.append(f"Chord length close: {agent_chord:.1f}mm vs {gt_chord:.1f}mm")
        else:
            feedback_parts.append(f"Chord length inaccurate: {agent_chord:.1f}mm vs {gt_chord:.1f}mm")
    else:
        feedback_parts.append("No chord length calculated")
    
    # ============================================================
    # CRITERION 4: Classification Correct (15 points)
    # ============================================================
    if agent_class:
        agent_class_lower = agent_class.lower().replace("_", " ")
        gt_class_lower = gt_class.lower().replace("_", " ")
        
        # Check for match (allow some flexibility)
        class_match = False
        if agent_class_lower == gt_class_lower:
            class_match = True
        elif "normal" in agent_class_lower and "normal" in gt_class_lower:
            class_match = True
        elif "mild" in agent_class_lower and "mild" in gt_class_lower:
            class_match = True
        elif "moderate" in agent_class_lower and "moderate" in gt_class_lower:
            class_match = True
        elif "severe" in agent_class_lower and "severe" in gt_class_lower:
            class_match = True
        
        if class_match:
            score += w_class
            feedback_parts.append(f"Classification correct: {agent_class}")
        else:
            # Check if off by one category (partial credit)
            categories = ["normal", "mild", "moderate", "severe"]
            try:
                agent_idx = next(i for i, c in enumerate(categories) if c in agent_class_lower)
                gt_idx = next(i for i, c in enumerate(categories) if c in gt_class_lower)
                if abs(agent_idx - gt_idx) == 1:
                    score += w_class * 0.5
                    feedback_parts.append(f"Classification off by one: {agent_class} vs {gt_class}")
                else:
                    feedback_parts.append(f"Classification wrong: {agent_class} vs {gt_class}")
            except StopIteration:
                feedback_parts.append(f"Classification wrong: {agent_class} vs {gt_class}")
    else:
        feedback_parts.append("No classification provided")
    
    # ============================================================
    # CRITERION 5: Centerline Quality (10 points)
    # ============================================================
    if num_points >= min_points:
        score += w_quality
        feedback_parts.append(f"Centerline quality good: {num_points} points")
    elif num_points >= min_points // 2:
        score += w_quality * 0.5
        feedback_parts.append(f"Centerline sparse: {num_points} points (recommend >={min_points})")
    elif num_points > 0:
        score += w_quality * 0.25
        feedback_parts.append(f"Centerline insufficient: only {num_points} points")
    else:
        feedback_parts.append("No centerline points found")
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_fields = 0
    required_fields = ['chord_length_mm', 'arc_length_mm', 'tortuosity_index_percent', 'classification']
    
    if report_exists:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_data = json.load(f)
            
            for field in required_fields:
                if field in report_data and report_data[field]:
                    report_fields += 1
        except Exception:
            pass
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    
    if report_fields == len(required_fields):
        score += w_report
        feedback_parts.append("Report complete with all fields")
    elif report_fields > 0:
        partial = w_report * (report_fields / len(required_fields))
        score += partial
        feedback_parts.append(f"Report partial: {report_fields}/{len(required_fields)} fields")
    elif result.get('centerline_exists', False):
        # Give partial credit if centerline exists with measurements
        score += w_report * 0.5
        feedback_parts.append("No separate report, but measurements in centerline file")
    else:
        feedback_parts.append("No report file created")
    
    # ============================================================
    # ANTI-GAMING: Check file was created during task
    # ============================================================
    file_created = result.get('file_created_during_task', False)
    if not file_created and result.get('centerline_exists', False):
        feedback_parts.append("WARNING: Centerline file may not have been created during task")
        score = max(0, score - 10)
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    score = int(round(score))
    score = max(0, min(100, score))
    
    # Pass criteria: score >= 60 AND TI within reasonable range
    ti_reasonable = ti_error <= ti_error_max * 2 if agent_ti > 0 else False
    passed = score >= 60 and ti_reasonable
    
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }