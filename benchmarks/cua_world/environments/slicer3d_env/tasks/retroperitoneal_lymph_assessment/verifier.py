#!/usr/bin/env python3
"""
Verifier for retroperitoneal lymph node assessment task.

VERIFICATION METRICS:
1. Enlarged node detection - did agent find the pathological nodes?
2. Measurement accuracy - are short-axis measurements within tolerance?
3. No missed enlarged nodes - critical for staging
4. Correct classification - normal vs enlarged based on 10mm cutoff
5. Station assignment - did agent identify anatomical locations?
6. Largest node identified - correct identification of largest node
7. Report completeness - all required fields present

Ground Truth: Synthetic lymph nodes placed in AMOS CT with known positions and sizes
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


def distance_3d(p1, p2):
    """Calculate 3D Euclidean distance between two points."""
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


def match_nodes_to_ground_truth(agent_measurements, gt_nodes, spacing_mm, max_distance_mm=25.0):
    """
    Match agent's measurements to ground truth nodes.
    
    Args:
        agent_measurements: List of agent's line measurements with midpoint
        gt_nodes: List of ground truth nodes with center_mm
        spacing_mm: Voxel spacing for coordinate conversion
        max_distance_mm: Maximum distance for matching (mm)
    
    Returns:
        List of (agent_measurement, gt_node, distance) tuples for matches
        List of unmatched gt_nodes
        List of unmatched agent_measurements
    """
    matches = []
    unmatched_gt = list(gt_nodes)
    unmatched_agent = list(agent_measurements)
    
    # Greedy matching - closest pairs first
    while unmatched_agent and unmatched_gt:
        best_match = None
        best_distance = float('inf')
        
        for agent_m in unmatched_agent:
            agent_pos = agent_m.get('midpoint', [0, 0, 0])
            
            for gt_n in unmatched_gt:
                gt_pos = gt_n.get('center_mm', [0, 0, 0])
                dist = distance_3d(agent_pos, gt_pos)
                
                if dist < best_distance and dist < max_distance_mm:
                    best_distance = dist
                    best_match = (agent_m, gt_n)
        
        if best_match:
            agent_m, gt_n = best_match
            matches.append((agent_m, gt_n, best_distance))
            unmatched_agent.remove(agent_m)
            unmatched_gt.remove(gt_n)
        else:
            break
    
    return matches, unmatched_gt, unmatched_agent


def verify_lymph_assessment(traj, env_info, task_info):
    """
    Verify retroperitoneal lymph node assessment task.
    
    Scoring (100 points total):
    - Enlarged node detection: 25 points (find >= 60% of enlarged nodes)
    - Measurement accuracy: 20 points (within 3mm of ground truth)
    - No missed enlarged nodes: 15 points (all enlarged nodes found)
    - Correct classification: 15 points (normal vs enlarged)
    - Station assignment: 10 points (correct anatomical labels)
    - Largest node identified: 10 points
    - Report completeness: 5 points
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
    
    enlarged_detection_threshold = thresholds.get('enlarged_detection_rate', 0.6)
    measurement_tolerance = thresholds.get('measurement_error_max_mm', 3.0)
    lymph_threshold_mm = metadata.get('lymph_node_threshold_mm', 10.0)
    
    w_detection = weights.get('enlarged_node_detection', 25)
    w_measurement = weights.get('measurement_accuracy', 20)
    w_no_missed = weights.get('no_missed_enlarged', 15)
    w_classification = weights.get('correct_classification', 15)
    w_station = weights.get('station_assignment', 10)
    w_largest = weights.get('largest_node_identified', 10)
    w_report = weights.get('report_completeness', 5)
    
    # Copy result files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lymph_task_result.json", temp_result.name)
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
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task"
        }
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/lymph_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
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
    
    gt_nodes = gt_data.get('nodes', [])
    gt_enlarged = [n for n in gt_nodes if n.get('classification') == 'enlarged']
    gt_normal = [n for n in gt_nodes if n.get('classification') == 'normal']
    gt_largest = max(gt_nodes, key=lambda x: x.get('short_axis_mm', 0))
    spacing = gt_data.get('voxel_spacing_mm', [1.0, 1.0, 1.0])
    
    details['gt_total_nodes'] = len(gt_nodes)
    details['gt_enlarged_count'] = len(gt_enlarged)
    details['gt_largest_mm'] = gt_largest.get('short_axis_mm', 0)
    details['gt_n_stage'] = gt_data.get('n_stage', 'N+')
    
    # Load agent's markups
    temp_markups = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_markups = {}
    try:
        copy_from_env("/tmp/agent_lymph_markups.json", temp_markups.name)
        with open(temp_markups.name, 'r') as f:
            agent_markups = json.load(f)
    except Exception as e:
        logger.info(f"No agent markups found: {e}")
        agent_markups = {'measurements': []}
    finally:
        if os.path.exists(temp_markups.name):
            os.unlink(temp_markups.name)
    
    agent_measurements = [m for m in agent_markups.get('measurements', []) 
                         if m.get('type') == 'line']
    details['agent_measurements_count'] = len(agent_measurements)
    
    # Load agent's report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_report = {}
    try:
        copy_from_env("/tmp/agent_lymph_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
    except Exception as e:
        logger.info(f"No agent report found: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # ================================================================
    # CRITERION 1: Enlarged Node Detection (25 points)
    # ================================================================
    if agent_measurements:
        matches, unmatched_gt, unmatched_agent = match_nodes_to_ground_truth(
            agent_measurements, gt_nodes, spacing
        )
        
        # Count how many enlarged nodes were detected
        enlarged_detected = 0
        for agent_m, gt_n, dist in matches:
            if gt_n.get('classification') == 'enlarged':
                enlarged_detected += 1
        
        detection_rate = enlarged_detected / len(gt_enlarged) if gt_enlarged else 1.0
        details['enlarged_detected'] = enlarged_detected
        details['detection_rate'] = detection_rate
        
        if detection_rate >= enlarged_detection_threshold:
            score += w_detection
            feedback_parts.append(f"✓ Detected {enlarged_detected}/{len(gt_enlarged)} enlarged nodes ({detection_rate:.0%})")
        elif detection_rate > 0:
            partial = int(w_detection * detection_rate / enlarged_detection_threshold)
            score += partial
            feedback_parts.append(f"◐ Detected {enlarged_detected}/{len(gt_enlarged)} enlarged nodes ({detection_rate:.0%})")
        else:
            feedback_parts.append(f"✗ No enlarged nodes detected (0/{len(gt_enlarged)})")
    else:
        feedback_parts.append("✗ No measurements found")
        matches = []
        unmatched_gt = gt_nodes
        unmatched_agent = []
    
    # ================================================================
    # CRITERION 2: Measurement Accuracy (20 points)
    # ================================================================
    accurate_measurements = 0
    total_error = 0.0
    
    for agent_m, gt_n, dist in matches:
        agent_length = agent_m.get('length_mm', 0)
        gt_short_axis = gt_n.get('short_axis_mm', 0)
        error = abs(agent_length - gt_short_axis)
        total_error += error
        
        if error <= measurement_tolerance:
            accurate_measurements += 1
    
    if matches:
        accuracy_rate = accurate_measurements / len(matches)
        avg_error = total_error / len(matches)
        details['accurate_measurements'] = accurate_measurements
        details['avg_measurement_error_mm'] = round(avg_error, 2)
        
        if accuracy_rate >= 0.5:
            score += int(w_measurement * accuracy_rate)
            feedback_parts.append(f"✓ {accurate_measurements}/{len(matches)} measurements within ±{measurement_tolerance}mm")
        else:
            score += int(w_measurement * accuracy_rate * 0.5)
            feedback_parts.append(f"◐ Measurement accuracy: {accuracy_rate:.0%} (avg error: {avg_error:.1f}mm)")
    else:
        feedback_parts.append("✗ No measurements to evaluate accuracy")
    
    # ================================================================
    # CRITERION 3: No Missed Enlarged Nodes (15 points)
    # ================================================================
    missed_enlarged = [n for n in unmatched_gt if n.get('classification') == 'enlarged']
    details['missed_enlarged'] = len(missed_enlarged)
    
    if len(missed_enlarged) == 0 and len(gt_enlarged) > 0:
        score += w_no_missed
        feedback_parts.append("✓ All enlarged nodes identified")
    elif len(missed_enlarged) < len(gt_enlarged):
        partial = int(w_no_missed * (1 - len(missed_enlarged) / len(gt_enlarged)))
        score += partial
        feedback_parts.append(f"◐ Missed {len(missed_enlarged)} enlarged node(s)")
    else:
        feedback_parts.append(f"✗ Missed all {len(missed_enlarged)} enlarged nodes")
    
    # ================================================================
    # CRITERION 4: Correct Classification (15 points)
    # ================================================================
    correct_classifications = 0
    
    for agent_m, gt_n, dist in matches:
        agent_length = agent_m.get('length_mm', 0)
        agent_class = 'enlarged' if agent_length >= lymph_threshold_mm else 'normal'
        gt_class = gt_n.get('classification', 'normal')
        
        if agent_class == gt_class:
            correct_classifications += 1
    
    if matches:
        class_rate = correct_classifications / len(matches)
        details['correct_classifications'] = correct_classifications
        
        if class_rate >= 0.7:
            score += int(w_classification * class_rate)
            feedback_parts.append(f"✓ Classification: {correct_classifications}/{len(matches)} correct")
        else:
            score += int(w_classification * class_rate * 0.5)
            feedback_parts.append(f"◐ Classification: {class_rate:.0%} correct")
    
    # ================================================================
    # CRITERION 5: Station Assignment (10 points)
    # ================================================================
    # Check if agent included station names in measurement labels
    station_mentions = 0
    station_keywords = ['aortic', 'aorta', 'caval', 'cava', 'para', 'retro', 'ivc']
    
    for agent_m in agent_measurements:
        name = agent_m.get('name', '').lower()
        if any(kw in name for kw in station_keywords):
            station_mentions += 1
    
    if station_mentions > 0:
        station_rate = min(1.0, station_mentions / max(1, len(agent_measurements)))
        score += int(w_station * station_rate)
        feedback_parts.append(f"✓ Station labels found in {station_mentions} measurement(s)")
        details['station_labels'] = station_mentions
    else:
        # Check report for station info
        if agent_report.get('largest_node_station'):
            score += int(w_station * 0.5)
            feedback_parts.append("◐ Station info in report only")
        else:
            feedback_parts.append("✗ No anatomical station labels")
    
    # ================================================================
    # CRITERION 6: Largest Node Identified (10 points)
    # ================================================================
    reported_largest = None
    try:
        reported_largest = float(result.get('reported_largest_mm') or 
                                 agent_report.get('largest_node_mm', 0))
    except (ValueError, TypeError):
        reported_largest = 0
    
    if reported_largest:
        largest_error = abs(reported_largest - gt_largest.get('short_axis_mm', 0))
        details['reported_largest_mm'] = reported_largest
        details['largest_error_mm'] = round(largest_error, 2)
        
        if largest_error <= measurement_tolerance:
            score += w_largest
            feedback_parts.append(f"✓ Largest node: {reported_largest}mm (GT: {gt_largest['short_axis_mm']}mm)")
        elif largest_error <= measurement_tolerance * 2:
            score += int(w_largest * 0.5)
            feedback_parts.append(f"◐ Largest node: {reported_largest}mm (error: {largest_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Largest node error: {largest_error:.1f}mm")
    else:
        feedback_parts.append("✗ Largest node not reported")
    
    # ================================================================
    # CRITERION 7: Report Completeness (5 points)
    # ================================================================
    required_fields = ['total_nodes_identified', 'enlarged_nodes_count', 
                      'largest_node_mm', 'n_stage']
    
    # Accept alternative field names
    field_aliases = {
        'total_nodes_identified': ['total_nodes', 'nodes_count', 'total'],
        'enlarged_nodes_count': ['enlarged_count', 'pathological_count'],
        'largest_node_mm': ['largest_mm', 'max_diameter'],
        'n_stage': ['stage', 'staging']
    }
    
    fields_present = 0
    for field in required_fields:
        if field in agent_report:
            fields_present += 1
        else:
            for alias in field_aliases.get(field, []):
                if alias in agent_report:
                    fields_present += 1
                    break
    
    if agent_report:
        completeness = fields_present / len(required_fields)
        score += int(w_report * completeness)
        if completeness >= 0.75:
            feedback_parts.append(f"✓ Report complete ({fields_present}/{len(required_fields)} fields)")
        else:
            feedback_parts.append(f"◐ Report partial ({fields_present}/{len(required_fields)} fields)")
        details['report_fields'] = fields_present
    else:
        feedback_parts.append("✗ No report file found")
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    # Key criteria: Must have found at least some enlarged nodes and not missed all of them
    key_criteria_met = (
        len(missed_enlarged) < len(gt_enlarged) and
        result.get('markups_created_during_task', False)
    )
    
    passed = score >= 60 and key_criteria_met
    
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "key_criteria_met": key_criteria_met
    }