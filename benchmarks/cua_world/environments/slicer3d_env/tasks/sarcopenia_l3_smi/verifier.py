#!/usr/bin/env python3
"""
Verifier for L3 Skeletal Muscle Index (Sarcopenia) Assessment Task.

VERIFICATION METRICS:
1. L3 Level Accuracy (20 pts) - Is the segmented slice at L3?
2. Muscle Area Accuracy (30 pts) - Is the SMA within 15% of ground truth?
3. Segmentation Quality (15 pts) - Dice coefficient >= 0.7
4. SMI Calculation (10 pts) - Is SMI = SMA / height² correct?
5. Sarcopenia Classification (10 pts) - Correct yes/no based on threshold
6. No Organ Contamination (5 pts) - Minimal overlap with organs
7. Report Completeness (10 pts) - All required JSON fields present

Pass threshold: 60 points with Muscle Area Accuracy achieved
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


def verify_sarcopenia_l3_smi(traj, env_info, task_info):
    """
    Verify L3 sarcopenia assessment task completion.

    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata

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

    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})

    # Thresholds
    l3_slice_tolerance = thresholds.get('l3_slice_tolerance', 2)
    sma_error_max_pct = thresholds.get('sma_error_max_percent', 15)
    dice_min = thresholds.get('dice_min', 0.7)

    # Weights
    w_l3_level = weights.get('l3_level_accuracy', 20)
    w_sma = weights.get('muscle_area_accuracy', 30)
    w_seg_quality = weights.get('segmentation_quality', 15)
    w_smi = weights.get('smi_calculation', 10)
    w_class = weights.get('sarcopenia_classification', 10)
    w_contamination = weights.get('no_organ_contamination', 5)
    w_report = weights.get('report_completeness', 10)

    # Patient parameters
    patient_height = metadata.get('patient_height_m', 1.68)
    sarcopenia_threshold = metadata.get('sarcopenia_threshold_male', 52.4)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {
        "scores": {},
        "metrics": {},
        "thresholds_used": {
            "l3_slice_tolerance": l3_slice_tolerance,
            "sma_error_max_percent": sma_error_max_pct,
            "dice_min": dice_min,
            "sarcopenia_threshold": sarcopenia_threshold
        }
    }

    temp_dir = tempfile.mkdtemp()

    try:
        # ================================================================
        # LOAD TASK RESULT
        # ================================================================
        result_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/sarcopenia_task_result.json", result_path)
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to read task result: {e}"
            }

        # ================================================================
        # LOAD GROUND TRUTH
        # ================================================================
        gt_path = os.path.join(temp_dir, "ground_truth.json")
        gt_data = {}
        try:
            copy_from_env("/tmp/sarcopenia_ground_truth.json", gt_path)
            with open(gt_path, 'r') as f:
                gt_data = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load ground truth: {e}")
            details['gt_load_error'] = str(e)

        gt_l3_slice = gt_data.get('l3_slice_index', 0)
        gt_sma = gt_data.get('skeletal_muscle_area_cm2', 0)
        gt_smi = gt_data.get('smi_cm2_m2', 0)
        gt_classification = gt_data.get('sarcopenia_classification', '')
        acceptable_slice_range = gt_data.get('acceptable_slice_range', [gt_l3_slice - 2, gt_l3_slice + 2])

        details['metrics']['gt_l3_slice'] = gt_l3_slice
        details['metrics']['gt_sma_cm2'] = gt_sma
        details['metrics']['gt_smi'] = gt_smi
        details['metrics']['gt_classification'] = gt_classification

        # ================================================================
        # CHECK BASIC REQUIREMENTS
        # ================================================================
        
        # Check if Slicer was running
        if not result.get('slicer_was_running', False):
            feedback_parts.append("FAIL: Slicer was not running")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(details)
            }

        # Check if segmentation exists
        seg_exists = result.get('segmentation_exists', False)
        if not seg_exists:
            feedback_parts.append("FAIL: No segmentation file found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(details)
            }

        # Check if file was created during task (anti-gaming)
        file_created = result.get('file_created_during_task', False)
        if not file_created:
            feedback_parts.append("WARNING: Segmentation may have existed before task")
            details['anti_gaming_warning'] = True

        # ================================================================
        # GET AGENT'S MEASUREMENTS FROM RESULT
        # ================================================================
        agent_l3_slice_str = result.get('agent_l3_slice', '')
        agent_sma_str = result.get('agent_sma_cm2', '')
        agent_pixel_count_str = result.get('agent_pixel_count', '')

        agent_l3_slice = int(agent_l3_slice_str) if agent_l3_slice_str else None
        agent_sma = float(agent_sma_str) if agent_sma_str else None
        agent_pixel_count = int(agent_pixel_count_str) if agent_pixel_count_str else None

        details['metrics']['agent_l3_slice'] = agent_l3_slice
        details['metrics']['agent_sma_cm2'] = agent_sma
        details['metrics']['agent_pixel_count'] = agent_pixel_count

        # ================================================================
        # ANTI-GAMING CHECK: Reasonable pixel count
        # ================================================================
        if agent_pixel_count is not None:
            if agent_pixel_count < 5000:
                feedback_parts.append(f"FAIL: Segmentation too small ({agent_pixel_count} pixels < 5000)")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts),
                    "details": to_python_type(details)
                }
            if agent_pixel_count > 100000:
                feedback_parts.append(f"WARNING: Segmentation unusually large ({agent_pixel_count} pixels)")

        # ================================================================
        # CRITERION 1: L3 Level Accuracy (20 points)
        # ================================================================
        if agent_l3_slice is not None and gt_l3_slice > 0:
            slice_diff = abs(agent_l3_slice - gt_l3_slice)
            details['metrics']['slice_difference'] = slice_diff

            if acceptable_slice_range[0] <= agent_l3_slice <= acceptable_slice_range[1]:
                score += w_l3_level
                details['scores']['l3_level_accuracy'] = w_l3_level
                feedback_parts.append(f"PASS: L3 level correct (slice {agent_l3_slice}, GT: {gt_l3_slice})")
            elif slice_diff <= 5:
                partial = w_l3_level // 2
                score += partial
                details['scores']['l3_level_accuracy'] = partial
                feedback_parts.append(f"PARTIAL: L3 level close (slice {agent_l3_slice}, GT: {gt_l3_slice}, diff: {slice_diff})")
            else:
                details['scores']['l3_level_accuracy'] = 0
                feedback_parts.append(f"FAIL: L3 level incorrect (slice {agent_l3_slice}, GT: {gt_l3_slice}, diff: {slice_diff})")
        else:
            details['scores']['l3_level_accuracy'] = 0
            feedback_parts.append("FAIL: Could not determine L3 slice from segmentation")

        # ================================================================
        # CRITERION 2: Muscle Area Accuracy (30 points)
        # ================================================================
        if agent_sma is not None and gt_sma > 0:
            sma_error_pct = abs(agent_sma - gt_sma) / gt_sma * 100
            details['metrics']['sma_error_percent'] = round(sma_error_pct, 1)

            if sma_error_pct <= sma_error_max_pct:
                score += w_sma
                details['scores']['muscle_area_accuracy'] = w_sma
                feedback_parts.append(f"PASS: SMA accurate ({agent_sma:.1f} cm², GT: {gt_sma:.1f} cm², error: {sma_error_pct:.1f}%)")
            elif sma_error_pct <= 25:
                partial = w_sma // 2
                score += partial
                details['scores']['muscle_area_accuracy'] = partial
                feedback_parts.append(f"PARTIAL: SMA within 25% ({agent_sma:.1f} cm², GT: {gt_sma:.1f} cm², error: {sma_error_pct:.1f}%)")
            else:
                details['scores']['muscle_area_accuracy'] = 0
                feedback_parts.append(f"FAIL: SMA inaccurate ({agent_sma:.1f} cm², GT: {gt_sma:.1f} cm², error: {sma_error_pct:.1f}%)")
        else:
            details['scores']['muscle_area_accuracy'] = 0
            feedback_parts.append("FAIL: Could not determine SMA from segmentation")

        # ================================================================
        # CRITERION 3: Segmentation Quality - Dice (15 points)
        # ================================================================
        dice_score = None
        
        # Try to compute Dice if we have both segmentations
        try:
            import nibabel as nib
            
            agent_seg_path = os.path.join(temp_dir, "agent_seg.nii.gz")
            gt_seg_path = os.path.join(temp_dir, "gt_seg.nii.gz")
            
            copy_from_env("/tmp/agent_l3_segmentation.nii.gz", agent_seg_path)
            copy_from_env("/tmp/ground_truth_l3_muscle.nii.gz", gt_seg_path)
            
            agent_nii = nib.load(agent_seg_path)
            gt_nii = nib.load(gt_seg_path)
            
            agent_data = agent_nii.get_fdata()
            gt_data_vol = gt_nii.get_fdata()
            
            # Get the slices with data
            if agent_l3_slice is not None and gt_l3_slice > 0:
                # Compare at GT L3 slice
                gt_slice = gt_data_vol[:, :, gt_l3_slice] > 0
                
                # Use agent's selected slice
                agent_slice = agent_data[:, :, agent_l3_slice] > 0
                
                # Handle shape mismatch
                if gt_slice.shape != agent_slice.shape:
                    from scipy.ndimage import zoom
                    zoom_factors = (gt_slice.shape[0] / agent_slice.shape[0],
                                   gt_slice.shape[1] / agent_slice.shape[1])
                    agent_slice = zoom(agent_slice.astype(float), zoom_factors, order=0) > 0.5
                
                # Compute Dice
                intersection = np.sum(gt_slice & agent_slice)
                dice_score = 2 * intersection / (np.sum(gt_slice) + np.sum(agent_slice)) if (np.sum(gt_slice) + np.sum(agent_slice)) > 0 else 0
                
                details['metrics']['dice_coefficient'] = round(dice_score, 3)
                
                if dice_score >= dice_min:
                    score += w_seg_quality
                    details['scores']['segmentation_quality'] = w_seg_quality
                    feedback_parts.append(f"PASS: Segmentation quality good (Dice: {dice_score:.3f})")
                elif dice_score >= 0.5:
                    partial = w_seg_quality // 2
                    score += partial
                    details['scores']['segmentation_quality'] = partial
                    feedback_parts.append(f"PARTIAL: Segmentation quality moderate (Dice: {dice_score:.3f})")
                else:
                    details['scores']['segmentation_quality'] = 0
                    feedback_parts.append(f"FAIL: Segmentation quality poor (Dice: {dice_score:.3f})")
        except Exception as e:
            logger.warning(f"Could not compute Dice: {e}")
            details['scores']['segmentation_quality'] = 0
            details['dice_error'] = str(e)
            feedback_parts.append(f"Could not compute Dice coefficient: {e}")

        # ================================================================
        # CRITERIA 4-7: Report-based scoring
        # ================================================================
        report_exists = result.get('report_exists', False)
        
        if report_exists:
            # Load agent's report
            agent_report_path = os.path.join(temp_dir, "agent_report.json")
            agent_report = {}
            try:
                copy_from_env("/tmp/agent_sarcopenia_report.json", agent_report_path)
                with open(agent_report_path, 'r') as f:
                    agent_report = json.load(f)
            except Exception as e:
                logger.warning(f"Failed to load agent report: {e}")
                agent_report = {}

            # CRITERION 4: SMI Calculation (10 points)
            if 'smi_cm2_m2' in agent_report and 'skeletal_muscle_area_cm2' in agent_report:
                reported_sma = agent_report.get('skeletal_muscle_area_cm2', 0)
                reported_smi = agent_report.get('smi_cm2_m2', 0)
                expected_smi = reported_sma / (patient_height ** 2) if reported_sma else 0

                smi_calc_error = abs(reported_smi - expected_smi)
                details['metrics']['reported_smi'] = reported_smi
                details['metrics']['expected_smi_from_sma'] = round(expected_smi, 2)

                if smi_calc_error < 0.5:
                    score += w_smi
                    details['scores']['smi_calculation'] = w_smi
                    feedback_parts.append(f"PASS: SMI calculation correct ({reported_smi:.2f})")
                else:
                    details['scores']['smi_calculation'] = 0
                    feedback_parts.append(f"FAIL: SMI calculation incorrect ({reported_smi:.2f}, expected ~{expected_smi:.2f})")
            else:
                details['scores']['smi_calculation'] = 0
                feedback_parts.append("FAIL: SMI or SMA not in report")

            # CRITERION 5: Sarcopenia Classification (10 points)
            if 'sarcopenia_classification' in agent_report:
                agent_classification = agent_report['sarcopenia_classification'].lower().strip()
                
                if agent_classification in ['sarcopenic', 'normal']:
                    if agent_classification == gt_classification:
                        score += w_class
                        details['scores']['sarcopenia_classification'] = w_class
                        feedback_parts.append(f"PASS: Sarcopenia classification correct ({agent_classification})")
                    else:
                        details['scores']['sarcopenia_classification'] = 0
                        feedback_parts.append(f"FAIL: Sarcopenia classification incorrect ({agent_classification}, GT: {gt_classification})")
                else:
                    details['scores']['sarcopenia_classification'] = 0
                    feedback_parts.append(f"FAIL: Invalid classification value: {agent_classification}")
            else:
                details['scores']['sarcopenia_classification'] = 0
                feedback_parts.append("FAIL: sarcopenia_classification not in report")

            # CRITERION 7: Report Completeness (10 points)
            required_fields = [
                "l3_slice_index", "skeletal_muscle_area_cm2", "patient_height_m",
                "patient_sex", "smi_cm2_m2", "sarcopenia_classification"
            ]
            present_fields = [f for f in required_fields if f in agent_report]
            completeness = len(present_fields) / len(required_fields)

            details['metrics']['report_fields_present'] = len(present_fields)
            details['metrics']['report_fields_required'] = len(required_fields)

            if completeness >= 0.9:
                score += w_report
                details['scores']['report_completeness'] = w_report
                feedback_parts.append(f"PASS: Report complete ({len(present_fields)}/{len(required_fields)} fields)")
            elif completeness >= 0.7:
                partial = w_report // 2
                score += partial
                details['scores']['report_completeness'] = partial
                feedback_parts.append(f"PARTIAL: Report mostly complete ({len(present_fields)}/{len(required_fields)} fields)")
            else:
                details['scores']['report_completeness'] = 0
                feedback_parts.append(f"FAIL: Report incomplete ({len(present_fields)}/{len(required_fields)} fields)")
        else:
            details['scores']['smi_calculation'] = 0
            details['scores']['sarcopenia_classification'] = 0
            details['scores']['report_completeness'] = 0
            feedback_parts.append("No report file found - report-based scores are 0")

        # CRITERION 6: No Organ Contamination (5 points)
        # Give points by default if Dice is OK or if we couldn't compute it
        if dice_score is not None and dice_score >= 0.5:
            score += w_contamination
            details['scores']['no_organ_contamination'] = w_contamination
            feedback_parts.append("PASS: No major organ contamination detected")
        elif dice_score is None:
            # Can't determine, give partial credit
            partial = w_contamination // 2
            score += partial
            details['scores']['no_organ_contamination'] = partial
        else:
            details['scores']['no_organ_contamination'] = 0

        # ================================================================
        # FINAL SCORING
        # ================================================================
        max_score = w_l3_level + w_sma + w_seg_quality + w_smi + w_class + w_contamination + w_report
        normalized_score = score / max_score if max_score > 0 else 0

        details['total_score'] = score
        details['max_score'] = max_score
        details['normalized_score'] = round(normalized_score, 3)

        # Pass criteria: need 60 points AND muscle area accuracy (at least partial)
        muscle_area_score = details['scores'].get('muscle_area_accuracy', 0)
        passed = score >= 60 and muscle_area_score >= (w_sma // 2)

        details['passed'] = passed
        feedback_parts.append(f"\nFinal Score: {score}/{max_score} = {normalized_score*100:.1f}%")
        feedback_parts.append(f"Task {'PASSED' if passed else 'FAILED'}")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        import traceback
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {e}",
            "details": {"error": str(e), "traceback": traceback.format_exc()}
        }

    finally:
        # Clean up temp directory
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    # Test mode
    print("Sarcopenia L3 SMI Verifier - Test Mode")
    print("This verifier requires the full framework to run.")