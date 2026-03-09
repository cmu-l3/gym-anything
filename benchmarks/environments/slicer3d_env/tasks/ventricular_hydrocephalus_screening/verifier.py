#!/usr/bin/env python3
"""
Verifier for Brain Ventricular Volume Assessment task.

VERIFICATION STRATEGY (Multi-Signal):
1. Segmentation exists and has plausible volume (25 pts)
2. Segmentation created during task - anti-gaming (included in above)
3. Ruler measurements exist and are valid (20 pts)
4. Evans' Index calculated correctly (15 pts)
5. Classification is consistent with measurements (15 pts)
6. Report is complete and internally consistent (15 pts)
7. Volume reported matches segmentation (5 pts)
8. Anatomical location check (5 pts)

Pass Threshold: 60 points with segmentation_exists AND volume_plausible
"""

import json
import os
import sys
import tempfile
import shutil
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ventricular_assessment(traj, env_info, task_info):
    """
    Verify ventricular volume assessment task completion.
    
    Uses copy_from_env to read exported results from container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get metadata with expected ranges
    metadata = task_info.get('metadata', {})
    expected_ranges = metadata.get('expected_ranges', {
        "ventricular_volume_ml": {"min": 5, "max": 100},
        "frontal_horn_width_mm": {"min": 15, "max": 60},
        "internal_skull_diameter_mm": {"min": 100, "max": 180},
        "evans_index": {"min": 0.15, "max": 0.50}
    })
    
    weights = metadata.get('scoring_weights', {
        "segmentation_exists": 10,
        "volume_plausible": 15,
        "location_valid": 10,
        "frontal_ruler_valid": 10,
        "skull_ruler_valid": 10,
        "evans_valid": 15,
        "classification_valid": 15,
        "report_complete": 10,
        "volume_match": 5
    })
    
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    # ================================================================
    # LOAD TASK RESULT FROM CONTAINER
    # ================================================================
    temp_dir = tempfile.mkdtemp()
    result = {}
    
    try:
        result_path = os.path.join(temp_dir, "task_result.json")
        copy_from_env("/tmp/ventricle_task_result.json", result_path)
        with open(result_path, 'r') as f:
            result = json.load(f)
        logger.info(f"Loaded task result: {json.dumps(result, indent=2)[:500]}")
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task result file not found - export script may have failed"
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
            "feedback": f"Failed to read task result: {e}"
        }
    
    # ================================================================
    # LOAD GROUND TRUTH (for reference ranges)
    # ================================================================
    gt_data = {}
    try:
        gt_path = os.path.join(temp_dir, "ground_truth.json")
        copy_from_env("/tmp/ground_truth.json", gt_path)
        with open(gt_path, 'r') as f:
            gt_data = json.load(f)
        expected_ranges = gt_data.get('expected_ranges', expected_ranges)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    
    # ================================================================
    # LOAD AGENT REPORT (if exists)
    # ================================================================
    report_data = {}
    try:
        report_path = os.path.join(temp_dir, "agent_report.json")
        copy_from_env("/tmp/agent_report.json", report_path)
        with open(report_path, 'r') as f:
            report_data = json.load(f)
        logger.info(f"Loaded agent report: {report_data}")
    except Exception as e:
        logger.info(f"No agent report found: {e}")
    
    # ================================================================
    # CRITERION 1: Segmentation Exists (10 points)
    # ================================================================
    seg_exists = result.get('segmentation_exists', False)
    seg_created_during_task = result.get('segmentation_created_during_task', False)
    
    if seg_exists:
        if seg_created_during_task:
            score += weights.get('segmentation_exists', 10)
            feedback_parts.append("✓ Segmentation file created during task (10 pts)")
            details["segmentation_exists"] = True
        else:
            # Partial credit - file exists but may have been pre-existing
            score += weights.get('segmentation_exists', 10) // 2
            feedback_parts.append("~ Segmentation exists but may not be newly created (5 pts)")
            details["segmentation_exists"] = "partial"
    else:
        feedback_parts.append("✗ Segmentation file not found (0 pts)")
        details["segmentation_exists"] = False
    
    # ================================================================
    # CRITERION 2: Volume Plausible (15 points)
    # ================================================================
    volume = result.get('segmentation_volume_ml', 0)
    vol_range = expected_ranges.get('ventricular_volume_ml', {"min": 5, "max": 100})
    
    details["segmentation_volume_ml"] = volume
    
    if volume > 0:
        if vol_range["min"] <= volume <= vol_range["max"]:
            score += weights.get('volume_plausible', 15)
            feedback_parts.append(f"✓ Ventricular volume {volume:.1f} mL is anatomically plausible (15 pts)")
            details["volume_plausible"] = True
        elif 2 <= volume <= 150:
            # Partial credit - volume exists but outside typical range
            partial = weights.get('volume_plausible', 15) // 2
            score += partial
            feedback_parts.append(f"~ Volume {volume:.1f} mL exists but outside typical range {vol_range['min']}-{vol_range['max']} mL ({partial} pts)")
            details["volume_plausible"] = "partial"
        else:
            feedback_parts.append(f"✗ Volume {volume:.1f} mL is not anatomically reasonable (0 pts)")
            details["volume_plausible"] = False
    else:
        feedback_parts.append("✗ Could not compute segmentation volume (0 pts)")
        details["volume_plausible"] = False
    
    # ================================================================
    # CRITERION 3: Segmentation Location Valid (10 points)
    # ================================================================
    centroid = result.get('segmentation_centroid_normalized', [])
    
    if centroid and len(centroid) == 3 and volume > 0:
        # Ventricles should be roughly centered in the brain
        # Expect centroid around (0.4-0.6, 0.3-0.7, 0.3-0.7) normalized
        cx, cy, cz = centroid
        location_ok = (0.3 <= cx <= 0.7 and 0.2 <= cy <= 0.8 and 0.2 <= cz <= 0.8)
        
        if location_ok:
            score += weights.get('location_valid', 10)
            feedback_parts.append(f"✓ Segmentation in expected ventricular region (10 pts)")
            details["location_valid"] = True
        else:
            feedback_parts.append(f"~ Segmentation centroid at {centroid} may not be in ventricle region (0 pts)")
            details["location_valid"] = False
    elif vol_range["min"] <= volume <= vol_range["max"]:
        # If volume is reasonable, give partial location credit
        partial = weights.get('location_valid', 10) // 2
        score += partial
        feedback_parts.append(f"~ Location check inconclusive, using volume as proxy ({partial} pts)")
        details["location_valid"] = "partial"
    else:
        feedback_parts.append("✗ Cannot verify segmentation location (0 pts)")
        details["location_valid"] = False
    
    # ================================================================
    # CRITERION 4: Frontal Horn Ruler Valid (10 points)
    # ================================================================
    frontal_exists = result.get('frontal_ruler_exists', False)
    frontal = result.get('frontal_horn_width_mm', 0)
    frontal_range = expected_ranges.get('frontal_horn_width_mm', {"min": 15, "max": 60})
    
    details["frontal_horn_width_mm"] = frontal
    
    if frontal_exists and frontal > 0:
        if frontal_range["min"] <= frontal <= frontal_range["max"]:
            score += weights.get('frontal_ruler_valid', 10)
            feedback_parts.append(f"✓ Frontal horn measurement {frontal:.1f} mm is valid (10 pts)")
            details["frontal_ruler_valid"] = True
        elif 10 <= frontal <= 80:
            partial = weights.get('frontal_ruler_valid', 10) // 2
            score += partial
            feedback_parts.append(f"~ Frontal horn measurement {frontal:.1f} mm exists but outside typical range ({partial} pts)")
            details["frontal_ruler_valid"] = "partial"
        else:
            feedback_parts.append(f"✗ Frontal horn measurement {frontal:.1f} mm is not anatomically valid (0 pts)")
            details["frontal_ruler_valid"] = False
    else:
        feedback_parts.append("✗ Frontal horn ruler not found (0 pts)")
        details["frontal_ruler_valid"] = False
    
    # ================================================================
    # CRITERION 5: Skull Diameter Ruler Valid (10 points)
    # ================================================================
    skull_exists = result.get('skull_ruler_exists', False)
    skull = result.get('skull_diameter_mm', 0)
    skull_range = expected_ranges.get('internal_skull_diameter_mm', {"min": 100, "max": 180})
    
    details["skull_diameter_mm"] = skull
    
    if skull_exists and skull > 0:
        if skull_range["min"] <= skull <= skull_range["max"]:
            score += weights.get('skull_ruler_valid', 10)
            feedback_parts.append(f"✓ Skull diameter measurement {skull:.1f} mm is valid (10 pts)")
            details["skull_ruler_valid"] = True
        elif 80 <= skull <= 200:
            partial = weights.get('skull_ruler_valid', 10) // 2
            score += partial
            feedback_parts.append(f"~ Skull diameter measurement {skull:.1f} mm exists but outside typical range ({partial} pts)")
            details["skull_ruler_valid"] = "partial"
        else:
            feedback_parts.append(f"✗ Skull diameter measurement {skull:.1f} mm is not anatomically valid (0 pts)")
            details["skull_ruler_valid"] = False
    else:
        feedback_parts.append("✗ Skull diameter ruler not found (0 pts)")
        details["skull_ruler_valid"] = False
    
    # ================================================================
    # CRITERION 6: Evans' Index Valid (15 points)
    # ================================================================
    evans_range = expected_ranges.get('evans_index', {"min": 0.15, "max": 0.50})
    calculated_evans = 0
    
    if frontal > 0 and skull > 0:
        calculated_evans = round(frontal / skull, 3)
        details["evans_index_calculated"] = calculated_evans
        
        if evans_range["min"] <= calculated_evans <= evans_range["max"]:
            score += weights.get('evans_valid', 15)
            feedback_parts.append(f"✓ Evans' Index {calculated_evans:.3f} is in valid range (15 pts)")
            details["evans_valid"] = True
        elif 0.10 <= calculated_evans <= 0.60:
            partial = weights.get('evans_valid', 15) // 2
            score += partial
            feedback_parts.append(f"~ Evans' Index {calculated_evans:.3f} exists but outside typical range ({partial} pts)")
            details["evans_valid"] = "partial"
        else:
            feedback_parts.append(f"✗ Evans' Index {calculated_evans:.3f} is not anatomically valid (0 pts)")
            details["evans_valid"] = False
    else:
        feedback_parts.append("✗ Cannot calculate Evans' Index - missing measurements (0 pts)")
        details["evans_valid"] = False
        details["evans_index_calculated"] = 0
    
    # ================================================================
    # CRITERION 7: Classification Consistent (15 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    
    if report_data or report_exists:
        # Get classification from report or result
        classification = (report_data.get('classification', '') or 
                         result.get('reported_classification', '')).lower().strip()
        reported_evans = report_data.get('evans_index', result.get('reported_evans_index', ''))
        reported_volume = report_data.get('ventricular_volume_ml', 
                                          result.get('reported_volume_ml', ''))
        
        # Convert to float if possible
        try:
            reported_evans = float(reported_evans) if reported_evans else calculated_evans
        except:
            reported_evans = calculated_evans
        
        try:
            reported_volume = float(reported_volume) if reported_volume else volume
        except:
            reported_volume = volume
        
        details["reported_classification"] = classification
        
        # Determine expected classification based on measurements
        expected_class = "normal"
        check_volume = reported_volume if reported_volume > 0 else volume
        check_evans = reported_evans if reported_evans > 0 else calculated_evans
        
        if check_volume > 60 or check_evans > 0.37:
            expected_class = "severe"
        elif check_volume > 40 or check_evans > 0.33:
            expected_class = "moderate"
        elif check_volume > 20 or check_evans > 0.30:
            expected_class = "mild"
        
        details["expected_classification"] = expected_class
        
        if classification:
            # Check if classification matches expected
            if expected_class in classification or classification in expected_class:
                score += weights.get('classification_valid', 15)
                feedback_parts.append(f"✓ Classification '{classification}' is consistent with measurements (15 pts)")
                details["classification_valid"] = True
            elif classification in ['normal', 'mild', 'moderate', 'severe']:
                # Valid classification but may not match measurements exactly
                partial = weights.get('classification_valid', 15) // 2
                score += partial
                feedback_parts.append(f"~ Classification '{classification}' provided (expected ~{expected_class}) ({partial} pts)")
                details["classification_valid"] = "partial"
            else:
                feedback_parts.append(f"✗ Classification '{classification}' not recognized (0 pts)")
                details["classification_valid"] = False
        else:
            feedback_parts.append("✗ No classification provided in report (0 pts)")
            details["classification_valid"] = False
    else:
        feedback_parts.append("✗ Report not found - classification not available (0 pts)")
        details["classification_valid"] = False
    
    # ================================================================
    # CRITERION 8: Report Complete (10 points)
    # ================================================================
    required_fields = ["ventricular_volume_ml", "frontal_horn_width_mm", 
                       "internal_skull_diameter_mm", "evans_index", "classification"]
    
    if report_data:
        present_fields = []
        for field in required_fields:
            # Check various field name variants
            if field in report_data:
                present_fields.append(field)
            elif field.replace('_', '') in str(report_data).lower():
                present_fields.append(field)
        
        field_ratio = len(present_fields) / len(required_fields)
        details["report_fields_present"] = present_fields
        details["report_fields_required"] = required_fields
        
        if field_ratio >= 0.8:
            score += weights.get('report_complete', 10)
            feedback_parts.append(f"✓ Report contains {len(present_fields)}/{len(required_fields)} required fields (10 pts)")
            details["report_complete"] = True
        elif field_ratio >= 0.4:
            partial = int(weights.get('report_complete', 10) * field_ratio)
            score += partial
            feedback_parts.append(f"~ Report has {len(present_fields)}/{len(required_fields)} required fields ({partial} pts)")
            details["report_complete"] = "partial"
        else:
            feedback_parts.append(f"✗ Report missing most required fields ({len(present_fields)}/{len(required_fields)}) (0 pts)")
            details["report_complete"] = False
    elif result.get('report_exists', False):
        # Report exists but couldn't be parsed as JSON
        partial = weights.get('report_complete', 10) // 2
        score += partial
        feedback_parts.append(f"~ Report file exists but format unclear ({partial} pts)")
        details["report_complete"] = "partial"
    else:
        feedback_parts.append("✗ Report file not found (0 pts)")
        details["report_complete"] = False
    
    # ================================================================
    # CRITERION 9: Volume Match (5 points)
    # ================================================================
    if report_data and volume > 0:
        reported_vol_str = report_data.get('ventricular_volume_ml', 
                                           report_data.get('volume_ml', 
                                           report_data.get('volume', '')))
        try:
            reported_vol = float(reported_vol_str) if reported_vol_str else 0
        except:
            reported_vol = 0
        
        if reported_vol > 0:
            diff_pct = abs(reported_vol - volume) / volume * 100 if volume > 0 else 100
            details["reported_volume_ml"] = reported_vol
            details["computed_volume_ml"] = volume
            details["volume_diff_percent"] = round(diff_pct, 1)
            
            if diff_pct <= 15:
                score += weights.get('volume_match', 5)
                feedback_parts.append(f"✓ Reported volume matches segmentation within 15% (5 pts)")
                details["volume_match"] = True
            elif diff_pct <= 30:
                partial = weights.get('volume_match', 5) // 2
                score += partial
                feedback_parts.append(f"~ Reported volume differs by {diff_pct:.0f}% from segmentation ({partial} pts)")
                details["volume_match"] = "partial"
            else:
                feedback_parts.append(f"✗ Reported volume differs significantly ({diff_pct:.0f}%) (0 pts)")
                details["volume_match"] = False
        else:
            feedback_parts.append("~ Volume not reported in expected format (0 pts)")
            details["volume_match"] = False
    else:
        feedback_parts.append("~ Volume match cannot be verified (0 pts)")
        details["volume_match"] = False
    
    # ================================================================
    # CLEANUP
    # ================================================================
    try:
        shutil.rmtree(temp_dir)
    except:
        pass
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Pass requires: 60 points AND segmentation exists AND volume plausible
    key_criteria_met = (
        details.get("segmentation_exists", False) in [True, "partial"] and
        details.get("volume_plausible", False) in [True, "partial"]
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback_str = "\n".join(feedback_parts)
    feedback_str += f"\n\n{'='*50}"
    feedback_str += f"\nFinal Score: {score}/{max_score}"
    feedback_str += f"\nKey Criteria Met: {key_criteria_met}"
    feedback_str += f"\nPassed: {passed}"
    
    if not passed:
        if score >= 60 and not key_criteria_met:
            feedback_str += "\n\nNote: Score >= 60 but key criteria (segmentation + plausible volume) not met"
        elif score < 60:
            feedback_str += f"\n\nNote: Score {score} is below passing threshold of 60"
    
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": feedback_str,
        "details": details
    }


if __name__ == "__main__":
    # Test verification locally
    print("Running local verification test...")
    
    # Mock env_info without copy_from_env for local testing
    class MockCopyFromEnv:
        def __call__(self, src, dst):
            import shutil
            if os.path.exists(src):
                shutil.copy(src, dst)
            else:
                raise FileNotFoundError(f"Source file not found: {src}")
    
    mock_env_info = {'copy_from_env': MockCopyFromEnv()}
    mock_task_info = {'metadata': {}}
    
    result = verify_ventricular_assessment({}, mock_env_info, mock_task_info)
    print(json.dumps(result, indent=2))