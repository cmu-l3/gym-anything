#!/usr/bin/env python3
"""
Verifier for surgical_anatomy_briefing task.

VERIFICATION STRATEGY:
1. Check fiducials exist with anatomically meaningful labels
2. Verify fiducial positions fall within correct organ regions (using AMOS ground truth)
3. Check screenshots exist and have reasonable quality
4. Verify scene was saved

SCORING (100 points total):
- Liver fiducial correctly placed: 10 points
- Spleen fiducial correctly placed: 10 points
- Right Kidney fiducial correctly placed: 10 points
- Left Kidney fiducial correctly placed: 10 points
- Aorta fiducial correctly placed: 8 points
- IVC fiducial correctly placed: 8 points
- Pancreas fiducial correctly placed: 8 points
- 8th structure (portal vein/gallbladder): 6 points
- Axial screenshot exists: 5 points
- Coronal screenshot exists: 5 points
- Sagittal screenshot exists: 5 points
- Fiducial file valid JSON: 5 points
- Scene saved: 5 points
- Label quality (meaningful names): 5 points

Pass threshold: 60 points (at least 5 structures correctly identified + documentation)
"""

import json
import os
import sys
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import optional dependencies
np = None
nib = None
NIBABEL_AVAILABLE = False

try:
    import numpy as np
    import nibabel as nib
    NIBABEL_AVAILABLE = True
except ImportError:
    logger.warning("numpy/nibabel not available - will try to install")


def ensure_dependencies():
    """Ensure required packages are available."""
    global NIBABEL_AVAILABLE, np, nib
    if not NIBABEL_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy", "nibabel"])
            import numpy as np_module
            import nibabel as nib_module
            np = np_module
            nib = nib_module
            NIBABEL_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install dependencies: {e}")
            return False
    return True


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    if np is None:
        return val
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


def normalize_structure_name(label):
    """Normalize structure name for matching."""
    if not label:
        return ""
    label = label.lower().strip()
    # Remove common prefixes/suffixes
    label = re.sub(r'^(point|fiducial|marker|f-?\d+[-_:]?)', '', label)
    label = re.sub(r'[-_\s]+', ' ', label)
    label = label.strip()
    return label


def match_structure(label, target_structures):
    """
    Check if a label matches any of the target structure names.
    Returns the matched structure name or None.
    """
    normalized = normalize_structure_name(label)
    
    # Define aliases for each structure
    aliases = {
        'liver': ['liver', 'hepatic', 'hepar'],
        'spleen': ['spleen', 'splenic', 'lien'],
        'right kidney': ['right kidney', 'r kidney', 'kidney right', 'rk', 'kidney r'],
        'left kidney': ['left kidney', 'l kidney', 'kidney left', 'lk', 'kidney l'],
        'aorta': ['aorta', 'abdominal aorta', 'ao'],
        'ivc': ['ivc', 'inferior vena cava', 'vena cava', 'cava'],
        'pancreas': ['pancreas', 'pancreatic'],
        'gallbladder': ['gallbladder', 'gall bladder', 'gb'],
        'portal vein': ['portal vein', 'portal', 'pv', 'hepatic portal']
    }
    
    for structure, alias_list in aliases.items():
        if structure in target_structures:
            for alias in alias_list:
                if alias in normalized or normalized in alias:
                    return structure
                # Also check if it starts with the alias
                if normalized.startswith(alias.split()[0]):
                    return structure
    
    return None


def ras_to_ijk(ras_point, affine):
    """Convert RAS coordinates to IJK voxel indices."""
    if np is None:
        return None
    
    ras_point = np.array(ras_point + [1.0])  # Homogeneous coordinates
    inv_affine = np.linalg.inv(affine)
    ijk = inv_affine @ ras_point
    return [int(round(ijk[i])) for i in range(3)]


def check_fiducial_in_organ(position_ras, label_volume, label_id, affine):
    """
    Check if a fiducial position falls within an organ region.
    
    Args:
        position_ras: [R, A, S] coordinates
        label_volume: 3D numpy array with organ labels
        label_id: Expected label ID for the organ
        affine: NIfTI affine transformation matrix
    
    Returns:
        bool: True if position is within the organ
    """
    if np is None or label_volume is None:
        return False
    
    try:
        ijk = ras_to_ijk(position_ras, affine)
        if ijk is None:
            return False
        
        # Check bounds
        shape = label_volume.shape
        for i, (idx, dim) in enumerate(zip(ijk, shape)):
            if idx < 0 or idx >= dim:
                return False
        
        # Check label at position
        actual_label = label_volume[ijk[0], ijk[1], ijk[2]]
        
        # Allow some tolerance - check neighboring voxels too
        if actual_label == label_id:
            return True
        
        # Check 3x3x3 neighborhood
        for dx in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                for dz in [-1, 0, 1]:
                    ni, nj, nk = ijk[0]+dx, ijk[1]+dy, ijk[2]+dz
                    if 0 <= ni < shape[0] and 0 <= nj < shape[1] and 0 <= nk < shape[2]:
                        if label_volume[ni, nj, nk] == label_id:
                            return True
        
        return False
        
    except Exception as e:
        logger.warning(f"Error checking fiducial position: {e}")
        return False


