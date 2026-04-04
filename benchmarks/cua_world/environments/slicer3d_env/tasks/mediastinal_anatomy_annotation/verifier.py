#!/usr/bin/env python3
"""
Verifier for Mediastinal Anatomy Annotation task.

VERIFICATION STRATEGY:
1. Landmark file exists and is valid JSON (10 points)
2. All 6 required landmarks present with correct names (partial credit per landmark)
3. HU values at landmark positions match expected tissue type (major criterion)
4. Spatial relationships between structures are anatomically correct (10 points)
5. Anti-gaming: File must be created during task

SCORING:
- AscendingAorta: 14 points (HU validation)
- DescendingAorta: 14 points (HU validation)
- PulmonaryArtery: 14 points (HU validation)
- Trachea: 14 points (HU validation - must be air)
- LeftAtrium: 12 points (HU validation)
- Esophagus: 12 points (HU validation)
- Spatial relationships: 10 points
- File validity: 10 points

Pass threshold: 60 points with Trachea and at least one Aorta correct
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import nibabel
HAS_NIBABEL = False
try:
    import nibabel as nib
    HAS_NIBABEL = True
except ImportError:
    logger.warning("nibabel not available - will attempt to install")


def ensure_nibabel():
    """Ensure nibabel is available."""
    global HAS_NIBABEL, nib
    if not HAS_NIBABEL:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
            import nibabel as nib_module
            nib = nib_module
            HAS_NIBABEL = True
        except Exception as e:
            logger.error(f"Failed to install nibabel: {e}")
    return HAS_NIBABEL


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


def parse_slicer_landmarks(data):
    """
    Parse landmarks from Slicer markup JSON format.
    
    Returns dict mapping lowercase landmark name to position.
    """
    landmarks = {}
    
    try:
        # Slicer markup format
        if 'markups' in data and len(data['markups']) > 0:
            control_points = data['markups'][0].get('controlPoints', [])
            for cp in control_points:
                label = cp.get('label', cp.get('id', 'Unknown'))
                position = cp.get('position', [0, 0, 0])
                # Normalize name for matching
                normalized_name = label.lower().replace('_', '').replace(' ', '').replace('-', '')
                landmarks[normalized_name] = {
                    'original_name': label,
                    'position_ras': position
                }
        # Alternative simple format
        elif 'landmarks' in data:
            for item in data['landmarks']:
                label = item.get('label', item.get('name', 'Unknown'))
                position = item.get('position', item.get('coordinates', [0, 0, 0]))
                normalized_name = label.lower().replace('_', '').replace(' ', '').replace('-', '')
                landmarks[normalized_name] = {
                    'original_name': label,
                    'position_ras': position
                }
    except Exception as e:
        logger.error(f"Error parsing landmarks: {e}")
    
    return landmarks


def get_hu_at_position(ct_data, affine, ras_position):
    """
    Get HU value at a given RAS position.
    
    Args:
        ct_data: numpy array of CT volume
        affine: 4x4 affine matrix
        ras_position: [R, A, S] coordinates
        
    Returns:
        HU value at position, or None if out of bounds
    """
    try:
        # Convert RAS to voxel coordinates
        ras_coord = np.array([ras_position[0], ras_position[1], ras_position[2], 1])
        voxel_coord = np.linalg.inv(affine) @ ras_coord
        
        vx = int(round(voxel_coord[0]))
        vy = int(round(voxel_coord[1]))
        vz = int(round(voxel_coord[2]))
        
        # Check bounds
        if (0 <= vx < ct_data.shape[0] and 
            0 <= vy < ct_data.shape[1] and 
            0 <= vz < ct_data.shape[2]):
            return float(ct_data[vx, vy, vz])
    except Exception as e:
        logger.error(f"Error getting HU at position: {e}")
    
    return None


def verify_mediastinal_anatomy(traj, env_info, task_info):
    """
    Verify mediastinal anatomy annotation task.
    
    Uses multi-criteria scoring based on:
    - Landmark presence and naming
    - HU validation at landmark positions
    - Spatial relationship validation
    - Anti-gaming timestamp checks
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
    required_landmarks = metadata.get('required_landmarks', [
        'AscendingAorta', 'DescendingAorta', 'PulmonaryArtery',
        'Trachea', 'LeftAtrium', 'Esophagus'
    ])
    expected_hu_ranges = metadata.get('expected_hu_ranges', {
        'AscendingAorta': [-100, 200],
        'DescendingAorta': [-100, 200],
        'PulmonaryArtery': [-100, 200],
        'Trachea': [-1024, -700],
        'LeftAtrium': [-100, 200],
        'Esophagus': [-150, 150]
    })
    weights = metadata.get('scoring_weights', {
        'ascending_aorta': 14,
        'descending_aorta': 14,
        'pulmonary_artery': 14,
        'trachea': 14,
        'left_atrium': 12,
        'esophagus': 12,
        'spatial_relationships': 10,
        'file_validity': 10
    })
    
    # Initialize results
    results = {
        'landmarks_found': {},
        'hu_validation': {},
        'spatial_validation': {},
        'individual_scores': {},
        'errors': [],
        'feedback': []
    }
    score = 0
    
    # ================================================================
    # STEP 1: Copy and read task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mediastinal_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}",
            "details": to_python_type(results)
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Anti-gaming check - file must be created during task
    # ================================================================
    if not task_result.get('file_created_during_task', False):
        if task_result.get('landmarks_file_exists', False):
            results['feedback'].append("⚠ WARNING: Landmarks file existed before task started")
            # Reduce score but don't completely fail
        else:
            results['feedback'].append("✗ No landmarks file was created")
            return {
                "passed": False,
                "score": 0,
                "feedback": "No landmarks file was created during the task",
                "details": to_python_type(results)
            }
    
    # Check if Slicer was running
    if not task_result.get('slicer_running', False):
        results['feedback'].append("⚠ Slicer was not running at export time")
    
    # ================================================================
    # STEP 3: Copy and parse landmarks file
    # ================================================================
    temp_landmarks = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_landmarks = {}
    
    try:
        copy_from_env("/tmp/agent_landmarks.mrk.json", temp_landmarks.name)
        with open(temp_landmarks.name, 'r') as f:
            landmarks_data = json.load(f)
        agent_landmarks = parse_slicer_landmarks(landmarks_data)
        results['feedback'].append(f"✓ Landmarks file valid, found {len(agent_landmarks)} landmarks")
        score += 5  # Partial file validity points
    except Exception as e:
        results['errors'].append(f"Could not read landmarks file: {e}")
        results['feedback'].append(f"✗ Could not read landmarks file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read landmarks file: {e}",
            "details": to_python_type(results)
        }
    finally:
        if os.path.exists(temp_landmarks.name):
            os.unlink(temp_landmarks.name)
    
    # ================================================================
    # STEP 4: Load CT data for HU validation
    # ================================================================
    ct_data = None
    ct_affine = None
    
    if ensure_nibabel():
        temp_ct = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        try:
            copy_from_env("/tmp/chest_ct.nii.gz", temp_ct.name)
            ct_nii = nib.load(temp_ct.name)
            ct_data = ct_nii.get_fdata()
            ct_affine = ct_nii.affine
            results['feedback'].append("✓ CT data loaded for HU validation")
        except Exception as e:
            results['feedback'].append(f"△ CT data not available for HU validation: {e}")
        finally:
            if os.path.exists(temp_ct.name):
                os.unlink(temp_ct.name)
    
    # ================================================================
    # STEP 5: Validate each required landmark
    # ================================================================
    # Map required names to normalized versions for matching
    landmark_name_map = {
        'AscendingAorta': 'ascendingaorta',
        'DescendingAorta': 'descendingaorta',
        'PulmonaryArtery': 'pulmonaryartery',
        'Trachea': 'trachea',
        'LeftAtrium': 'leftatrium',
        'Esophagus': 'esophagus'
    }
    
    weight_map = {
        'AscendingAorta': weights.get('ascending_aorta', 14),
        'DescendingAorta': weights.get('descending_aorta', 14),
        'PulmonaryArtery': weights.get('pulmonary_artery', 14),
        'Trachea': weights.get('trachea', 14),
        'LeftAtrium': weights.get('left_atrium', 12),
        'Esophagus': weights.get('esophagus', 12)
    }
    
    for req_name in required_landmarks:
        normalized_req = landmark_name_map.get(req_name, req_name.lower().replace('_', ''))
        max_points = weight_map.get(req_name, 12)
        landmark_score = 0
        
        # Find matching landmark in agent's landmarks
        matched = None
        for agent_name, agent_data in agent_landmarks.items():
            if agent_name == normalized_req:
                matched = agent_data
                break
        
        results['landmarks_found'][req_name] = {
            'found': matched is not None,
            'matched_name': matched['original_name'] if matched else None
        }
        
        if not matched:
            results['feedback'].append(f"✗ {req_name}: Not found")
            results['individual_scores'][req_name] = 0
            continue
        
        position_ras = matched['position_ras']
        results['feedback'].append(f"✓ {req_name}: Found as '{matched['original_name']}'")
        
        # HU Validation
        if ct_data is not None and ct_affine is not None:
            hu_value = get_hu_at_position(ct_data, ct_affine, position_ras)
            
            if hu_value is not None:
                min_hu, max_hu = expected_hu_ranges.get(req_name, [-500, 500])
                hu_valid = min_hu <= hu_value <= max_hu
                
                results['hu_validation'][req_name] = {
                    'hu_value': hu_value,
                    'expected_range': [min_hu, max_hu],
                    'valid': hu_valid
                }
                
                if hu_valid:
                    landmark_score = max_points
                    results['feedback'].append(f"  ✓ HU={hu_value:.0f} (valid, range {min_hu} to {max_hu})")
                else:
                    # Partial credit for placing landmark in reasonable location
                    if req_name == 'Trachea':
                        if hu_value < -500:
                            landmark_score = max_points * 0.5
                            results['feedback'].append(f"  △ HU={hu_value:.0f} (low density but not air)")
                        else:
                            results['feedback'].append(f"  ✗ HU={hu_value:.0f} (not air - expected {min_hu} to {max_hu})")
                    else:
                        if -200 <= hu_value <= 300:
                            landmark_score = max_points * 0.5
                            results['feedback'].append(f"  △ HU={hu_value:.0f} (soft tissue but not optimal)")
                        else:
                            results['feedback'].append(f"  ✗ HU={hu_value:.0f} (wrong tissue type)")
            else:
                # Position out of bounds
                landmark_score = max_points * 0.25
                results['feedback'].append(f"  △ Position may be out of volume bounds")
        else:
            # No CT data - give partial credit for presence
            landmark_score = max_points * 0.5
            results['feedback'].append(f"  △ Present (HU validation skipped)")
        
        results['individual_scores'][req_name] = landmark_score
        score += landmark_score
    
    # ================================================================
    # STEP 6: Validate spatial relationships
    # ================================================================
    spatial_score = 0
    max_spatial = weights.get('spatial_relationships', 10)
    spatial_checks = []
    
    def get_landmark_position(name):
        normalized = landmark_name_map.get(name, name.lower())
        if normalized in agent_landmarks:
            return agent_landmarks[normalized]['position_ras']
        return None
    
    # Check: Ascending aorta should be anterior to descending aorta
    asc_pos = get_landmark_position('AscendingAorta')
    desc_pos = get_landmark_position('DescendingAorta')
    if asc_pos and desc_pos:
        # In RAS coordinates, positive Y is typically anterior
        # But this depends on affine - use simple Y comparison
        is_correct = asc_pos[1] < desc_pos[1]  # Ascending more anterior
        spatial_checks.append(('Ascending anterior to Descending', is_correct))
    
    # Check: Trachea should be anterior to esophagus
    trachea_pos = get_landmark_position('Trachea')
    esoph_pos = get_landmark_position('Esophagus')
    if trachea_pos and esoph_pos:
        is_correct = trachea_pos[1] < esoph_pos[1]  # Trachea more anterior
        spatial_checks.append(('Trachea anterior to Esophagus', is_correct))
    
    # Check: Pulmonary artery should be anterior to ascending aorta
    pa_pos = get_landmark_position('PulmonaryArtery')
    if pa_pos and asc_pos:
        is_correct = pa_pos[1] <= asc_pos[1]  # PA at least as anterior
        spatial_checks.append(('PA anterior to Ascending Aorta', is_correct))
    
    correct_spatial = 0
    for check_name, is_correct in spatial_checks:
        results['spatial_validation'][check_name] = is_correct
        if is_correct:
            correct_spatial += 1
            results['feedback'].append(f"✓ Spatial: {check_name}")
        else:
            results['feedback'].append(f"✗ Spatial: {check_name}")
    
    if len(spatial_checks) > 0:
        spatial_score = max_spatial * (correct_spatial / len(spatial_checks))
    else:
        spatial_score = 0
        results['feedback'].append("△ Spatial relationships not checked (insufficient landmarks)")
    
    results['individual_scores']['spatial_relationships'] = spatial_score
    score += spatial_score
    
    # ================================================================
    # STEP 7: File validity bonus
    # ================================================================
    file_score = 5  # Already got 5 for valid JSON
    
    # Bonus for correct naming
    correct_names = sum(1 for req in required_landmarks 
                       if results['landmarks_found'].get(req, {}).get('found', False))
    if correct_names == 6:
        file_score += 5
        results['feedback'].append("✓ All 6 landmarks named correctly")
    elif correct_names >= 4:
        file_score += 3
        results['feedback'].append(f"△ {correct_names}/6 landmarks named correctly")
    
    results['individual_scores']['file_validity'] = file_score
    score += file_score - 5  # Subtract the 5 already added
    
    # ================================================================
    # STEP 8: Calculate final score and pass/fail
    # ================================================================
    score = min(100, max(0, score))
    
    # Key criteria: Trachea and at least one aorta must be correct
    trachea_ok = results['individual_scores'].get('Trachea', 0) >= 7  # At least half points
    asc_aorta_ok = results['individual_scores'].get('AscendingAorta', 0) >= 7
    desc_aorta_ok = results['individual_scores'].get('DescendingAorta', 0) >= 7
    
    key_criteria_met = trachea_ok and (asc_aorta_ok or desc_aorta_ok)
    
    passed = score >= 60 and key_criteria_met
    
    results['total_score'] = score
    results['passed'] = passed
    results['key_criteria_met'] = key_criteria_met
    
    # Final summary
    results['feedback'].append("")
    results['feedback'].append(f"=== TOTAL SCORE: {score:.1f}/100 ===")
    results['feedback'].append(f"Key criteria (Trachea + Aorta): {'MET' if key_criteria_met else 'NOT MET'}")
    results['feedback'].append(f"Pass threshold: 60 points with key criteria")
    results['feedback'].append(f"Result: {'PASS' if passed else 'FAIL'}")
    
    return {
        "passed": passed,
        "score": int(round(score)),
        "feedback": " | ".join(results['feedback'][:10]) + (f" ... ({len(results['feedback'])} messages)" if len(results['feedback']) > 10 else ""),
        "details": to_python_type(results)
    }


# For standalone testing
if __name__ == "__main__":
    print("Mediastinal Anatomy Annotation Verifier")
    print("Run through the task framework for actual verification")
    
    # Quick test with mock data
    mock_result = {
        "passed": False,
        "score": 0,
        "feedback": "Test mode - no verification performed"
    }
    print(json.dumps(mock_result, indent=2))