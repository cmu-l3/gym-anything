#!/usr/bin/env python3
"""
Verifier for Neuroanatomy Landmark Documentation Suite task.

VERIFICATION STRATEGY:
1. Check fiducial placement accuracy against ground truth coordinates
2. Verify measurements are within acceptable ranges
3. Check documentation completeness
4. Use trajectory frames for VLM verification of navigation

SCORING (100 points):
- Lateral ventricle fiducial: 10 points
- Third ventricle fiducial: 10 points
- CC genu fiducial: 10 points
- CC splenium fiducial: 10 points
- Pineal gland fiducial: 10 points
- Pons fiducial: 10 points
- Third ventricle measurement: 8 points
- CC genu measurement: 7 points
- CC splenium measurement: 7 points
- Pons measurement: 8 points
- Documentation completeness: 10 points

Pass threshold: 60 points with at least 4 fiducials correctly placed
"""

import json
import os
import sys
import tempfile
import logging
import math
from typing import Dict, Any, List, Tuple, Optional

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


def euclidean_distance(p1: List[float], p2: List[float]) -> float:
    """Calculate Euclidean distance between two 3D points."""
    if len(p1) != 3 or len(p2) != 3:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


def match_structure_name(label: str, structure_keys: List[str]) -> Optional[str]:
    """
    Match a fiducial label to a structure key using flexible matching.
    
    Returns the matched structure key or None if no match found.
    """
    label_lower = label.lower().replace('_', ' ').replace('-', ' ')
    
    # Define keyword mappings for each structure
    structure_keywords = {
        'lateral_ventricle': ['lateral', 'ventricle', 'frontal horn', 'lv', 'lat vent'],
        'third_ventricle': ['third', '3rd', 'tv', 'third ventricle', '3rd vent'],
        'corpus_callosum_genu': ['genu', 'cc genu', 'corpus callosum genu', 'anterior cc'],
        'corpus_callosum_splenium': ['splenium', 'cc splenium', 'corpus callosum splenium', 'posterior cc'],
        'pineal': ['pineal', 'pineal gland'],
        'pons': ['pons', 'brainstem', 'pontine']
    }
    
    for struct_key in structure_keys:
        struct_lower = struct_key.lower()
        
        # Direct substring match
        if struct_lower in label_lower or label_lower in struct_lower:
            return struct_key
        
        # Keyword match
        for base_struct, keywords in structure_keywords.items():
            if base_struct in struct_lower:
                for kw in keywords:
                    if kw in label_lower:
                        return struct_key
    
    return None


def extract_fiducials_from_data(data: Dict) -> List[Dict]:
    """
    Extract fiducial points from various possible JSON structures.
    
    Handles:
    - Custom format: {"fiducials": [...]}
    - Slicer native format: {"markups": [{"controlPoints": [...]}]}
    """
    fiducials = []
    
    # Check for custom format
    if 'fiducials' in data:
        for fid in data['fiducials']:
            point = {
                'label': fid.get('label', fid.get('node_name', 'unknown')),
                'coordinates': fid.get('coordinates_ras', fid.get('position', [0, 0, 0]))
            }
            fiducials.append(point)
    
    # Check for Slicer native format
    elif 'markups' in data:
        for markup in data.get('markups', []):
            for cp in markup.get('controlPoints', []):
                point = {
                    'label': cp.get('label', 'unknown'),
                    'coordinates': cp.get('position', [0, 0, 0])
                }
                fiducials.append(point)
    
    # Check for structures format (from agent report)
    elif 'structures' in data:
        for struct in data.get('structures', []):
            if 'coordinates_ras' in struct:
                point = {
                    'label': struct.get('name', 'unknown'),
                    'coordinates': struct.get('coordinates_ras', [0, 0, 0])
                }
                fiducials.append(point)
    
    return fiducials


def extract_measurements_from_data(data: Dict) -> Dict[str, float]:
    """
    Extract measurements from various possible JSON structures.
    
    Returns dict mapping structure names to measurement values (mm).
    """
    measurements = {}
    
    # From custom format
    if 'measurements' in data:
        for meas in data['measurements']:
            name = meas.get('name', '').lower()
            length = meas.get('length_mm', 0)
            if length > 0:
                measurements[name] = length
    
    # From structures format (agent report)
    if 'structures' in data:
        for struct in data['structures']:
            name = struct.get('name', '').lower()
            meas_val = struct.get('measurement_mm')
            if meas_val is not None and meas_val > 0:
                measurements[name] = float(meas_val)
    
    return measurements


