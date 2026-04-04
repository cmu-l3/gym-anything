#!/usr/bin/env python3
"""
Verifier for Multi-Modal Tumor Localization task.

VERIFICATION STRATEGY:
1. Check if markup file exists and is valid (10 points)
2. Check if fiducial point is inside the ground truth tumor region (30 points)
3. Check distance from fiducial to tumor centroid (25 + 10 bonus points)
4. Check if report exists (10 points)
5. Check if report has valid RAS coordinates (5 points)
6. Check if report has modality observations (5 points)
7. Check if report coordinates match markup (5 points)

Pass threshold: 65 points AND point inside tumor
"""

import json
import os
import sys
import tempfile
import shutil
import logging
from typing import Tuple, Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import optional dependencies
HAS_NUMPY = False
HAS_NIBABEL = False

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    pass

try:
    import nibabel as nib
    HAS_NIBABEL = True
except ImportError:
    pass


def ensure_dependencies():
    """Ensure required packages are available."""
    global HAS_NUMPY, HAS_NIBABEL, np, nib
    
    if not HAS_NUMPY:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
            import numpy as np_module
            np = np_module
            HAS_NUMPY = True
        except Exception as e:
            logger.error(f"Failed to install numpy: {e}")
    
    if not HAS_NIBABEL:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
            import nibabel as nib_module
            nib = nib_module
            HAS_NIBABEL = True
        except Exception as e:
            logger.error(f"Failed to install nibabel: {e}")
    
    return HAS_NUMPY and HAS_NIBABEL


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


def parse_fiducial_coords(result: Dict) -> Optional[list]:
    """Extract fiducial coordinates from result data."""
    fiducial = result.get('fiducial', {})
    try:
        r = float(fiducial.get('R', ''))
        a = float(fiducial.get('A', ''))
        s = float(fiducial.get('S', ''))
        return [r, a, s]
    except (ValueError, TypeError):
        return None


def parse_report_coords(result: Dict) -> Optional[list]:
    """Extract report coordinates from result data."""
    report = result.get('report', {})
    try:
        r = float(report.get('R', ''))
        a = float(report.get('A', ''))
        s = float(report.get('S', ''))
        return [r, a, s]
    except (ValueError, TypeError):
        return None


def verify_multimodal_tumor_localization(traj, env_info, task_info):
    """
    Verify multi-modal tumor localization task completion.
    
    Scoring (100 points total):
    - Markup file exists: 10 points
    - Point inside tumor: 30 points
    - Distance to centroid <= 15mm: 25 points
    - Distance to centroid <= 10mm: +10 bonus points
    - Report exists: 10 points
    - Report has coordinates: 5 points
    - Report has observations: 5 points
    - Coordinates match: 5 points
    
    Returns:
        dict with 'passed', 'score', 'feedback', and 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Ensure dependencies
    ensure_dependencies()
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    distance_max_mm = thresholds.get('distance_to_centroid_max_mm', 15.0)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Load result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/localization_task_result.json", temp_result.name)
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
    
    details['sample_id'] = result.get('sample_id', 'unknown')
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("❌ Slicer was not running")
    
    # ================================================================
    # CRITERION 1: Markup file exists (10 points)
    # ================================================================
    markup_exists = result.get('markup_exists', False)
    markup_valid = result.get('markup_valid', False)
    markup_created_after_start = result.get('markup_created_after_start', False)
    
    if markup_exists and markup_valid:
        score += 10
        feedback_parts.append("✅ Markup file exists and is valid")
        details['markup_exists'] = True
        
        # Check anti-gaming: file created during task
        if not markup_created_after_start:
            feedback_parts.append("⚠️ Markup may have existed before task")
            details['markup_created_during_task'] = False
        else:
            details['markup_created_during_task'] = True
    else:
        feedback_parts.append("❌ Markup file not found or invalid")
        details['markup_exists'] = False
    
    # Parse fiducial coordinates
    fiducial_coords = parse_fiducial_coords(result)
    details['fiducial_coords'] = fiducial_coords
    
    if not fiducial_coords:
        feedback_parts.append("❌ Could not parse fiducial coordinates")
        # Early return - can't do spatial verification without coordinates
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    feedback_parts.append(f"📍 Fiducial at RAS: ({fiducial_coords[0]:.1f}, {fiducial_coords[1]:.1f}, {fiducial_coords[2]:.1f})")
    
    # ================================================================
    # Load ground truth data
    # ================================================================
    gt_centroid = None
    gt_data = {}
    
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ground_truth_centroid.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
        gt_centroid = gt_data.get('centroid_ras')
        details['gt_centroid'] = gt_centroid
        details['gt_tumor_voxels'] = gt_data.get('tumor_voxel_count', 0)
    except Exception as e:
        logger.warning(f"Failed to load ground truth centroid: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # ================================================================
    # CRITERION 2: Point inside tumor (30 points)
    # ================================================================
    point_inside_tumor = False
    
    if HAS_NUMPY and HAS_NIBABEL:
        temp_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        try:
            copy_from_env("/tmp/ground_truth_seg.nii.gz", temp_seg.name)
            
            seg_nii = nib.load(temp_seg.name)
            seg_data = seg_nii.get_fdata().astype(np.int32)
            affine = seg_nii.affine
            inv_affine = np.linalg.inv(affine)
            
            # Convert RAS to voxel coordinates
            ras_coords = np.array(fiducial_coords)
            ras_homogeneous = np.append(ras_coords, 1)
            voxel_coords = inv_affine.dot(ras_homogeneous)[:3]
            voxel_indices = np.round(voxel_coords).astype(int)
            
            details['fiducial_voxel'] = voxel_indices.tolist()
            
            # Check if inside volume bounds
            in_bounds = all(0 <= voxel_indices[i] < seg_data.shape[i] for i in range(3))
            
            if in_bounds:
                label_at_point = int(seg_data[voxel_indices[0], voxel_indices[1], voxel_indices[2]])
                details['label_at_point'] = label_at_point
                
                # BraTS labels: 0=background, 1=necrotic, 2=edema, 4=enhancing
                point_inside_tumor = label_at_point > 0
                
                if point_inside_tumor:
                    score += 30
                    label_names = {1: 'necrotic core', 2: 'edema', 4: 'enhancing tumor'}
                    label_name = label_names.get(label_at_point, f'tumor region {label_at_point}')
                    feedback_parts.append(f"✅ Point inside tumor ({label_name})")
                else:
                    feedback_parts.append("❌ Point NOT inside tumor region")
            else:
                feedback_parts.append("❌ Point outside volume bounds")
                details['in_bounds'] = False
                
        except Exception as e:
            logger.error(f"Failed to verify point position: {e}")
            details['spatial_verification_error'] = str(e)
            feedback_parts.append(f"⚠️ Could not verify point position: {e}")
        finally:
            if os.path.exists(temp_seg.name):
                os.unlink(temp_seg.name)
    else:
        feedback_parts.append("⚠️ Spatial verification unavailable (missing dependencies)")
    
    details['point_inside_tumor'] = point_inside_tumor
    
    # ================================================================
    # CRITERION 3: Distance to centroid (25 + 10 bonus points)
    # ================================================================
    distance_to_centroid = float('inf')
    
    if HAS_NUMPY and gt_centroid:
        try:
            gt_centroid_arr = np.array(gt_centroid)
            fiducial_arr = np.array(fiducial_coords)
            distance_to_centroid = float(np.linalg.norm(fiducial_arr - gt_centroid_arr))
            details['distance_to_centroid_mm'] = distance_to_centroid
            details['gt_centroid_ras'] = gt_centroid
            
            feedback_parts.append(f"📏 Distance to centroid: {distance_to_centroid:.1f}mm")
            
            if distance_to_centroid <= distance_max_mm:
                score += 25
                feedback_parts.append(f"✅ Within {distance_max_mm}mm threshold")
                
                # Bonus for high precision
                if distance_to_centroid <= 10:
                    score += 10
                    feedback_parts.append("🎯 Bonus: Excellent precision (≤10mm)")
            else:
                feedback_parts.append(f"❌ Exceeds {distance_max_mm}mm threshold")
                
        except Exception as e:
            logger.error(f"Failed to calculate distance: {e}")
            details['distance_calculation_error'] = str(e)
    
    # ================================================================
    # CRITERION 4: Report exists (10 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    report_valid = result.get('report_valid', False)
    report_created_after_start = result.get('report_created_after_start', False)
    
    if report_exists:
        score += 10
        feedback_parts.append("✅ Report file exists")
        details['report_exists'] = True
        
        if not report_created_after_start:
            details['report_created_during_task'] = False
        else:
            details['report_created_during_task'] = True
    else:
        feedback_parts.append("❌ Report file not found")
        details['report_exists'] = False
    
    # ================================================================
    # CRITERION 5: Report has valid coordinates (5 points)
    # ================================================================
    report_coords = parse_report_coords(result)
    details['report_coords'] = report_coords
    
    if report_coords:
        score += 5
        feedback_parts.append("✅ Report contains RAS coordinates")
    else:
        feedback_parts.append("❌ Report missing valid coordinates")
    
    # ================================================================
    # CRITERION 6: Report has observations (5 points)
    # ================================================================
    report = result.get('report', {})
    has_observations = report.get('has_observations', False)
    has_modality = bool(report.get('modality', ''))
    
    if has_observations or has_modality:
        score += 5
        feedback_parts.append("✅ Report contains observations")
        details['has_observations'] = True
    else:
        feedback_parts.append("❌ Report missing observations")
        details['has_observations'] = False
    
    # ================================================================
    # CRITERION 7: Coordinates match (5 points)
    # ================================================================
    coords_match = False
    
    if fiducial_coords and report_coords and HAS_NUMPY:
        try:
            coord_diff = np.linalg.norm(np.array(fiducial_coords) - np.array(report_coords))
            details['coord_difference_mm'] = float(coord_diff)
            
            if coord_diff < 5:  # Within 5mm
                coords_match = True
                score += 5
                feedback_parts.append("✅ Report coordinates match markup")
            else:
                feedback_parts.append(f"⚠️ Coordinates differ by {coord_diff:.1f}mm")
        except Exception as e:
            logger.error(f"Failed to compare coordinates: {e}")
    
    details['coords_match'] = coords_match
    
    # ================================================================
    # Calculate final result
    # ================================================================
    # Pass requires: 65+ points AND point inside tumor
    passed = score >= 65 and point_inside_tumor
    
    details['score'] = score
    details['max_score'] = 100
    details['passed'] = passed
    
    # Generate summary
    if passed:
        summary = f"✅ PASSED with {score}/100 points. Tumor center correctly localized."
        if distance_to_centroid <= 10:
            summary += f" Excellent precision ({distance_to_centroid:.1f}mm from centroid)."
        elif distance_to_centroid <= 15:
            summary += f" Good precision ({distance_to_centroid:.1f}mm from centroid)."
    else:
        if not point_inside_tumor:
            summary = f"❌ FAILED ({score}/100 points). Fiducial point not inside tumor region."
        else:
            summary = f"❌ FAILED ({score}/100 points). Score below 65 threshold."
    
    feedback_parts.insert(0, summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }


if __name__ == "__main__":
    # Test run
    print("Multi-Modal Tumor Localization Verifier")
    print("Run through the task framework for actual verification")