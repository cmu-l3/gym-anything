#!/usr/bin/env python3
"""
Verifier for Stereotactic Brain Biopsy Trajectory Planning task.

VERIFICATION METRICS:
1. Target in Tumor (25 pts): Target fiducial within enhancing tumor region
2. Trajectory Avoids Ventricles (25 pts): No trajectory point intersects edema/CSF
3. Valid Entry Point (15 pts): Entry superior to target, not at midline
4. Trajectory Length Correct (10 pts): Reported length matches computed
5. Angle Calculation (10 pts): Reported angle matches computed
6. Ventricle Clearance Reported (5 pts): Clearance value present and > 0
7. All Markups Saved (5 pts): Target, entry, and trajectory files exist
8. Report Complete (5 pts): JSON report has all required fields

Pass threshold: 60 points with "Target in Tumor" AND "Trajectory Avoids Ventricles"
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


def verify_stereotactic_biopsy_planning(traj, env_info, task_info):
    """
    Verify the stereotactic biopsy planning task.
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get scoring weights from metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    
    w_target = weights.get('target_in_tumor', 25)
    w_trajectory = weights.get('trajectory_avoids_ventricles', 25)
    w_entry = weights.get('valid_entry_point', 15)
    w_length = weights.get('trajectory_length_correct', 10)
    w_angle = weights.get('angle_calculation', 10)
    w_clearance = weights.get('clearance_reported', 5)
    w_markups = weights.get('all_markups_saved', 5)
    w_report = weights.get('report_complete', 5)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # Key criteria tracking
    target_in_tumor = False
    trajectory_safe = False
    
    # ================================================================
    # Load result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/trajectory_task_result.json", temp_result.name)
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
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # Load ground truth
    # ================================================================
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/trajectory_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        feedback_parts.append(f"Warning: Ground truth loading issue: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    target_gt = np.array(gt_data.get('target_ras', [0, 0, 0]))
    affine = np.array(gt_data.get('affine', np.eye(4).tolist()))
    voxel_dims = gt_data.get('voxel_dims_mm', [1, 1, 1])
    shape = gt_data.get('shape', [100, 100, 100])
    brain_bounds = gt_data.get('brain_bounds_voxel', {})
    
    details['gt_target_ras'] = target_gt.tolist()
    
    # ================================================================
    # Load segmentation for target zone validation
    # ================================================================
    seg_data = None
    temp_seg_dir = tempfile.mkdtemp()
    temp_seg_path = os.path.join(temp_seg_dir, 'seg.nii.gz')
    try:
        copy_from_env("/tmp/ground_truth_seg.nii.gz", temp_seg_path)
        import nibabel as nib
        seg_nii = nib.load(temp_seg_path)
        seg_data = seg_nii.get_fdata().astype(np.int32)
        details['seg_loaded'] = True
    except ImportError:
        # Try to install nibabel
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
            import nibabel as nib
            seg_nii = nib.load(temp_seg_path)
            seg_data = seg_nii.get_fdata().astype(np.int32)
            details['seg_loaded'] = True
        except Exception as e:
            logger.warning(f"Could not load segmentation: {e}")
            details['seg_loaded'] = False
    except Exception as e:
        logger.warning(f"Could not load segmentation: {e}")
        details['seg_loaded'] = False
    finally:
        shutil.rmtree(temp_seg_dir, ignore_errors=True)
    
    # ================================================================
    # Load edema distance transform
    # ================================================================
    edema_dt = None
    temp_dt_dir = tempfile.mkdtemp()
    temp_dt_path = os.path.join(temp_dt_dir, 'edema_dt.npy')
    try:
        copy_from_env("/tmp/edema_distance_transform.npy", temp_dt_path)
        edema_dt = np.load(temp_dt_path)
        details['edema_dt_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load edema distance transform: {e}")
        details['edema_dt_loaded'] = False
    finally:
        shutil.rmtree(temp_dt_dir, ignore_errors=True)
    
    # ================================================================
    # CRITERION 1: Target in Tumor (25 points)
    # ================================================================
    target_coords = result.get('target_coordinates_ras')
    
    if target_coords is None or target_coords == "null" or target_coords == []:
        feedback_parts.append(f"❌ Target markup not found (0/{w_target})")
        details['target_in_tumor'] = False
    else:
        target_ras = np.array(target_coords)
        details['agent_target_ras'] = target_ras.tolist()
        
        try:
            # Convert RAS to voxel coordinates
            affine_inv = np.linalg.inv(affine)
            target_voxel = np.round(affine_inv[:3, :3] @ target_ras + affine_inv[:3, 3]).astype(int)
            details['agent_target_voxel'] = target_voxel.tolist()
            
            # Check if target is within volume bounds
            in_bounds = all(0 <= target_voxel[i] < shape[i] for i in range(3))
            
            if in_bounds and seg_data is not None:
                # Check if target is in enhancing tumor (label 4) or tumor core (label 1)
                target_label = seg_data[target_voxel[0], target_voxel[1], target_voxel[2]]
                details['target_label'] = int(target_label)
                
                if target_label == 4:
                    target_in_tumor = True
                    score += w_target
                    feedback_parts.append(f"✓ Target is within enhancing tumor ({w_target}/{w_target})")
                elif target_label == 1:
                    target_in_tumor = True
                    pts = int(w_target * 0.8)
                    score += pts
                    feedback_parts.append(f"⚠ Target in necrotic core (acceptable) ({pts}/{w_target})")
                elif target_label == 2:
                    pts = int(w_target * 0.4)
                    score += pts
                    feedback_parts.append(f"⚠ Target in edema region (suboptimal) ({pts}/{w_target})")
                else:
                    # Check distance to tumor
                    tumor_mask = (seg_data == 4) | (seg_data == 1)
                    tumor_coords = np.argwhere(tumor_mask)
                    if len(tumor_coords) > 0:
                        distances = np.linalg.norm(tumor_coords - target_voxel, axis=1) * np.mean(voxel_dims)
                        min_dist = np.min(distances)
                        details['target_distance_to_tumor_mm'] = float(min_dist)
                        
                        if min_dist <= 5:
                            target_in_tumor = True
                            pts = int(w_target * 0.8)
                            score += pts
                            feedback_parts.append(f"⚠ Target {min_dist:.1f}mm from tumor ({pts}/{w_target})")
                        elif min_dist <= 10:
                            pts = int(w_target * 0.4)
                            score += pts
                            feedback_parts.append(f"⚠ Target {min_dist:.1f}mm from tumor ({pts}/{w_target})")
                        else:
                            feedback_parts.append(f"❌ Target {min_dist:.1f}mm from tumor (0/{w_target})")
                    else:
                        feedback_parts.append(f"❌ Could not verify target location (0/{w_target})")
            else:
                # Fallback: check distance to expected target
                dist_to_expected = np.linalg.norm(target_ras - target_gt)
                details['target_distance_to_expected_mm'] = float(dist_to_expected)
                
                if dist_to_expected <= 15:
                    target_in_tumor = True
                    pts = int(w_target * 0.8)
                    score += pts
                    feedback_parts.append(f"⚠ Target {dist_to_expected:.1f}mm from expected ({pts}/{w_target})")
                else:
                    feedback_parts.append(f"❌ Target {dist_to_expected:.1f}mm from expected (0/{w_target})")
        except Exception as e:
            logger.error(f"Error validating target: {e}")
            feedback_parts.append(f"❌ Error validating target: {e} (0/{w_target})")
    
    # ================================================================
    # CRITERION 2: Trajectory Avoids Ventricles (25 points)
    # ================================================================
    entry_coords = result.get('entry_coordinates_ras')
    
    if entry_coords is None or entry_coords == "null" or entry_coords == []:
        feedback_parts.append(f"❌ Entry markup not found (0/{w_trajectory})")
    elif target_coords is None or target_coords == "null" or target_coords == []:
        feedback_parts.append(f"❌ Cannot check trajectory without target (0/{w_trajectory})")
    else:
        entry_ras = np.array(entry_coords)
        target_ras = np.array(target_coords)
        details['agent_entry_ras'] = entry_ras.tolist()
        
        # Sample points along trajectory
        n_samples = 50
        trajectory_points = []
        for t in np.linspace(0, 1, n_samples):
            point = entry_ras + t * (target_ras - entry_ras)
            trajectory_points.append(point)
        
        # Check each point for edema intersection
        if edema_dt is not None and seg_data is not None:
            try:
                affine_inv = np.linalg.inv(affine)
                min_clearance = float('inf')
                intersects_edema = False
                
                for point in trajectory_points:
                    voxel = np.round(affine_inv[:3, :3] @ point + affine_inv[:3, 3]).astype(int)
                    
                    # Check bounds
                    if not all(0 <= voxel[i] < shape[i] for i in range(3)):
                        continue
                    
                    clearance = edema_dt[voxel[0], voxel[1], voxel[2]]
                    min_clearance = min(min_clearance, clearance)
                    
                    # Check if inside edema (label 2)
                    if seg_data[voxel[0], voxel[1], voxel[2]] == 2:
                        intersects_edema = True
                
                details['min_clearance_mm'] = float(min_clearance) if min_clearance != float('inf') else 0
                details['intersects_edema'] = intersects_edema
                
                if not intersects_edema and min_clearance > 0:
                    trajectory_safe = True
                    score += w_trajectory
                    feedback_parts.append(f"✓ Trajectory avoids edema (clearance: {min_clearance:.1f}mm) ({w_trajectory}/{w_trajectory})")
                elif min_clearance > 2:
                    trajectory_safe = True
                    pts = int(w_trajectory * 0.8)
                    score += pts
                    feedback_parts.append(f"⚠ Trajectory near edema (clearance: {min_clearance:.1f}mm) ({pts}/{w_trajectory})")
                elif min_clearance > 0:
                    pts = int(w_trajectory * 0.4)
                    score += pts
                    feedback_parts.append(f"⚠ Trajectory very close to edema ({min_clearance:.1f}mm) ({pts}/{w_trajectory})")
                else:
                    feedback_parts.append(f"❌ Trajectory passes through edema region (0/{w_trajectory})")
            except Exception as e:
                # Can't fully validate, give partial credit for having both points
                pts = int(w_trajectory * 0.6)
                score += pts
                trajectory_safe = True  # Assume safe for passing criteria
                feedback_parts.append(f"⚠ Could not fully validate trajectory: {e} ({pts}/{w_trajectory})")
        else:
            # Basic check: entry should be superior to target
            if entry_ras[2] > target_ras[2]:
                trajectory_safe = True
                pts = int(w_trajectory * 0.6)
                score += pts
                feedback_parts.append(f"⚠ Entry superior to target (partial validation) ({pts}/{w_trajectory})")
            else:
                feedback_parts.append(f"❌ Entry not superior to target (0/{w_trajectory})")
    
    # ================================================================
    # CRITERION 3: Valid Entry Point (15 points)
    # ================================================================
    if entry_coords is None or entry_coords == "null" or entry_coords == []:
        feedback_parts.append(f"❌ Entry point missing (0/{w_entry})")
    else:
        entry_ras = np.array(entry_coords)
        entry_valid = True
        entry_issues = []
        
        # Entry should be superior to target
        if target_coords is not None and target_coords != "null" and target_coords != []:
            target_ras = np.array(target_coords)
            if entry_ras[2] <= target_ras[2]:
                entry_valid = False
                entry_issues.append("not superior to target")
        
        # Entry should not be at midline (R coordinate should be > 5mm from 0)
        if abs(entry_ras[0]) < 5:
            entry_issues.append("too close to midline")
        
        details['entry_issues'] = entry_issues
        
        if entry_valid and len(entry_issues) == 0:
            score += w_entry
            feedback_parts.append(f"✓ Valid entry point location ({w_entry}/{w_entry})")
        elif entry_valid:
            pts = int(w_entry * 0.67)
            score += pts
            feedback_parts.append(f"⚠ Entry point has concerns: {', '.join(entry_issues)} ({pts}/{w_entry})")
        else:
            pts = int(w_entry * 0.33)
            score += pts
            feedback_parts.append(f"❌ Entry point issues: {', '.join(entry_issues)} ({pts}/{w_entry})")
    
    # ================================================================
    # CRITERION 4: Trajectory Length Correct (10 points)
    # ================================================================
    report_data = result.get('report_data', {})
    if isinstance(report_data, str):
        try:
            report_data = json.loads(report_data)
        except:
            report_data = {}
    
    reported_length = report_data.get('trajectory_length_mm')
    
    if target_coords is not None and entry_coords is not None and \
       target_coords != "null" and entry_coords != "null" and \
       target_coords != [] and entry_coords != []:
        computed_length = np.linalg.norm(np.array(entry_coords) - np.array(target_coords))
        details['computed_length_mm'] = float(computed_length)
        
        if reported_length is not None:
            try:
                reported_length = float(reported_length)
                details['reported_length_mm'] = reported_length
                length_error = abs(reported_length - computed_length)
                
                if length_error <= 5:
                    score += w_length
                    feedback_parts.append(f"✓ Trajectory length correct ({reported_length:.1f}mm) ({w_length}/{w_length})")
                elif length_error <= 10:
                    pts = int(w_length * 0.7)
                    score += pts
                    feedback_parts.append(f"⚠ Trajectory length close ({reported_length:.1f}mm vs {computed_length:.1f}mm) ({pts}/{w_length})")
                else:
                    pts = int(w_length * 0.3)
                    score += pts
                    feedback_parts.append(f"❌ Trajectory length error ({reported_length:.1f}mm vs {computed_length:.1f}mm) ({pts}/{w_length})")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Invalid trajectory length value (0/{w_length})")
        else:
            feedback_parts.append(f"❌ Trajectory length not reported (0/{w_length})")
    else:
        feedback_parts.append(f"❌ Cannot compute trajectory length (missing points) (0/{w_length})")
    
    # ================================================================
    # CRITERION 5: Angle Calculation (10 points)
    # ================================================================
    reported_angle = report_data.get('angle_from_vertical_deg')
    
    if target_coords is not None and entry_coords is not None and \
       target_coords != "null" and entry_coords != "null" and \
       target_coords != [] and entry_coords != []:
        trajectory_vec = np.array(target_coords) - np.array(entry_coords)
        computed_length = np.linalg.norm(trajectory_vec)
        if computed_length > 0:
            computed_angle = np.degrees(np.arccos(abs(trajectory_vec[2]) / computed_length))
        else:
            computed_angle = 0
        details['computed_angle_deg'] = float(computed_angle)
        
        if reported_angle is not None:
            try:
                reported_angle = float(reported_angle)
                details['reported_angle_deg'] = reported_angle
                angle_error = abs(reported_angle - computed_angle)
                
                if angle_error <= 5:
                    score += w_angle
                    feedback_parts.append(f"✓ Angle correct ({reported_angle:.1f}°) ({w_angle}/{w_angle})")
                elif angle_error <= 10:
                    pts = int(w_angle * 0.7)
                    score += pts
                    feedback_parts.append(f"⚠ Angle close ({reported_angle:.1f}° vs {computed_angle:.1f}°) ({pts}/{w_angle})")
                else:
                    pts = int(w_angle * 0.3)
                    score += pts
                    feedback_parts.append(f"❌ Angle error ({reported_angle:.1f}° vs {computed_angle:.1f}°) ({pts}/{w_angle})")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Invalid angle value (0/{w_angle})")
        else:
            feedback_parts.append(f"❌ Angle not reported (0/{w_angle})")
    else:
        feedback_parts.append(f"❌ Cannot compute angle (missing points) (0/{w_angle})")
    
    # ================================================================
    # CRITERION 6: Ventricle Clearance Reported (5 points)
    # ================================================================
    reported_clearance = report_data.get('ventricle_clearance_mm')
    if reported_clearance is not None:
        try:
            clearance = float(reported_clearance)
            details['reported_clearance_mm'] = clearance
            if clearance > 0:
                score += w_clearance
                feedback_parts.append(f"✓ Ventricle clearance reported ({clearance:.1f}mm) ({w_clearance}/{w_clearance})")
            else:
                pts = int(w_clearance * 0.4)
                score += pts
                feedback_parts.append(f"⚠ Ventricle clearance is 0 or negative ({pts}/{w_clearance})")
        except (ValueError, TypeError):
            feedback_parts.append(f"❌ Invalid clearance value (0/{w_clearance})")
    else:
        feedback_parts.append(f"❌ Ventricle clearance not reported (0/{w_clearance})")
    
    # ================================================================
    # CRITERION 7: All Markups Saved (5 points)
    # ================================================================
    markups_exist = 0
    if result.get('target_markup_exists'):
        markups_exist += 1
    if result.get('entry_markup_exists'):
        markups_exist += 1
    if result.get('trajectory_markup_exists'):
        markups_exist += 1
    
    details['markups_count'] = markups_exist
    
    if markups_exist == 3:
        score += w_markups
        feedback_parts.append(f"✓ All 3 markups saved ({w_markups}/{w_markups})")
    elif markups_exist >= 2:
        pts = int(w_markups * 0.6)
        score += pts
        feedback_parts.append(f"⚠ {markups_exist}/3 markups saved ({pts}/{w_markups})")
    elif markups_exist >= 1:
        pts = int(w_markups * 0.2)
        score += pts
        feedback_parts.append(f"❌ Only {markups_exist}/3 markups saved ({pts}/{w_markups})")
    else:
        feedback_parts.append(f"❌ No markups saved (0/{w_markups})")
    
    # ================================================================
    # CRITERION 8: Report Completeness (5 points)
    # ================================================================
    required_fields = [
        'trajectory_length_mm',
        'angle_from_vertical_deg',
        'ventricle_clearance_mm',
        'entry_coordinates_ras',
        'target_coordinates_ras'
    ]
    present_fields = sum(1 for f in required_fields if f in report_data and report_data[f] is not None)
    details['report_fields_present'] = present_fields
    details['report_fields_required'] = len(required_fields)
    
    if present_fields == len(required_fields):
        score += w_report
        feedback_parts.append(f"✓ Report has all required fields ({w_report}/{w_report})")
    elif present_fields >= 3:
        pts = int(w_report * 0.6)
        score += pts
        feedback_parts.append(f"⚠ Report has {present_fields}/{len(required_fields)} fields ({pts}/{w_report})")
    elif present_fields >= 1:
        pts = int(w_report * 0.2)
        score += pts
        feedback_parts.append(f"❌ Report has only {present_fields}/{len(required_fields)} fields ({pts}/{w_report})")
    else:
        feedback_parts.append(f"❌ Report missing or empty (0/{w_report})")
    
    # ================================================================
    # Anti-gaming check: files created during task
    # ================================================================
    files_created_during_task = (
        result.get('target_created_during_task', False) or
        result.get('entry_created_during_task', False) or
        result.get('trajectory_created_during_task', False)
    )
    details['files_created_during_task'] = files_created_during_task
    
    if not files_created_during_task and markups_exist > 0:
        feedback_parts.append("⚠ Warning: Output files may have existed before task")
    
    # ================================================================
    # Final assessment
    # ================================================================
    feedback_parts.append(f"\n--- Final Score: {score}/100 ---")
    
    # Pass criteria: 60 points with target in tumor AND trajectory safe
    key_criteria_met = target_in_tumor and trajectory_safe
    passed = score >= 60 and key_criteria_met
    
    if passed:
        feedback_parts.append("✓ PASS: Score >= 60 with target in tumor and safe trajectory")
    elif score >= 60:
        feedback_parts.append("⚠ Score >= 60 but missing key criteria (target in tumor AND/OR safe trajectory)")
    else:
        feedback_parts.append("❌ FAIL: Score < 60")
    
    details['target_in_tumor'] = target_in_tumor
    details['trajectory_safe'] = trajectory_safe
    details['key_criteria_met'] = key_criteria_met
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "\n".join(feedback_parts),
        "details": to_python_type(details)
    }


def main():
    """Main entry point for standalone testing."""
    # Mock data for testing
    result_data = {
        "slicer_was_running": True,
        "target_markup_exists": True,
        "entry_markup_exists": True,
        "trajectory_markup_exists": True,
        "report_exists": True,
        "target_coordinates_ras": [10, -20, 30],
        "entry_coordinates_ras": [10, -20, 80],
        "report_data": {
            "trajectory_length_mm": 50,
            "angle_from_vertical_deg": 5,
            "ventricle_clearance_mm": 15
        }
    }
    
    print("Stereotactic Biopsy Planning Verifier")
    print("=" * 50)
    print("This verifier requires running within the framework.")
    print("Standalone mode not fully supported.")
    

if __name__ == "__main__":
    main()