def verify_neuroanatomy_landmarks(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify neuroanatomy landmark documentation task completion.
    
    Uses multiple verification signals:
    1. Fiducial location accuracy
    2. Measurement accuracy
    3. Documentation completeness
    4. Timestamp verification (anti-gaming)
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
    ground_truth = metadata.get('ground_truth', {})
    weights = metadata.get('scoring_weights', {})
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {
        'fiducial_results': {},
        'measurement_results': {},
        'documentation': {}
    }
    
    # ================================================================
    # LOAD RESULT DATA
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/neuroanatomy_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task"
        }
    
    # ================================================================
    # ANTI-GAMING: Check timestamps
    # ================================================================
    task_start = result.get('task_start_time', 0)
    files_created_during_task = result.get('files_created_during_task', False)
    
    if not files_created_during_task:
        feedback_parts.append("⚠ Files may not have been created during this task session")
        details['timestamp_warning'] = True
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/neuroanatomy_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use ground truth from metadata as fallback
        gt_data = {'structures': ground_truth}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_structures = gt_data.get('structures', ground_truth)
    details['ground_truth_loaded'] = len(gt_structures) > 0
    
    # ================================================================
    # LOAD AGENT FIDUCIALS
    # ================================================================
    agent_fiducials = []
    agent_data = {}
    
    temp_fid = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_fiducials.json", temp_fid.name)
        with open(temp_fid.name, 'r') as f:
            agent_data = json.load(f)
        agent_fiducials = extract_fiducials_from_data(agent_data)
    except Exception as e:
        logger.warning(f"Failed to load agent fiducials: {e}")
    finally:
        if os.path.exists(temp_fid.name):
            os.unlink(temp_fid.name)
    
    # Also try agent report for fiducials/coordinates
    agent_report = {}
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
        report_fiducials = extract_fiducials_from_data(agent_report)
        if report_fiducials:
            agent_fiducials.extend(report_fiducials)
    except Exception as e:
        logger.warning(f"Failed to load agent report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    details['agent_fiducial_count'] = len(agent_fiducials)
    
    if not agent_fiducials:
        feedback_parts.append("✗ No fiducial markers found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) if feedback_parts else "No fiducials placed",
            "details": to_python_type(details)
        }
    
    # ================================================================
    # VERIFY FIDUCIAL LOCATIONS
    # ================================================================
    fiducials_correct = 0
    required_structures = [
        ('lateral_ventricle', ['lateral_ventricle_frontal_horn_left', 'lateral_ventricle_frontal_horn_right']),
        ('third_ventricle', ['third_ventricle']),
        ('corpus_callosum_genu', ['corpus_callosum_genu']),
        ('corpus_callosum_splenium', ['corpus_callosum_splenium']),
        ('pineal_gland', ['pineal_gland']),
        ('pons', ['pons'])
    ]
    
    matched_structures = set()
    
    for struct_name, gt_keys in required_structures:
        best_distance = float('inf')
        best_key = None
        best_tolerance = 15.0  # default
        matched_fid = None
        
        # Find the best matching fiducial for this structure
        for fid in agent_fiducials:
            fid_label = fid.get('label', '')
            fid_coords = fid.get('coordinates', [0, 0, 0])
            
            # Check against each possible ground truth key
            for gt_key in gt_keys:
                if gt_key not in gt_structures:
                    continue
                    
                gt_info = gt_structures[gt_key]
                gt_coords = gt_info.get('coordinates_ras', [0, 0, 0])
                tolerance = gt_info.get('tolerance_mm', 15.0)
                
                distance = euclidean_distance(fid_coords, gt_coords)
                
                if distance < best_distance:
                    best_distance = distance
                    best_key = gt_key
                    best_tolerance = tolerance
                    matched_fid = fid
        
        # Also check by label matching
        for fid in agent_fiducials:
            fid_label = fid.get('label', '')
            matched_key = match_structure_name(fid_label, list(gt_structures.keys()))
            
            if matched_key and matched_key in gt_keys:
                gt_info = gt_structures[matched_key]
                gt_coords = gt_info.get('coordinates_ras', [0, 0, 0])
                tolerance = gt_info.get('tolerance_mm', 15.0)
                fid_coords = fid.get('coordinates', [0, 0, 0])
                
                distance = euclidean_distance(fid_coords, gt_coords)
                
                if distance < best_distance:
                    best_distance = distance
                    best_key = matched_key
                    best_tolerance = tolerance
                    matched_fid = fid
        
        # Evaluate result
        struct_result = {
            'best_distance_mm': round(best_distance, 2) if best_distance != float('inf') else None,
            'tolerance_mm': best_tolerance,
            'within_tolerance': best_distance <= best_tolerance,
            'matched_key': best_key
        }
        
        if best_distance <= best_tolerance:
            fiducials_correct += 1
            matched_structures.add(struct_name)
            
            # Award points based on structure
            if 'lateral_ventricle' in struct_name:
                score += weights.get('lateral_ventricle_fiducial', 10)
            elif 'third_ventricle' in struct_name:
                score += weights.get('third_ventricle_fiducial', 10)
            elif 'genu' in struct_name:
                score += weights.get('cc_genu_fiducial', 10)
            elif 'splenium' in struct_name:
                score += weights.get('cc_splenium_fiducial', 10)
            elif 'pineal' in struct_name:
                score += weights.get('pineal_gland_fiducial', 10)
            elif 'pons' in struct_name:
                score += weights.get('pons_fiducial', 10)
            
            feedback_parts.append(f"✓ {struct_name}: within tolerance ({best_distance:.1f}mm)")
        else:
            if best_distance != float('inf'):
                feedback_parts.append(f"✗ {struct_name}: too far ({best_distance:.1f}mm > {best_tolerance}mm)")
            else:
                feedback_parts.append(f"✗ {struct_name}: no matching fiducial found")
        
        details['fiducial_results'][struct_name] = struct_result
    
    # ================================================================
    # VERIFY MEASUREMENTS
    # ================================================================
    agent_measurements = extract_measurements_from_data(agent_data)
    agent_measurements.update(extract_measurements_from_data(agent_report))
    
    details['agent_measurement_count'] = len(agent_measurements)
    
    measurement_checks = [
        ('third_ventricle', 'third_ventricle', 'third_ventricle_measurement', 8),
        ('corpus_callosum_genu', 'corpus_callosum_genu', 'cc_genu_measurement', 7),
        ('corpus_callosum_splenium', 'corpus_callosum_splenium', 'cc_splenium_measurement', 7),
        ('pons', 'pons', 'pons_measurement', 8)
    ]
    
    for struct_name, gt_key, weight_key, default_weight in measurement_checks:
        if gt_key not in gt_structures:
            continue
            
        gt_info = gt_structures[gt_key]
        gt_meas = gt_info.get('measurement_mm')
        meas_tol = gt_info.get('measurement_tolerance', 5.0)
        
        if gt_meas is None:
            continue
        
        # Find agent's measurement for this structure
        agent_meas = None
        for meas_key, meas_val in agent_measurements.items():
            if struct_name.replace('_', ' ') in meas_key or struct_name in meas_key:
                agent_meas = meas_val
                break
            # Also try partial matches
            if any(kw in meas_key for kw in struct_name.split('_')):
                agent_meas = meas_val
                break
        
        meas_result = {
            'ground_truth_mm': gt_meas,
            'agent_measurement_mm': agent_meas,
            'tolerance_mm': meas_tol,
            'accurate': False
        }
        
        if agent_meas is not None:
            error = abs(agent_meas - gt_meas)
            meas_result['error_mm'] = round(error, 2)
            
            if error <= meas_tol:
                meas_result['accurate'] = True
                score += weights.get(weight_key, default_weight)
                feedback_parts.append(f"✓ {struct_name} measurement: {agent_meas:.1f}mm (GT: {gt_meas}mm)")
            else:
                feedback_parts.append(f"✗ {struct_name} measurement: {agent_meas:.1f}mm (expected ~{gt_meas}mm)")
        else:
            feedback_parts.append(f"✗ {struct_name} measurement: not found")
        
        details['measurement_results'][struct_name] = meas_result
    
    # ================================================================
    # CHECK DOCUMENTATION COMPLETENESS
    # ================================================================
    doc_score = 0
    structures_in_report = agent_report.get('structures', [])
    
    if len(structures_in_report) >= 6:
        doc_score = weights.get('documentation_completeness', 10)
        feedback_parts.append(f"✓ Documentation complete ({len(structures_in_report)} structures)")
    elif len(structures_in_report) >= 4:
        doc_score = weights.get('documentation_completeness', 10) * 0.6
        feedback_parts.append(f"◐ Partial documentation ({len(structures_in_report)}/6 structures)")
    elif len(structures_in_report) > 0:
        doc_score = weights.get('documentation_completeness', 10) * 0.3
        feedback_parts.append(f"✗ Incomplete documentation ({len(structures_in_report)}/6 structures)")
    else:
        # Check if fiducials count as documentation
        if len(agent_fiducials) >= 4:
            doc_score = weights.get('documentation_completeness', 10) * 0.5
            feedback_parts.append(f"◐ Fiducials placed but report missing ({len(agent_fiducials)} fiducials)")
    
    score += doc_score
    details['documentation']['structures_in_report'] = len(structures_in_report)
    details['documentation']['doc_score'] = doc_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    score = int(min(100, max(0, score)))
    
    # Determine pass/fail
    # Pass requires: score >= 60 AND at least 4 fiducials correct
    key_criteria_met = fiducials_correct >= 4
    passed = score >= 60 and key_criteria_met
    
    details['fiducials_correct'] = fiducials_correct
    details['key_criteria_met'] = key_criteria_met
    details['final_score'] = score
    
    # Summary feedback
    summary = f"Score: {score}/100 | Fiducials: {fiducials_correct}/6 correct"
    if passed:
        summary = f"✓ PASSED - {summary}"
    else:
        if not key_criteria_met:
            summary = f"✗ FAILED (need 4+ fiducials) - {summary}"
        else:
            summary = f"✗ FAILED (score < 60) - {summary}"
    
    feedback_parts.insert(0, summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts[:8]),  # Limit feedback length
        "details": to_python_type(details)
    }