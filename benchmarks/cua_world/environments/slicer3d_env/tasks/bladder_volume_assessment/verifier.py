#!/usr/bin/env python3
"""
Verifier for Bladder Volume Assessment task.

VERIFICATION METRICS:
1. Dice Coefficient - measures overlap between predicted and ground truth bladder
2. Volume Accuracy - compares predicted vs ground truth bladder volume
3. Clinical Classification - correctness of distension status
4. Report Completeness - all required JSON fields present
5. Anatomical Validity - single connected component, pelvic location

SCORING (100 points total):
- Dice >= 0.75: 30 points (high quality)
- Dice >= 0.5: 15 points (moderate quality) 
- Volume within 20%: 20 points
- Volume within 40%: 10 points
- Classification correct: 15 points
- Clinical significance correct: 10 points
- Report complete: 10 points
- Single connected component: 5 points
- Pelvic location: 5 points
- File exists: 5 points
"""

import json
import os
import sys
import tempfile
import shutil
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global imports for nibabel/scipy
nib = None
scipy_ndimage = None
DEPS_AVAILABLE = False


def ensure_dependencies():
    """Ensure nibabel and scipy are available."""
    global DEPS_AVAILABLE, nib, scipy_ndimage
    if DEPS_AVAILABLE:
        return True
    
    try:
        import nibabel
        from scipy import ndimage
        nib = nibabel
        scipy_ndimage = ndimage
        DEPS_AVAILABLE = True
        return True
    except ImportError:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
            import nibabel
            from scipy import ndimage
            nib = nibabel
            scipy_ndimage = ndimage
            DEPS_AVAILABLE = True
            return True
        except Exception as e:
            logger.error(f"Failed to install dependencies: {e}")
            return False


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


def dice_coefficient(pred: np.ndarray, gt: np.ndarray) -> float:
    """
    Calculate Dice coefficient between prediction and ground truth.
    
    Dice = 2 * |pred ∩ gt| / (|pred| + |gt|)
    """
    pred = pred.astype(bool)
    gt = gt.astype(bool)
    
    intersection = np.sum(pred & gt)
    sum_volumes = np.sum(pred) + np.sum(gt)
    
    if sum_volumes == 0:
        return 1.0 if np.sum(pred) == 0 and np.sum(gt) == 0 else 0.0
    
    return float(2.0 * intersection / sum_volumes)