def verify_surgical_anatomy_briefing(traj, env_info, task_info):
    """
    Verify anatomical annotation task completion.
    
    Uses ground truth organ labels to verify fiducial placement accuracy.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Ensure dependencies
    if not ensure_dependencies():
        logger.warning("Running without nibabel - limited verification")
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    label_mapping = metadata.get('amos_label_mapping', {
        'liver': 6,
        'spleen': 1,
        'right kidney': 2,
        'left kidney': 3,
        'aorta': 10,
        'ivc': 9,
        'pancreas': 11,
        'gallbladder': 5,
        'portal vein': 12
    })
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {
        'structures_verified': {},
        'screenshots_checked': {},
        'fiducials_found': []
    }
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/anatomy_task_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # Load fiducials data
    # ================================================================
    fiducials = []
    temp_fid = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fiducials_export.json", temp_fid.name)
        with open(temp_fid.name, 'r') as f:
            fid_data = json.load(f)
            fiducials = fid_data.get('fiducials', [])
    except Exception as e:
        logger.warning(f"Could not load fiducials export: {e}")
        # Try loading markup JSON directly
        try:
            copy_from_env("/tmp/anatomical_landmarks.mrk.json", temp_fid.name)
            with open(temp_fid.name, 'r') as f:
                mrk_data = json.load(f)
                # Parse Slicer markup JSON format
                if 'markups' in mrk_data:
                    for markup in mrk_data['markups']:
                        control_points = markup.get('controlPoints', [])
                        for cp in control_points:
                            fiducials.append({
                                'label': cp.get('label', ''),
                                'position_ras': cp.get('position', [0, 0, 0])
                            })
        except Exception as e2:
            logger.warning(f"Could not load markup JSON: {e2}")
    finally:
        if os.path.exists(temp_fid.name):
            os.unlink(temp_fid.name)
    
    details['fiducials_found'] = [f.get('label', 'unlabeled') for f in fiducials]
    
    # ================================================================
    # Load ground truth labels for position verification
    # ================================================================
    label_volume = None
    affine = None
    
    if NIBABEL_AVAILABLE:
        temp_labels = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        try:
            copy_from_env("/tmp/gt_labels.nii.gz", temp_labels.name)
            label_img = nib.load(temp_labels.name)
            label_volume = np.asarray(label_img.dataobj).astype(np.int32)
            affine = label_img.affine
            logger.info(f"Loaded ground truth labels: shape={label_volume.shape}")
        except Exception as e:
            logger.warning(f"Could not load ground truth labels: {e}")
        finally:
            if os.path.exists(temp_labels.name):
                os.unlink(temp_labels.name)
    
    # ================================================================
    # VERIFY FIDUCIAL PLACEMENTS
    # ================================================================
    required_structures = ['liver', 'spleen', 'right kidney', 'left kidney', 
                          'aorta', 'ivc', 'pancreas']
    optional_structures = ['gallbladder', 'portal vein']
    
    structure_scores = {
        'liver': weights.get('liver_fiducial', 10),
        'spleen': weights.get('spleen_fiducial', 10),
        'right kidney': weights.get('right_kidney_fiducial', 10),
        'left kidney': weights.get('left_kidney_fiducial', 10),
        'aorta': weights.get('aorta_fiducial', 8),
        'ivc': weights.get('ivc_fiducial', 8),
        'pancreas': weights.get('pancreas_fiducial', 8),
    }
    
    verified_structures = set()
    structures_with_position = {}
    
    for fid in fiducials:
        label = fid.get('label', '')
        position = fid.get('position_ras', [0, 0, 0])
        
        # Try to match this fiducial to a structure
        matched = match_structure(label, required_structures + optional_structures)
        
        if matched and matched not in verified_structures:
            # Check if position is within the organ (if ground truth available)
            position_correct = True
            if label_volume is not None and affine is not None:
                expected_label_id = label_mapping.get(matched, 0)
                if expected_label_id > 0:
                    position_correct = check_fiducial_in_organ(
                        position, label_volume, expected_label_id, affine
                    )
            
            structures_with_position[matched] = {
                'label': label,
                'position': position,
                'position_verified': position_correct
            }
            
            if position_correct:
                verified_structures.add(matched)
                if matched in structure_scores:
                    score += structure_scores[matched]
                    feedback_parts.append(f"✓ {matched.title()} correctly placed")
                elif matched in optional_structures:
                    score += weights.get('eighth_structure', 6)
                    feedback_parts.append(f"✓ {matched.title()} (8th structure) correctly placed")
            else:
                # Partial credit for labeling but wrong position
                if matched in structure_scores:
                    partial = structure_scores[matched] * 0.3
                    score += partial
                    feedback_parts.append(f"△ {matched.title()} labeled but position may be incorrect")
    
    details['structures_verified'] = {k: to_python_type(v) for k, v in structures_with_position.items()}
    
    # Check for missing structures
    for struct in required_structures:
        if struct not in verified_structures:
            feedback_parts.append(f"✗ {struct.title()} not found or incorrectly placed")
    
    # ================================================================
    # CHECK SCREENSHOTS
    # ================================================================
    screenshot_checks = {
        'axial': ('axial_screenshot_exists', 'axial_screenshot_size', 
                  '/tmp/briefing_axial.png', weights.get('axial_screenshot', 5)),
        'coronal': ('coronal_screenshot_exists', 'coronal_screenshot_size',
                   '/tmp/briefing_coronal.png', weights.get('coronal_screenshot', 5)),
        'sagittal': ('sagittal_screenshot_exists', 'sagittal_screenshot_size',
                    '/tmp/briefing_sagittal.png', weights.get('sagittal_screenshot', 5))
    }
    
    for view_name, (exists_key, size_key, path, points) in screenshot_checks.items():
        exists = result.get(exists_key, False)
        size = result.get(size_key, 0)
        
        if exists and size > 10000:  # At least 10KB
            score += points
            feedback_parts.append(f"✓ {view_name.title()} screenshot saved ({size//1024}KB)")
            details['screenshots_checked'][view_name] = {'exists': True, 'size_kb': size//1024}
        elif exists:
            score += points * 0.5
            feedback_parts.append(f"△ {view_name.title()} screenshot exists but small ({size//1024}KB)")
            details['screenshots_checked'][view_name] = {'exists': True, 'size_kb': size//1024}
        else:
            feedback_parts.append(f"✗ {view_name.title()} screenshot not found")
            details['screenshots_checked'][view_name] = {'exists': False}
    
    # ================================================================
    # CHECK FIDUCIAL FILE VALIDITY
    # ================================================================
    fiducial_count = result.get('fiducial_count', 0)
    if len(fiducials) >= 8:
        score += weights.get('fiducial_file_valid', 5)
        feedback_parts.append(f"✓ Fiducial file has {len(fiducials)} points")
    elif len(fiducials) >= 5:
        score += weights.get('fiducial_file_valid', 5) * 0.6
        feedback_parts.append(f"△ Fiducial file has {len(fiducials)} points (expected 8)")
    elif len(fiducials) > 0:
        score += weights.get('fiducial_file_valid', 5) * 0.3
        feedback_parts.append(f"△ Fiducial file has only {len(fiducials)} points")
    else:
        feedback_parts.append("✗ No fiducials found in file")
    
    # ================================================================
    # CHECK SCENE SAVED
    # ================================================================
    if result.get('scene_exists', False):
        score += weights.get('scene_saved', 5)
        feedback_parts.append("✓ Scene file saved")
    else:
        feedback_parts.append("✗ Scene file not found")
    
    # ================================================================
    # CHECK LABEL QUALITY
    # ================================================================
    # Labels should be meaningful, not just "F-1", "F-2", etc.
    generic_labels = 0
    meaningful_labels = 0
    
    for fid in fiducials:
        label = fid.get('label', '')
        normalized = normalize_structure_name(label)
        if not normalized or re.match(r'^f?-?\d+$', normalized):
            generic_labels += 1
        else:
            meaningful_labels += 1
    
    if meaningful_labels >= 6:
        score += weights.get('label_quality', 5)
        feedback_parts.append(f"✓ {meaningful_labels}/{len(fiducials)} fiducials have meaningful labels")
    elif meaningful_labels >= 3:
        score += weights.get('label_quality', 5) * 0.5
        feedback_parts.append(f"△ Only {meaningful_labels}/{len(fiducials)} fiducials have meaningful labels")
    else:
        feedback_parts.append(f"✗ Most fiducials have generic labels")
    
    details['label_quality'] = {
        'meaningful': meaningful_labels,
        'generic': generic_labels,
        'total': len(fiducials)
    }
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    score = min(int(score), max_score)
    structures_correct = len(verified_structures)
    
    # Pass criteria: at least 5 structures correctly placed AND documentation present
    key_criteria_met = (
        structures_correct >= 5 and
        (result.get('axial_screenshot_exists') or 
         result.get('coronal_screenshot_exists') or 
         result.get('sagittal_screenshot_exists'))
    )
    
    passed = score >= metadata.get('passing_threshold', 60) and key_criteria_met
    
    # Summary
    feedback_parts.insert(0, f"Score: {score}/100 | Structures verified: {structures_correct}/8")
    
    return {
        "passed": to_python_type(passed),
        "score": to_python_type(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }