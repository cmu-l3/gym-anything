#!/usr/bin/env python3
"""
Verifier for liver steatosis assessment task.

VERIFICATION STRATEGY:
1. Liver ROI placed (10 pts) - ROI markup exists
2. Liver ROI valid (10 pts) - Has control points, created during task
3. Spleen ROI placed (10 pts) - ROI markup exists
4. Spleen ROI valid (10 pts) - Has control points, created during task
5. Liver HU accuracy (15 pts) - Within ±10 HU of ground truth
6. Spleen HU accuracy (15 pts) - Within ±10 HU of ground truth
7. L/S ratio correct (10 pts) - Within ±0.1 of expected
8. Classification correct (10 pts) - Matches expected severity
9. Report complete (10 pts) - JSON has all required fields

Pass threshold: 60 points with both ROIs placed and at least one HU accurate
"""

import json
import os
import sys
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_liver_steatosis(traj, env_info, task_info):
    """
    Verify liver steatosis assessment task completion.
    
    Uses copy_from_env to read pre-exported verification data.
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
    weights = metadata.get('scoring_weights', {})
    thresholds = metadata.get('passing_thresholds', {})
    
    hu_tolerance = metadata.get('hu_tolerance', 10)
    ratio_tolerance = metadata.get('ls_ratio_tolerance', 0.1)
    
    w_liver_roi_placed = weights.get('liver_roi_placed', 10)
    w_liver_roi_valid = weights.get('liver_roi_valid', 10)
    w_spleen_roi_placed = weights.get('spleen_roi_placed', 10)
    w_spleen_roi_valid = weights.get('spleen_roi_valid', 10)
    w_liver_hu = weights.get('liver_hu_accuracy', 15)
    w_spleen_hu = weights.get('spleen_hu_accuracy', 15)
    w_ls_ratio = weights.get('ls_ratio_correct', 10)
    w_classification = weights.get('classification_correct', 10)
    w_report = weights.get('report_complete', 10)
    
    # Initialize
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Load exported result
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/steatosis_task_result.json", temp_result.name)
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
    # Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {"liver_hu": 58.0, "spleen_hu": 52.0, "ls_ratio": 1.115, "classification": "none"}
    try:
        copy_from_env("/tmp/steatosis_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
        logger.info(f"Ground truth loaded: {gt_data}")
    except Exception as e:
        logger.warning(f"Using default ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_liver_hu = gt_data.get('liver_hu', 58.0)
    gt_spleen_hu = gt_data.get('spleen_hu', 52.0)
    gt_ls_ratio = gt_data.get('ls_ratio', gt_liver_hu / gt_spleen_hu if gt_spleen_hu != 0 else 1.0)
    gt_classification = gt_data.get('classification', 'none').lower().strip()
    
    details['ground_truth'] = {
        'liver_hu': gt_liver_hu,
        'spleen_hu': gt_spleen_hu,
        'ls_ratio': round(gt_ls_ratio, 3),
        'classification': gt_classification
    }
    
    # ================================================================
    # CRITERION 1: Liver ROI placed (10 points)
    # ================================================================
    liver_roi_exists = result.get('liver_roi_exists', False)
    liver_roi_modified = result.get('liver_roi_modified_during_task', False)
    
    if liver_roi_exists:
        score += w_liver_roi_placed
        feedback_parts.append(f"✓ Liver ROI file exists (+{w_liver_roi_placed})")
        details['liver_roi_placed'] = True
    else:
        feedback_parts.append("✗ Liver ROI file not found")
        details['liver_roi_placed'] = False
    
    # ================================================================
    # CRITERION 2: Liver ROI valid (10 points)
    # ================================================================
    liver_roi_valid = False
    if liver_roi_exists:
        temp_roi = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/liver_roi.mrk.json", temp_roi.name)
            with open(temp_roi.name, 'r') as f:
                roi_data = json.load(f)
            
            # Check for valid markup structure
            markups = roi_data.get('markups', [])
            if markups and len(markups) > 0:
                first_markup = markups[0]
                control_points = first_markup.get('controlPoints', [])
                if len(control_points) > 0:
                    liver_roi_valid = True
                    if liver_roi_modified:
                        score += w_liver_roi_valid
                        feedback_parts.append(f"✓ Liver ROI has valid control points, created during task (+{w_liver_roi_valid})")
                    else:
                        score += w_liver_roi_valid // 2
                        feedback_parts.append(f"⚠ Liver ROI valid but may pre-exist task (+{w_liver_roi_valid // 2})")
                else:
                    feedback_parts.append("✗ Liver ROI has no control points")
            else:
                feedback_parts.append("✗ Liver ROI markup structure invalid")
        except Exception as e:
            feedback_parts.append(f"✗ Could not validate liver ROI: {e}")
        finally:
            if os.path.exists(temp_roi.name):
                os.unlink(temp_roi.name)
    details['liver_roi_valid'] = liver_roi_valid
    
    # ================================================================
    # CRITERION 3: Spleen ROI placed (10 points)
    # ================================================================
    spleen_roi_exists = result.get('spleen_roi_exists', False)
    spleen_roi_modified = result.get('spleen_roi_modified_during_task', False)
    
    if spleen_roi_exists:
        score += w_spleen_roi_placed
        feedback_parts.append(f"✓ Spleen ROI file exists (+{w_spleen_roi_placed})")
        details['spleen_roi_placed'] = True
    else:
        feedback_parts.append("✗ Spleen ROI file not found")
        details['spleen_roi_placed'] = False
    
    # ================================================================
    # CRITERION 4: Spleen ROI valid (10 points)
    # ================================================================
    spleen_roi_valid = False
    if spleen_roi_exists:
        temp_roi = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/spleen_roi.mrk.json", temp_roi.name)
            with open(temp_roi.name, 'r') as f:
                roi_data = json.load(f)
            
            markups = roi_data.get('markups', [])
            if markups and len(markups) > 0:
                first_markup = markups[0]
                control_points = first_markup.get('controlPoints', [])
                if len(control_points) > 0:
                    spleen_roi_valid = True
                    if spleen_roi_modified:
                        score += w_spleen_roi_valid
                        feedback_parts.append(f"✓ Spleen ROI has valid control points, created during task (+{w_spleen_roi_valid})")
                    else:
                        score += w_spleen_roi_valid // 2
                        feedback_parts.append(f"⚠ Spleen ROI valid but may pre-exist task (+{w_spleen_roi_valid // 2})")
                else:
                    feedback_parts.append("✗ Spleen ROI has no control points")
            else:
                feedback_parts.append("✗ Spleen ROI markup structure invalid")
        except Exception as e:
            feedback_parts.append(f"✗ Could not validate spleen ROI: {e}")
        finally:
            if os.path.exists(temp_roi.name):
                os.unlink(temp_roi.name)
    details['spleen_roi_valid'] = spleen_roi_valid
    
    # ================================================================
    # CRITERION 5: Liver HU accuracy (15 points)
    # ================================================================
    liver_hu_reported = result.get('liver_hu_reported')
    liver_hu_accurate = False
    
    if liver_hu_reported is not None and liver_hu_reported != "null" and liver_hu_reported != "":
        try:
            liver_hu_val = float(liver_hu_reported)
            liver_hu_error = abs(liver_hu_val - gt_liver_hu)
            details['liver_hu_reported'] = liver_hu_val
            details['liver_hu_error'] = round(liver_hu_error, 1)
            
            if liver_hu_error <= hu_tolerance:
                score += w_liver_hu
                liver_hu_accurate = True
                feedback_parts.append(f"✓ Liver HU accurate: {liver_hu_val:.1f} (expected {gt_liver_hu:.1f}, error {liver_hu_error:.1f}) (+{w_liver_hu})")
            elif liver_hu_error <= hu_tolerance * 2:
                score += w_liver_hu // 2
                feedback_parts.append(f"⚠ Liver HU partially accurate: {liver_hu_val:.1f} (expected {gt_liver_hu:.1f}, error {liver_hu_error:.1f}) (+{w_liver_hu // 2})")
            else:
                feedback_parts.append(f"✗ Liver HU inaccurate: {liver_hu_val:.1f} (expected {gt_liver_hu:.1f}, error {liver_hu_error:.1f})")
        except (ValueError, TypeError) as e:
            feedback_parts.append(f"✗ Could not parse liver HU value: {liver_hu_reported}")
    else:
        feedback_parts.append("✗ Liver HU not reported")
    details['liver_hu_accurate'] = liver_hu_accurate
    
    # ================================================================
    # CRITERION 6: Spleen HU accuracy (15 points)
    # ================================================================
    spleen_hu_reported = result.get('spleen_hu_reported')
    spleen_hu_accurate = False
    
    if spleen_hu_reported is not None and spleen_hu_reported != "null" and spleen_hu_reported != "":
        try:
            spleen_hu_val = float(spleen_hu_reported)
            spleen_hu_error = abs(spleen_hu_val - gt_spleen_hu)
            details['spleen_hu_reported'] = spleen_hu_val
            details['spleen_hu_error'] = round(spleen_hu_error, 1)
            
            if spleen_hu_error <= hu_tolerance:
                score += w_spleen_hu
                spleen_hu_accurate = True
                feedback_parts.append(f"✓ Spleen HU accurate: {spleen_hu_val:.1f} (expected {gt_spleen_hu:.1f}, error {spleen_hu_error:.1f}) (+{w_spleen_hu})")
            elif spleen_hu_error <= hu_tolerance * 2:
                score += w_spleen_hu // 2
                feedback_parts.append(f"⚠ Spleen HU partially accurate: {spleen_hu_val:.1f} (expected {gt_spleen_hu:.1f}, error {spleen_hu_error:.1f}) (+{w_spleen_hu // 2})")
            else:
                feedback_parts.append(f"✗ Spleen HU inaccurate: {spleen_hu_val:.1f} (expected {gt_spleen_hu:.1f}, error {spleen_hu_error:.1f})")
        except (ValueError, TypeError) as e:
            feedback_parts.append(f"✗ Could not parse spleen HU value: {spleen_hu_reported}")
    else:
        feedback_parts.append("✗ Spleen HU not reported")
    details['spleen_hu_accurate'] = spleen_hu_accurate
    
    # ================================================================
    # CRITERION 7: L/S ratio correct (10 points)
    # ================================================================
    ls_ratio_reported = result.get('ls_ratio_reported')
    ls_ratio_correct = False
    
    if ls_ratio_reported is not None and ls_ratio_reported != "null" and ls_ratio_reported != "":
        try:
            ls_ratio_val = float(ls_ratio_reported)
            ls_ratio_error = abs(ls_ratio_val - gt_ls_ratio)
            details['ls_ratio_reported'] = round(ls_ratio_val, 3)
            details['ls_ratio_error'] = round(ls_ratio_error, 3)
            
            if ls_ratio_error <= ratio_tolerance:
                score += w_ls_ratio
                ls_ratio_correct = True
                feedback_parts.append(f"✓ L/S ratio correct: {ls_ratio_val:.2f} (expected {gt_ls_ratio:.2f}) (+{w_ls_ratio})")
            elif ls_ratio_error <= ratio_tolerance * 2:
                score += w_ls_ratio // 2
                feedback_parts.append(f"⚠ L/S ratio partially correct: {ls_ratio_val:.2f} (expected {gt_ls_ratio:.2f}) (+{w_ls_ratio // 2})")
            else:
                feedback_parts.append(f"✗ L/S ratio incorrect: {ls_ratio_val:.2f} (expected {gt_ls_ratio:.2f})")
        except (ValueError, TypeError):
            feedback_parts.append(f"✗ Could not parse L/S ratio: {ls_ratio_reported}")
    else:
        feedback_parts.append("✗ L/S ratio not reported")
    details['ls_ratio_correct'] = ls_ratio_correct
    
    # ================================================================
    # CRITERION 8: Classification correct (10 points)
    # ================================================================
    classification_reported = result.get('classification_reported', '').lower().strip()
    classification_correct = False
    
    if classification_reported and classification_reported != "null":
        # Normalize classification strings
        normalized = ""
        if any(x in classification_reported for x in ["none", "normal", "minimal", "absent", "no steatosis", "negative"]):
            normalized = "none"
        elif "mild" in classification_reported:
            normalized = "mild"
        elif "moderate" in classification_reported:
            normalized = "moderate"
        elif "severe" in classification_reported:
            normalized = "severe"
        else:
            normalized = classification_reported
        
        details['classification_reported'] = classification_reported
        details['classification_normalized'] = normalized
        
        if normalized == gt_classification:
            score += w_classification
            classification_correct = True
            feedback_parts.append(f"✓ Classification correct: {classification_reported} (+{w_classification})")
        else:
            feedback_parts.append(f"✗ Classification incorrect: {classification_reported} (expected {gt_classification})")
    else:
        feedback_parts.append("✗ Classification not reported")
    details['classification_correct'] = classification_correct
    
    # ================================================================
    # CRITERION 9: Report completeness (10 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    report_modified = result.get('report_modified_during_task', False)
    
    if report_exists:
        required_fields = ['liver_hu', 'spleen_hu', 'ls_ratio', 'classification']
        fields_present = sum([
            liver_hu_reported is not None and liver_hu_reported != "null",
            spleen_hu_reported is not None and spleen_hu_reported != "null",
            ls_ratio_reported is not None and ls_ratio_reported != "null",
            classification_reported and classification_reported != "null"
        ])
        
        if fields_present == len(required_fields):
            if report_modified:
                score += w_report
                feedback_parts.append(f"✓ Report complete with all required fields (+{w_report})")
            else:
                score += w_report // 2
                feedback_parts.append(f"⚠ Report complete but may pre-exist task (+{w_report // 2})")
            details['report_complete'] = True
        else:
            partial_score = (fields_present * w_report) // len(required_fields)
            score += partial_score
            feedback_parts.append(f"⚠ Report has {fields_present}/{len(required_fields)} required fields (+{partial_score})")
            details['report_complete'] = False
    else:
        feedback_parts.append("✗ Report file not found")
        details['report_complete'] = False
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    min_score = thresholds.get('min_score', 60)
    require_both_rois = thresholds.get('require_both_rois', True)
    require_one_measurement = thresholds.get('require_one_accurate_measurement', True)
    
    rois_placed = liver_roi_valid and spleen_roi_valid
    has_accurate_measurement = liver_hu_accurate or spleen_hu_accurate
    
    key_criteria_met = True
    fail_reasons = []
    
    if require_both_rois and not rois_placed:
        key_criteria_met = False
        fail_reasons.append("both ROIs not validly placed")
    
    if require_one_measurement and not has_accurate_measurement:
        key_criteria_met = False
        fail_reasons.append("no accurate HU measurement")
    
    if score < min_score:
        key_criteria_met = False
        fail_reasons.append(f"score {score} < {min_score}")
    
    passed = key_criteria_met
    
    if passed:
        feedback_parts.append(f"\n✓ TASK PASSED with score {score}/100")
    else:
        feedback_parts.append(f"\n✗ TASK FAILED: {', '.join(fail_reasons)}")
    
    details['rois_placed'] = rois_placed
    details['has_accurate_measurement'] = has_accurate_measurement
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test run
    result = verify_liver_steatosis({}, {}, {})
    print(json.dumps(result, indent=2))