def verify_bladder_volume_assessment(traj, env_info, task_info):
    """
    Verify bladder volume assessment task completion.
    
    Returns dict with 'passed', 'score', 'feedback', and 'details'
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
            "feedback": "Could not load required dependencies (nibabel, scipy)"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    dice_min = thresholds.get('dice_minimum', 0.5)
    vol_error_max = thresholds.get('volume_error_max_percent', 40)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    temp_dir = tempfile.mkdtemp()
    
    try:
        # ============================================================
        # Load task result JSON
        # ============================================================
        result_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/bladder_task_result.json", result_path)
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to read task result: {e}"
            }
        
        details['result'] = to_python_type(result)
        case_id = result.get('case_id', 'amos_0001')
        
        # ============================================================
        # Check 1: Segmentation file exists (5 points)
        # ============================================================
        seg_exists = result.get('segmentation_exists', False)
        seg_created = result.get('segmentation_created_during_task', False)
        
        if seg_exists:
            if seg_created:
                score += 5
                feedback_parts.append("[+5] Segmentation file exists and was created during task")
            else:
                score += 2
                feedback_parts.append("[+2] Segmentation file exists but timestamp suspicious")
        else:
            feedback_parts.append("[+0] Segmentation file NOT found")
            # Can't continue verification without segmentation
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(details)
            }
        
        # ============================================================
        # Load ground truth
        # ============================================================
        gt_json_path = os.path.join(temp_dir, "gt_info.json")
        gt_seg_path = os.path.join(temp_dir, "gt_seg.nii.gz")
        agent_seg_path = os.path.join(temp_dir, "agent_seg.nii.gz")
        
        try:
            copy_from_env("/tmp/ground_truth_bladder.json", gt_json_path)
            with open(gt_json_path, 'r') as f:
                gt_info = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load ground truth JSON: {e}")
            gt_info = {}
        
        gt_volume_ml = gt_info.get('bladder_volume_ml', 0)
        gt_classification = gt_info.get('expected_classification', '')
        gt_clinical_sig = gt_info.get('expected_clinical_significance', False)
        
        details['gt_volume_ml'] = gt_volume_ml
        details['gt_classification'] = gt_classification
        details['gt_clinical_significance'] = gt_clinical_sig
        
        # Load segmentation NIfTI files
        try:
            copy_from_env("/tmp/ground_truth_bladder.nii.gz", gt_seg_path)
            copy_from_env("/tmp/agent_bladder_segmentation.nii.gz", agent_seg_path)
        except Exception as e:
            logger.warning(f"Failed to copy segmentation files: {e}")
            feedback_parts.append(f"[+0] Could not load segmentation files: {e}")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(details)
            }
        
        # Load NIfTI data
        try:
            agent_nii = nib.load(agent_seg_path)
            agent_data = agent_nii.get_fdata()
            agent_binary = (agent_data > 0).astype(np.uint8)
            
            gt_nii = nib.load(gt_seg_path)
            gt_data = gt_nii.get_fdata()
            gt_binary = (gt_data > 0).astype(np.uint8)
            
            spacing = agent_nii.header.get_zooms()[:3]
            voxel_volume_mm3 = float(np.prod(spacing))
        except Exception as e:
            feedback_parts.append(f"[+0] Failed to parse NIfTI files: {e}")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(details)
            }
        
        details['agent_seg_shape'] = list(agent_data.shape)
        details['gt_seg_shape'] = list(gt_data.shape)
        details['voxel_spacing_mm'] = [float(s) for s in spacing]
        
        # ============================================================
        # Check 2: Single connected component (5 points)
        # ============================================================
        from scipy.ndimage import label as scipy_label
        labeled_arr, n_components = scipy_label(agent_binary)
        details['n_components'] = int(n_components)
        
        if n_components == 1:
            score += 5
            feedback_parts.append("[+5] Segmentation is a single connected component")
        elif n_components > 1:
            # Keep only largest component for further analysis
            component_sizes = [np.sum(labeled_arr == i) for i in range(1, n_components + 1)]
            largest = np.argmax(component_sizes) + 1
            agent_binary = (labeled_arr == largest).astype(np.uint8)
            feedback_parts.append(f"[+0] Segmentation has {n_components} components (using largest)")
        else:
            feedback_parts.append("[+0] Segmentation appears empty")
        
        # ============================================================
        # Check 3: Pelvic location (5 points)
        # ============================================================
        if np.any(agent_binary):
            coords = np.argwhere(agent_binary)
            centroid = coords.mean(axis=0)
            shape = agent_binary.shape
            
            z_fraction = centroid[2] / shape[2] if shape[2] > 0 else 0
            x_fraction = centroid[0] / shape[0] if shape[0] > 0 else 0
            y_fraction = centroid[1] / shape[1] if shape[1] > 0 else 0
            
            details['centroid_fractions'] = {
                'x': round(float(x_fraction), 3),
                'y': round(float(y_fraction), 3),
                'z': round(float(z_fraction), 3)
            }
            
            # Pelvis is in lower portion of abdominal CT (z < 0.4 typically)
            # and roughly central in x/y
            in_pelvis = z_fraction < 0.5
            is_central = 0.2 < x_fraction < 0.8 and 0.15 < y_fraction < 0.85
            
            if in_pelvis and is_central:
                score += 5
                feedback_parts.append(f"[+5] Segmentation centroid in pelvic region (z={z_fraction:.2f})")
            elif in_pelvis or is_central:
                score += 2
                feedback_parts.append(f"[+2] Segmentation partially in expected region (z={z_fraction:.2f})")
            else:
                feedback_parts.append(f"[+0] Segmentation outside expected pelvic region (z={z_fraction:.2f})")
        else:
            feedback_parts.append("[+0] Cannot verify location - empty segmentation")
        
        # ============================================================
        # Check 4: Dice coefficient (up to 30 points)
        # ============================================================
        dice = dice_coefficient(agent_binary, gt_binary)
        details['dice_coefficient'] = round(float(dice), 4)
        
        if dice >= 0.75:
            score += 30
            feedback_parts.append(f"[+30] Excellent Dice coefficient: {dice:.3f} (>= 0.75)")
        elif dice >= 0.5:
            score += 15
            feedback_parts.append(f"[+15] Moderate Dice coefficient: {dice:.3f} (>= 0.5)")
        elif dice >= 0.3:
            score += 5
            feedback_parts.append(f"[+5] Low Dice coefficient: {dice:.3f} (>= 0.3)")
        else:
            feedback_parts.append(f"[+0] Very low Dice coefficient: {dice:.3f} (< 0.3)")
        
        # ============================================================
        # Check 5: Volume accuracy (up to 20 points)
        # ============================================================
        agent_volume_ml = np.sum(agent_binary) * voxel_volume_mm3 / 1000.0
        details['agent_volume_ml'] = round(float(agent_volume_ml), 1)
        
        if gt_volume_ml > 0:
            volume_error = abs(agent_volume_ml - gt_volume_ml) / gt_volume_ml
            details['volume_error_percent'] = round(float(volume_error * 100), 1)
            
            if volume_error <= 0.20:
                score += 20
                feedback_parts.append(f"[+20] Volume accurate within 20%: {agent_volume_ml:.1f} mL (GT: {gt_volume_ml:.1f} mL)")
            elif volume_error <= 0.40:
                score += 10
                feedback_parts.append(f"[+10] Volume within 40%: {agent_volume_ml:.1f} mL (GT: {gt_volume_ml:.1f} mL)")
            else:
                feedback_parts.append(f"[+0] Volume error too high: {agent_volume_ml:.1f} mL (GT: {gt_volume_ml:.1f} mL, error: {volume_error*100:.0f}%)")
        else:
            feedback_parts.append(f"[+0] Could not verify volume (GT unavailable)")
        
        # ============================================================
        # Check 6: Report completeness (10 points)
        # ============================================================
        report_exists = result.get('report_exists', False)
        reported_volume = result.get('reported_volume_ml')
        reported_status = result.get('reported_distension_status')
        reported_sig = result.get('reported_clinical_significance')
        
        if report_exists:
            has_volume = reported_volume is not None and reported_volume != 'null'
            has_status = reported_status is not None and reported_status != 'null'
            has_sig = reported_sig is not None and reported_sig != 'null'
            
            if has_volume and has_status and has_sig:
                score += 10
                feedback_parts.append("[+10] Report contains all required fields")
            else:
                missing = []
                if not has_volume: missing.append("volume_ml")
                if not has_status: missing.append("distension_status")
                if not has_sig: missing.append("clinical_significance")
                score += max(0, 10 - 3 * len(missing))
                feedback_parts.append(f"[+{max(0, 10 - 3 * len(missing))}] Report missing: {', '.join(missing)}")
        else:
            feedback_parts.append("[+0] Report file not found")
        
        # ============================================================
        # Check 7: Classification correctness (15 points)
        # ============================================================
        if reported_status and reported_status != 'null':
            # Clean up string
            status_str = str(reported_status).strip("'\"").strip()
            details['reported_status'] = status_str
            
            if status_str.lower() == gt_classification.lower():
                score += 15
                feedback_parts.append(f"[+15] Distension classification correct: {status_str}")
            else:
                # Check if classification matches reported volume (internal consistency)
                if reported_volume and reported_volume != 'null':
                    try:
                        rv = float(reported_volume)
                        if rv < 300:
                            expected_from_vol = "Normal"
                        elif rv < 500:
                            expected_from_vol = "Mildly Distended"
                        elif rv < 800:
                            expected_from_vol = "Moderately Distended"
                        else:
                            expected_from_vol = "Severely Distended"
                        
                        if status_str.lower() == expected_from_vol.lower():
                            score += 8
                            feedback_parts.append(f"[+8] Classification consistent with reported volume ({status_str})")
                        else:
                            feedback_parts.append(f"[+0] Classification incorrect: {status_str} (expected: {gt_classification})")
                    except:
                        feedback_parts.append(f"[+0] Classification incorrect: {status_str} (expected: {gt_classification})")
                else:
                    feedback_parts.append(f"[+0] Classification incorrect: {status_str} (expected: {gt_classification})")
        else:
            feedback_parts.append("[+0] No distension classification reported")
        
        # ============================================================
        # Check 8: Clinical significance (10 points)
        # ============================================================
        if reported_sig and reported_sig != 'null':
            try:
                sig_bool = str(reported_sig).lower() == 'true'
                details['reported_clinical_significance'] = sig_bool
                
                if sig_bool == gt_clinical_sig:
                    score += 10
                    feedback_parts.append(f"[+10] Clinical significance correct: {sig_bool}")
                else:
                    # Partial credit if consistent with reported volume
                    if reported_volume and reported_volume != 'null':
                        try:
                            rv = float(reported_volume)
                            expected_sig = rv > 500
                            if sig_bool == expected_sig:
                                score += 5
                                feedback_parts.append(f"[+5] Clinical significance consistent with reported volume")
                            else:
                                feedback_parts.append(f"[+0] Clinical significance incorrect: {sig_bool} (expected: {gt_clinical_sig})")
                        except:
                            feedback_parts.append(f"[+0] Clinical significance incorrect: {sig_bool} (expected: {gt_clinical_sig})")
                    else:
                        feedback_parts.append(f"[+0] Clinical significance incorrect: {sig_bool} (expected: {gt_clinical_sig})")
            except Exception as e:
                feedback_parts.append(f"[+0] Could not parse clinical significance: {reported_sig}")
        else:
            feedback_parts.append("[+0] No clinical significance reported")
        
        # ============================================================
        # Determine pass/fail
        # ============================================================
        # Pass requires: score >= 60 AND dice >= 0.5
        passed = score >= 60 and dice >= dice_min
        
        details['final_score'] = score
        details['max_score'] = max_score
        details['pass_threshold'] = 60
        details['dice_threshold'] = dice_min
        
        # Summary
        feedback_parts.append("")
        feedback_parts.append("=== Summary ===")
        feedback_parts.append(f"Total Score: {score}/{max_score}")
        feedback_parts.append(f"Dice Coefficient: {dice:.3f} (threshold: {dice_min})")
        feedback_parts.append(f"Agent Volume: {agent_volume_ml:.1f} mL | GT Volume: {gt_volume_ml:.1f} mL")
        feedback_parts.append(f"Passed: {passed}")
        
    except Exception as e:
        import traceback
        feedback_parts.append(f"ERROR during verification: {str(e)}")
        feedback_parts.append(traceback.format_exc())
        passed = False
        details['error'] = str(e)
    
    finally:
        # Clean up temp directory
        shutil.rmtree(temp_dir, ignore_errors=True)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": to_python_type(details)
    }


if __name__ == "__main__":
    # For standalone testing
    print("Bladder Volume Assessment Verifier")
    print("Run with gym-anything framework for full verification")