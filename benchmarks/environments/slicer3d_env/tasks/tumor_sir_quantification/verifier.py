#!/usr/bin/env python3
"""
Verifier for Tumor Signal Intensity Ratio (SIR) Quantification task.

VERIFICATION STRATEGY:
1. ROI Placement Validation - check if ROIs are in correct anatomical locations
2. SIR Calculation Plausibility - verify SIR values are physiologically reasonable
3. Report Completeness - check for required fields and interpretation
4. Anti-gaming - verify files were created during task

SCORING (100 points):
- Tumor ROI placement: 20 points (overlaps with tumor region)
- White matter ROI placement: 20 points (contralateral, no tumor)
- T1ce SIR plausibility: 15 points (expected 1.1-3.5)
- T2 SIR plausibility: 10 points (expected 1.2-4.5)
- FLAIR SIR plausibility: 10 points (expected 1.2-4.5)
- T1 SIR plausibility: 5 points (expected 0.6-1.3)
- ROI files saved: 10 points
- Report completeness: 10 points
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Optional dependencies
nib = None
NIBABEL_AVAILABLE = False

try:
    import nibabel as nib
    NIBABEL_AVAILABLE = True
except ImportError:
    logger.warning("nibabel not available - will try to install")


def ensure_dependencies():
    """Ensure required packages are available."""
    global NIBABEL_AVAILABLE, nib
    if not NIBABEL_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
            import nibabel as nib_module
            nib = nib_module
            NIBABEL_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install nibabel: {e}")
            return False
    return True


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


def ras_to_ijk(ras_coords, affine):
    """Convert RAS coordinates to IJK voxel indices."""
    inv_affine = np.linalg.inv(affine)
    ras_homogeneous = np.array(list(ras_coords) + [1.0])
    ijk_homogeneous = inv_affine @ ras_homogeneous
    return ijk_homogeneous[:3].astype(int)


def check_roi_in_region(roi_center_ras, roi_radius, seg_data, affine, target_labels, min_overlap=0.3):
    """
    Check if ROI overlaps with specified segmentation labels.
    
    Args:
        roi_center_ras: ROI center in RAS coordinates
        roi_radius: ROI radius (scalar or xyz)
        seg_data: Segmentation volume data
        affine: Affine transformation matrix
        target_labels: List of label values to check overlap with
        min_overlap: Minimum fraction of ROI that should overlap
        
    Returns:
        tuple: (overlap_fraction, is_valid)
    """
    try:
        # Convert RAS to IJK
        center_ijk = ras_to_ijk(roi_center_ras, affine)
        
        # Handle radius (could be scalar or array)
        if isinstance(roi_radius, (list, tuple, np.ndarray)):
            radius_vox = int(np.mean(roi_radius) / np.mean(np.abs(np.diag(affine)[:3])))
        else:
            radius_vox = int(roi_radius / np.mean(np.abs(np.diag(affine)[:3])))
        
        radius_vox = max(1, min(radius_vox, 20))  # Clamp to reasonable range
        
        # Create a spherical mask around the center
        x, y, z = center_ijk
        shape = seg_data.shape
        
        # Bounds check
        x = max(0, min(x, shape[0]-1))
        y = max(0, min(y, shape[1]-1))
        z = max(0, min(z, shape[2]-1))
        
        # Sample within radius
        total_voxels = 0
        overlapping_voxels = 0
        
        for dx in range(-radius_vox, radius_vox + 1):
            for dy in range(-radius_vox, radius_vox + 1):
                for dz in range(-radius_vox, radius_vox + 1):
                    if dx*dx + dy*dy + dz*dz <= radius_vox*radius_vox:
                        nx, ny, nz = x + dx, y + dy, z + dz
                        if 0 <= nx < shape[0] and 0 <= ny < shape[1] and 0 <= nz < shape[2]:
                            total_voxels += 1
                            if seg_data[nx, ny, nz] in target_labels:
                                overlapping_voxels += 1
        
        if total_voxels == 0:
            return 0.0, False
            
        overlap_fraction = overlapping_voxels / total_voxels
        return overlap_fraction, overlap_fraction >= min_overlap
        
    except Exception as e:
        logger.warning(f"Error checking ROI overlap: {e}")
        return 0.0, False


def check_contralateral(roi1_ras, roi2_ras, seg_shape, affine):
    """
    Check if two ROIs are in contralateral hemispheres.
    
    Args:
        roi1_ras: First ROI center in RAS coordinates
        roi2_ras: Second ROI center in RAS coordinates
        seg_shape: Shape of the segmentation volume
        affine: Affine transformation matrix
        
    Returns:
        bool: True if ROIs are in opposite hemispheres
    """
    try:
        ijk1 = ras_to_ijk(roi1_ras, affine)
        ijk2 = ras_to_ijk(roi2_ras, affine)
        
        # In most brain scans, the x-axis (first dimension after standard orientation)
        # separates left and right hemispheres
        midpoint = seg_shape[0] // 2
        
        # Check if on opposite sides of midline
        roi1_side = ijk1[0] < midpoint
        roi2_side = ijk2[0] < midpoint
        
        return roi1_side != roi2_side
        
    except Exception as e:
        logger.warning(f"Error checking contralateral: {e}")
        return False


def verify_sir_plausibility(sir_value, expected_range, sequence_name):
    """
    Check if SIR value is within physiologically plausible range.
    
    Returns:
        tuple: (is_plausible, score_fraction, feedback)
    """
    if sir_value is None or sir_value == "":
        return False, 0.0, f"{sequence_name}: No SIR value provided"
    
    try:
        sir = float(sir_value)
        min_val, max_val = expected_range
        
        if min_val <= sir <= max_val:
            return True, 1.0, f"{sequence_name} SIR={sir:.2f} (plausible)"
        elif sir > 0:
            # Partially plausible - outside range but reasonable
            return False, 0.3, f"{sequence_name} SIR={sir:.2f} (outside expected {min_val}-{max_val})"
        else:
            return False, 0.0, f"{sequence_name} SIR={sir:.2f} (invalid)"
            
    except (ValueError, TypeError):
        return False, 0.0, f"{sequence_name}: Invalid SIR value '{sir_value}'"


def verify_tumor_sir_quantification(traj, env_info, task_info):
    """
    Verify tumor signal intensity ratio quantification task.
    
    Uses multiple independent signals to prevent gaming:
    1. ROI file existence and creation time
    2. Report file existence and creation time
    3. ROI placement validation against ground truth segmentation
    4. SIR value plausibility checks
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
    expected_sir_ranges = metadata.get('expected_sir_ranges', {
        "t1": [0.6, 1.3],
        "t1ce": [1.1, 3.5],
        "t2": [1.2, 4.5],
        "flair": [1.2, 4.5]
    })
    weights = metadata.get('scoring_weights', {})
    tumor_labels = metadata.get('tumor_labels', {"necrotic": 1, "edema": 2, "enhancing": 4})
    
    # Default weights
    w_tumor_roi = weights.get('tumor_roi_placement', 20)
    w_wm_roi = weights.get('wm_roi_placement', 20)
    w_t1ce = weights.get('t1ce_sir_accuracy', 15)
    w_t2 = weights.get('t2_sir_accuracy', 10)
    w_flair = weights.get('flair_sir_accuracy', 10)
    w_t1 = weights.get('t1_sir_accuracy', 5)
    w_roi_files = weights.get('roi_files_saved', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/sir_task_result.json", temp_result.name)
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
    
    # ================================================================
    # LOAD GROUND TRUTH SEGMENTATION
    # ================================================================
    seg_data = None
    seg_affine = None
    gt_loaded = False
    
    if NIBABEL_AVAILABLE:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        try:
            copy_from_env("/tmp/ground_truth_seg.nii.gz", temp_gt.name)
            gt_nii = nib.load(temp_gt.name)
            seg_data = gt_nii.get_fdata().astype(np.int32)
            seg_affine = gt_nii.affine
            gt_loaded = True
            details['gt_shape'] = list(seg_data.shape)
        except Exception as e:
            logger.warning(f"Could not load ground truth segmentation: {e}")
            details['gt_load_error'] = str(e)
        finally:
            if os.path.exists(temp_gt.name):
                os.unlink(temp_gt.name)
    
    # ================================================================
    # LOAD AGENT ROI DATA
    # ================================================================
    roi_data = {}
    temp_roi = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_rois.json", temp_roi.name)
        with open(temp_roi.name, 'r') as f:
            roi_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load agent ROI data: {e}")
        details['roi_load_error'] = str(e)
    finally:
        if os.path.exists(temp_roi.name):
            os.unlink(temp_roi.name)
    
    # ================================================================
    # LOAD AGENT REPORT
    # ================================================================
    report_data = {}
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load agent report: {e}")
        details['report_load_error'] = str(e)
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # ================================================================
    # CRITERION 1: ROI FILES SAVED (10 points)
    # ================================================================
    roi_exists = result.get('roi_file_exists', False)
    roi_created = result.get('roi_created_during_task', False)
    
    if roi_exists and roi_created:
        score += w_roi_files
        feedback_parts.append(f"✓ ROI file created during task (+{w_roi_files})")
    elif roi_exists:
        score += w_roi_files // 2
        feedback_parts.append(f"~ ROI file exists but may be pre-existing (+{w_roi_files // 2})")
    else:
        feedback_parts.append("✗ ROI file not found")
    
    details['roi_file_exists'] = roi_exists
    details['roi_created_during_task'] = roi_created
    
    # ================================================================
    # CRITERION 2: TUMOR ROI PLACEMENT (20 points)
    # ================================================================
    tumor_roi_valid = False
    tumor_roi_center = None
    tumor_roi_radius = 5.0  # Default radius
    
    # Try to extract tumor ROI from data
    rois_list = roi_data.get('rois', [])
    for roi in rois_list:
        name = roi.get('name', '').lower()
        if 'tumor' in name or 'lesion' in name or 'enhancing' in name:
            tumor_roi_center = roi.get('center_ras')
            if 'radius_xyz' in roi:
                tumor_roi_radius = np.mean(roi['radius_xyz'])
            break
    
    # Also check report for tumor ROI info
    if tumor_roi_center is None and 'tumor_roi' in report_data:
        tumor_roi_info = report_data['tumor_roi']
        if 'center_ijk' in tumor_roi_info:
            # Convert IJK to RAS if we have affine
            tumor_roi_center = tumor_roi_info.get('center_ras', tumor_roi_info.get('center_ijk'))
        tumor_roi_radius = tumor_roi_info.get('radius_mm', 5.0)
    
    # If no specific tumor ROI found, use first ROI
    if tumor_roi_center is None and len(rois_list) > 0:
        tumor_roi_center = rois_list[0].get('center_ras')
        if 'radius_xyz' in rois_list[0]:
            tumor_roi_radius = np.mean(rois_list[0]['radius_xyz'])
    
    if tumor_roi_center is not None and gt_loaded and seg_data is not None:
        # Check overlap with tumor labels (1, 2, 4)
        all_tumor_labels = list(tumor_labels.values())
        overlap_frac, is_valid = check_roi_in_region(
            tumor_roi_center, tumor_roi_radius, seg_data, seg_affine,
            all_tumor_labels, min_overlap=0.3
        )
        details['tumor_roi_overlap'] = to_python_type(overlap_frac)
        
        if is_valid:
            tumor_roi_valid = True
            score += w_tumor_roi
            feedback_parts.append(f"✓ Tumor ROI placed in tumor region ({overlap_frac:.0%} overlap, +{w_tumor_roi})")
        elif overlap_frac > 0:
            partial_score = int(w_tumor_roi * overlap_frac)
            score += partial_score
            feedback_parts.append(f"~ Tumor ROI partially in tumor ({overlap_frac:.0%} overlap, +{partial_score})")
        else:
            feedback_parts.append("✗ Tumor ROI not in tumor region")
    elif tumor_roi_center is not None:
        # Can't validate without ground truth, give partial credit
        score += w_tumor_roi // 2
        tumor_roi_valid = True  # Assume valid for SIR checking
        feedback_parts.append(f"~ Tumor ROI placed (cannot validate without GT, +{w_tumor_roi // 2})")
    else:
        feedback_parts.append("✗ No tumor ROI found")
    
    details['tumor_roi_center'] = to_python_type(tumor_roi_center) if tumor_roi_center else None
    
    # ================================================================
    # CRITERION 3: WHITE MATTER ROI PLACEMENT (20 points)
    # ================================================================
    wm_roi_valid = False
    wm_roi_center = None
    wm_roi_radius = 5.0
    
    # Try to extract WM ROI from data
    for roi in rois_list:
        name = roi.get('name', '').lower()
        if 'white' in name or 'wm' in name or 'normal' in name or 'contralateral' in name:
            wm_roi_center = roi.get('center_ras')
            if 'radius_xyz' in roi:
                wm_roi_radius = np.mean(roi['radius_xyz'])
            break
    
    # Also check report for WM ROI info
    if wm_roi_center is None and 'wm_roi' in report_data:
        wm_roi_info = report_data['wm_roi']
        wm_roi_center = wm_roi_info.get('center_ras', wm_roi_info.get('center_ijk'))
        wm_roi_radius = wm_roi_info.get('radius_mm', 5.0)
    
    # If no specific WM ROI found, use second ROI
    if wm_roi_center is None and len(rois_list) > 1:
        wm_roi_center = rois_list[1].get('center_ras')
        if 'radius_xyz' in rois_list[1]:
            wm_roi_radius = np.mean(rois_list[1]['radius_xyz'])
    
    if wm_roi_center is not None and gt_loaded and seg_data is not None:
        # Check that WM ROI does NOT overlap with tumor
        all_tumor_labels = list(tumor_labels.values())
        overlap_frac, overlaps_tumor = check_roi_in_region(
            wm_roi_center, wm_roi_radius, seg_data, seg_affine,
            all_tumor_labels, min_overlap=0.1
        )
        details['wm_roi_tumor_overlap'] = to_python_type(overlap_frac)
        
        # Check contralateral placement
        is_contralateral = False
        if tumor_roi_center is not None:
            is_contralateral = check_contralateral(
                tumor_roi_center, wm_roi_center, seg_data.shape, seg_affine
            )
        details['wm_roi_contralateral'] = is_contralateral
        
        if not overlaps_tumor and is_contralateral:
            wm_roi_valid = True
            score += w_wm_roi
            feedback_parts.append(f"✓ WM ROI placed contralaterally, no tumor overlap (+{w_wm_roi})")
        elif not overlaps_tumor:
            score += int(w_wm_roi * 0.7)
            wm_roi_valid = True
            feedback_parts.append(f"~ WM ROI no tumor overlap but not clearly contralateral (+{int(w_wm_roi * 0.7)})")
        else:
            feedback_parts.append(f"✗ WM ROI overlaps with tumor ({overlap_frac:.0%})")
    elif wm_roi_center is not None:
        score += w_wm_roi // 2
        wm_roi_valid = True
        feedback_parts.append(f"~ WM ROI placed (cannot validate without GT, +{w_wm_roi // 2})")
    else:
        feedback_parts.append("✗ No white matter ROI found")
    
    details['wm_roi_center'] = to_python_type(wm_roi_center) if wm_roi_center else None
    
    # ================================================================
    # CRITERION 4-7: SIR VALUE PLAUSIBILITY (40 points total)
    # ================================================================
    sir_values = result.get('sir_values', {})
    
    # Also check report for SIR values
    if not any(sir_values.values()):
        sir_values = report_data.get('sir_values', {})
    
    details['sir_values_raw'] = sir_values
    
    sir_checks = [
        ('t1ce', expected_sir_ranges.get('t1ce', [1.1, 3.5]), w_t1ce),
        ('t2', expected_sir_ranges.get('t2', [1.2, 4.5]), w_t2),
        ('flair', expected_sir_ranges.get('flair', [1.2, 4.5]), w_flair),
        ('t1', expected_sir_ranges.get('t1', [0.6, 1.3]), w_t1),
    ]
    
    plausible_count = 0
    for seq_name, expected_range, weight in sir_checks:
        # Try multiple key formats
        sir_val = sir_values.get(seq_name) or sir_values.get(seq_name.upper()) or sir_values.get(f't1_contrast' if seq_name == 't1ce' else seq_name)
        
        is_plausible, score_frac, fb = verify_sir_plausibility(sir_val, expected_range, seq_name.upper())
        
        points = int(weight * score_frac)
        score += points
        
        if is_plausible:
            plausible_count += 1
            feedback_parts.append(f"✓ {fb} (+{points})")
        elif score_frac > 0:
            feedback_parts.append(f"~ {fb} (+{points})")
        else:
            feedback_parts.append(f"✗ {fb}")
        
        details[f'{seq_name}_sir_plausible'] = is_plausible
    
    details['plausible_sir_count'] = plausible_count
    
    # ================================================================
    # CRITERION 8: REPORT COMPLETENESS (10 points)
    # ================================================================
    report_exists = result.get('report_file_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    required_fields = ['sir_values', 'tumor_roi', 'wm_roi', 'interpretation']
    fields_present = sum(1 for f in required_fields if f in report_data and report_data[f])
    
    if report_exists and report_created:
        if fields_present == len(required_fields):
            score += w_report
            feedback_parts.append(f"✓ Report complete with all fields (+{w_report})")
        elif fields_present > 0:
            partial = int(w_report * fields_present / len(required_fields))
            score += partial
            feedback_parts.append(f"~ Report has {fields_present}/{len(required_fields)} required fields (+{partial})")
        else:
            feedback_parts.append("✗ Report missing required fields")
    elif report_exists:
        score += w_report // 2
        feedback_parts.append(f"~ Report exists but may be pre-existing (+{w_report // 2})")
    else:
        feedback_parts.append("✗ Report file not found")
    
    details['report_fields_present'] = fields_present
    details['report_created_during_task'] = report_created
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Pass requires:
    # - At least one ROI placed correctly (tumor or WM)
    # - At least 2 plausible SIR values
    # - Score >= 60
    
    key_criteria_met = (tumor_roi_valid or wm_roi_valid) and plausible_count >= 2
    passed = score >= 60 and key_criteria_met
    
    # Compile feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED (score={score}/100) - " + feedback
    else:
        reasons = []
        if score < 60:
            reasons.append(f"score {score} < 60")
        if not (tumor_roi_valid or wm_roi_valid):
            reasons.append("no valid ROI placement")
        if plausible_count < 2:
            reasons.append(f"only {plausible_count} plausible SIR values")
        feedback = f"FAILED ({', '.join(reasons)}) - " + feedback
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": feedback,
        "details": to_python_type(details)
    }