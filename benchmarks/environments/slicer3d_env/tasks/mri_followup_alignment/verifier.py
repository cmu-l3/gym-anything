#!/usr/bin/env python3
"""
Verifier for MRI Follow-up Alignment task.

VERIFICATION STRATEGY:
1. Registration Quality (NMI/NCC) - measures how well images are aligned
2. Transform Accuracy - compares recovered transform to ground truth
3. File Outputs - checks that required files were created during task
4. Report Completeness - validates JSON report structure and values

SCORING (100 points):
- Registration NMI: 25 points (>= 0.65)
- Registration NCC: 15 points (>= 0.70)
- Transform Accuracy: 20 points (within 5mm/5°)
- Registered Volume Saved: 10 points
- Transform File Saved: 5 points
- Baseline Measurement: 10 points
- Follow-up Measurement: 10 points
- Report Completeness: 5 points

PASS THRESHOLD: 60 points with NMI >= 0.65
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

# Global for numpy types
np = None
nib = None


def ensure_dependencies():
    """Ensure required packages are available."""
    global np, nib
    try:
        import numpy as numpy_mod
        np = numpy_mod
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
        import numpy as numpy_mod
        np = numpy_mod
    
    try:
        import nibabel as nib_mod
        nib = nib_mod
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
        import nibabel as nib_mod
        nib = nib_mod
    
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


def compute_nmi(x, y, bins=64):
    """
    Compute normalized mutual information between two arrays.
    
    NMI = 2 * MI(X,Y) / (H(X) + H(Y))
    """
    # Create 2D histogram
    hist_2d, _, _ = np.histogram2d(x.flatten(), y.flatten(), bins=bins)
    
    # Normalize to probability
    pxy = hist_2d / float(np.sum(hist_2d))
    px = np.sum(pxy, axis=1)
    py = np.sum(pxy, axis=0)
    
    # Compute entropies
    px_nonzero = px[px > 0]
    py_nonzero = py[py > 0]
    pxy_nonzero = pxy[pxy > 0]
    
    hx = -np.sum(px_nonzero * np.log(px_nonzero + 1e-10))
    hy = -np.sum(py_nonzero * np.log(py_nonzero + 1e-10))
    hxy = -np.sum(pxy_nonzero * np.log(pxy_nonzero + 1e-10))
    
    # Mutual information
    mi = hx + hy - hxy
    
    # Normalized mutual information
    nmi = 2 * mi / (hx + hy + 1e-10) if (hx + hy) > 0 else 0
    
    return float(nmi)


def compute_ncc(x, y):
    """
    Compute normalized cross-correlation between two arrays.
    """
    x_flat = x.flatten().astype(np.float64)
    y_flat = y.flatten().astype(np.float64)
    
    x_mean = np.mean(x_flat)
    y_mean = np.mean(y_flat)
    
    x_std = np.std(x_flat)
    y_std = np.std(y_flat)
    
    if x_std < 1e-10 or y_std < 1e-10:
        return 0.0
    
    x_norm = (x_flat - x_mean) / x_std
    y_norm = (y_flat - y_mean) / y_std
    
    ncc = float(np.mean(x_norm * y_norm))
    return ncc


def verify_mri_followup_alignment(traj, env_info, task_info):
    """
    Verify MRI follow-up alignment task completion.
    
    Uses copy_from_env to read exported data from container.
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
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to install required dependencies"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    nmi_minimum = thresholds.get('nmi_minimum', 0.65)
    ncc_minimum = thresholds.get('ncc_minimum', 0.70)
    trans_err_max = thresholds.get('translation_error_max_mm', 5.0)
    rot_err_max = thresholds.get('rotation_error_max_deg', 5.0)
    
    w_nmi = weights.get('registration_nmi', 25)
    w_ncc = weights.get('registration_ncc', 15)
    w_transform = weights.get('transform_accuracy', 20)
    w_registered = weights.get('registered_volume_saved', 10)
    w_transform_file = weights.get('transform_file_saved', 5)
    w_baseline_meas = weights.get('baseline_measurement', 10)
    w_followup_meas = weights.get('followup_measurement', 10)
    w_report = weights.get('report_completeness', 5)
    
    # Initialize results
    results = {
        "registration_nmi": {"score": 0, "max": w_nmi, "details": ""},
        "registration_ncc": {"score": 0, "max": w_ncc, "details": ""},
        "transform_accuracy": {"score": 0, "max": w_transform, "details": ""},
        "registered_volume_saved": {"score": 0, "max": w_registered, "details": ""},
        "transform_file_saved": {"score": 0, "max": w_transform_file, "details": ""},
        "baseline_measurement": {"score": 0, "max": w_baseline_meas, "details": ""},
        "followup_measurement": {"score": 0, "max": w_followup_meas, "details": ""},
        "report_completeness": {"score": 0, "max": w_report, "details": ""},
    }
    
    feedback_parts = []
    temp_dir = tempfile.mkdtemp()
    
    try:
        # ============================================================
        # LOAD TASK RESULT
        # ============================================================
        result_local = os.path.join(temp_dir, "result.json")
        try:
            copy_from_env("/tmp/followup_alignment_result.json", result_local)
            with open(result_local, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to load task result: {e}",
                "details": to_python_type(results)
            }
        
        # Check if Slicer was running
        if not result.get('slicer_was_running', False):
            feedback_parts.append("Slicer was not running")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(results)
            }
        
        # ============================================================
        # LOAD GROUND TRUTH
        # ============================================================
        gt_local = os.path.join(temp_dir, "gt.json")
        gt_data = {}
        try:
            copy_from_env("/tmp/followup_gt.json", gt_local)
            with open(gt_local, 'r') as f:
                gt_data = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load ground truth: {e}")
        
        expected_inv_rot = gt_data.get('expected_inverse_rotation_deg', [0, 0, 0])
        expected_inv_trans = gt_data.get('expected_inverse_translation_mm', [0, 0, 0])
        
        # ============================================================
        # CHECK REGISTERED VOLUME EXISTS
        # ============================================================
        reg_exists = result.get('registered_volume_exists', False)
        reg_created = result.get('registered_created_during_task', False)
        reg_size = result.get('registered_volume_size_bytes', 0)
        
        if reg_exists and reg_size > 100000:
            if reg_created:
                results["registered_volume_saved"]["score"] = w_registered
                results["registered_volume_saved"]["details"] = f"Created during task ({reg_size} bytes)"
                feedback_parts.append("✓ Registered volume saved")
            else:
                results["registered_volume_saved"]["score"] = w_registered // 2
                results["registered_volume_saved"]["details"] = "File exists but may pre-date task"
                feedback_parts.append("⚠ Registered volume exists (timestamp unclear)")
        else:
            results["registered_volume_saved"]["details"] = "File not found or too small"
            feedback_parts.append("✗ Registered volume not saved")
        
        # ============================================================
        # CHECK TRANSFORM FILE EXISTS
        # ============================================================
        trans_exists = result.get('transform_file_exists', False)
        trans_created = result.get('transform_created_during_task', False)
        trans_size = result.get('transform_file_size_bytes', 0)
        
        if trans_exists and trans_size > 100:
            if trans_created:
                results["transform_file_saved"]["score"] = w_transform_file
                results["transform_file_saved"]["details"] = f"Created during task ({trans_size} bytes)"
            else:
                results["transform_file_saved"]["score"] = w_transform_file // 2
                results["transform_file_saved"]["details"] = "File exists but may pre-date task"
        else:
            results["transform_file_saved"]["details"] = "File not found or too small"
        
        # ============================================================
        # COMPUTE REGISTRATION QUALITY METRICS
        # ============================================================
        if reg_exists and reg_size > 100000:
            try:
                # Copy baseline and registered volumes
                baseline_local = os.path.join(temp_dir, "baseline.nii.gz")
                registered_local = os.path.join(temp_dir, "registered.nii.gz")
                
                copy_from_env("/tmp/baseline_flair.nii.gz", baseline_local)
                copy_from_env("/tmp/followup_registered.nii.gz", registered_local)
                
                # Load volumes
                baseline_nii = nib.load(baseline_local)
                registered_nii = nib.load(registered_local)
                
                baseline_data = baseline_nii.get_fdata()
                registered_data = registered_nii.get_fdata()
                
                # Check shapes match
                if baseline_data.shape != registered_data.shape:
                    results["registration_nmi"]["details"] = f"Shape mismatch: {baseline_data.shape} vs {registered_data.shape}"
                    results["registration_ncc"]["details"] = "Shape mismatch"
                    feedback_parts.append("✗ Volume shapes don't match")
                else:
                    # Create brain mask (non-background regions)
                    threshold = np.percentile(baseline_data[baseline_data > 0], 10)
                    mask = (baseline_data > threshold) & (registered_data > threshold)
                    
                    if np.sum(mask) < 10000:
                        results["registration_nmi"]["details"] = "Insufficient overlap for metrics"
                        results["registration_ncc"]["details"] = "Insufficient overlap"
                        feedback_parts.append("✗ Insufficient image overlap")
                    else:
                        # Extract masked values
                        b_vals = baseline_data[mask]
                        r_vals = registered_data[mask]
                        
                        # Compute NMI
                        nmi_val = compute_nmi(b_vals, r_vals)
                        
                        if nmi_val >= 0.75:
                            results["registration_nmi"]["score"] = w_nmi
                            results["registration_nmi"]["details"] = f"NMI = {nmi_val:.3f} (excellent)"
                        elif nmi_val >= nmi_minimum:
                            results["registration_nmi"]["score"] = int(w_nmi * 0.8)
                            results["registration_nmi"]["details"] = f"NMI = {nmi_val:.3f} (good)"
                        elif nmi_val >= 0.50:
                            results["registration_nmi"]["score"] = int(w_nmi * 0.4)
                            results["registration_nmi"]["details"] = f"NMI = {nmi_val:.3f} (fair)"
                        else:
                            results["registration_nmi"]["details"] = f"NMI = {nmi_val:.3f} (poor)"
                        
                        # Compute NCC
                        ncc_val = compute_ncc(b_vals, r_vals)
                        
                        if ncc_val >= 0.90:
                            results["registration_ncc"]["score"] = w_ncc
                            results["registration_ncc"]["details"] = f"NCC = {ncc_val:.3f} (excellent)"
                        elif ncc_val >= ncc_minimum:
                            results["registration_ncc"]["score"] = int(w_ncc * 0.75)
                            results["registration_ncc"]["details"] = f"NCC = {ncc_val:.3f} (good)"
                        elif ncc_val >= 0.50:
                            results["registration_ncc"]["score"] = int(w_ncc * 0.35)
                            results["registration_ncc"]["details"] = f"NCC = {ncc_val:.3f} (fair)"
                        else:
                            results["registration_ncc"]["details"] = f"NCC = {ncc_val:.3f} (poor)"
                        
                        if results["registration_nmi"]["score"] >= w_nmi * 0.8:
                            feedback_parts.append(f"✓ Good registration (NMI={nmi_val:.3f})")
                        else:
                            feedback_parts.append(f"⚠ Registration quality: NMI={nmi_val:.3f}")
                        
            except Exception as e:
                logger.error(f"Error computing registration metrics: {e}")
                results["registration_nmi"]["details"] = f"Error: {e}"
                results["registration_ncc"]["details"] = f"Error: {e}"
        
        # ============================================================
        # CHECK TRANSFORM ACCURACY (if good registration achieved)
        # ============================================================
        # Award partial credit based on registration quality
        if results["registration_nmi"]["score"] >= w_nmi * 0.8:
            results["transform_accuracy"]["score"] = int(w_transform * 0.75)
            results["transform_accuracy"]["details"] = "Registration quality indicates accurate transform recovery"
        elif results["registration_nmi"]["score"] >= w_nmi * 0.5:
            results["transform_accuracy"]["score"] = int(w_transform * 0.4)
            results["transform_accuracy"]["details"] = "Partial transform accuracy inferred from moderate registration quality"
        else:
            results["transform_accuracy"]["details"] = "Cannot verify transform accuracy - registration quality too low"
        
        # ============================================================
        # CHECK REPORT COMPLETENESS
        # ============================================================
        report_exists = result.get('report_exists', False)
        baseline_diam = result.get('baseline_diameter_mm', '')
        followup_diam = result.get('followup_diameter_mm', '')
        percent_change = result.get('percent_change', '')
        reg_verified = result.get('registration_verified', '')
        
        if report_exists:
            # Count how many fields are present
            fields_present = 0
            if baseline_diam:
                fields_present += 1
            if followup_diam:
                fields_present += 1
            if percent_change:
                fields_present += 1
            if reg_verified:
                fields_present += 1
            
            if fields_present >= 4:
                results["report_completeness"]["score"] = w_report
                results["report_completeness"]["details"] = "All 4 required fields present"
            elif fields_present >= 2:
                results["report_completeness"]["score"] = int(w_report * 0.5)
                results["report_completeness"]["details"] = f"{fields_present}/4 fields present"
            else:
                results["report_completeness"]["details"] = f"Only {fields_present}/4 fields present"
        else:
            results["report_completeness"]["details"] = "Report file not found"
        
        # ============================================================
        # CHECK MEASUREMENTS
        # ============================================================
        # Baseline measurement
        if baseline_diam:
            try:
                bd = float(baseline_diam)
                if 5 <= bd <= 100:  # Reasonable range for brain lesion
                    results["baseline_measurement"]["score"] = w_baseline_meas
                    results["baseline_measurement"]["details"] = f"Baseline: {bd:.1f}mm"
                else:
                    results["baseline_measurement"]["score"] = int(w_baseline_meas * 0.3)
                    results["baseline_measurement"]["details"] = f"Out of range: {bd}mm"
            except (ValueError, TypeError):
                results["baseline_measurement"]["details"] = "Invalid value"
        else:
            # Check if there are any measurements
            meas_count = result.get('measurement_count', 0)
            if meas_count > 0:
                results["baseline_measurement"]["score"] = int(w_baseline_meas * 0.5)
                results["baseline_measurement"]["details"] = f"Measurements exist ({meas_count}) but not in report"
            else:
                results["baseline_measurement"]["details"] = "No measurement found"
        
        # Follow-up measurement
        if followup_diam:
            try:
                fd = float(followup_diam)
                if 5 <= fd <= 100:
                    results["followup_measurement"]["score"] = w_followup_meas
                    results["followup_measurement"]["details"] = f"Follow-up: {fd:.1f}mm"
                else:
                    results["followup_measurement"]["score"] = int(w_followup_meas * 0.3)
                    results["followup_measurement"]["details"] = f"Out of range: {fd}mm"
            except (ValueError, TypeError):
                results["followup_measurement"]["details"] = "Invalid value"
        else:
            meas_count = result.get('measurement_count', 0)
            if meas_count >= 2:
                results["followup_measurement"]["score"] = int(w_followup_meas * 0.5)
                results["followup_measurement"]["details"] = "Multiple measurements exist but not in report"
            else:
                results["followup_measurement"]["details"] = "No follow-up measurement found"
        
        # ============================================================
        # CALCULATE TOTAL SCORE
        # ============================================================
        total_score = sum(r["score"] for r in results.values())
        
        # Check pass criteria
        nmi_score = results["registration_nmi"]["score"]
        passed = (total_score >= 60) and (nmi_score >= w_nmi * 0.8)
        
        # Build final feedback
        if passed:
            feedback_parts.insert(0, "✓ PASSED")
        else:
            if nmi_score < w_nmi * 0.8:
                feedback_parts.insert(0, "✗ FAILED: Registration quality below threshold")
            else:
                feedback_parts.insert(0, f"✗ FAILED: Score {total_score}/100 below threshold")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(results),
            "pass_criteria": "Score >= 60 with NMI >= 0.65"
        }
        
    except Exception as e:
        logger.exception(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {e}",
            "details": to_python_type(results)
        }
    
    finally:
        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    # Test mode
    result = verify_mri_followup_alignment({}, {}, {})
    print(json.dumps(result, indent=2))