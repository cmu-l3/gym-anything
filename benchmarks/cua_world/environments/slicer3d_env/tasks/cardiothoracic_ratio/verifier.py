#!/usr/bin/env python3
"""
Verifier for cardiothoracic ratio (CTR) measurement task.

VERIFICATION CRITERIA:
1. Cardiac diameter valid (15 points) - measurement exists and in plausible range
2. Thoracic diameter valid (15 points) - measurement exists and in plausible range
3. Same level measurements (10 points) - both measurements at similar z-coordinate
4. CTR calculation correct (20 points) - reported CTR matches calculated from measurements
5. CTR in expected range (15 points) - CTR within tolerance of reference
6. Classification correct (15 points) - clinical category matches CTR value
7. Report complete (10 points) - JSON report contains all required fields

Pass threshold: 65 points with cardiac/thoracic valid and CTR calculation correct
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cardiothoracic_ratio(traj, env_info, task_info):
    """
    Verify CTR measurement task completion.

    Uses multi-criteria scoring with anatomical plausibility checks.
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
    cardiac_range = metadata.get('cardiac_diameter_range_mm', {"min": 80, "max": 200})
    thoracic_range = metadata.get('thoracic_diameter_range_mm', {"min": 200, "max": 400})
    ctr_tolerance = metadata.get('ctr_tolerance', 0.02)
    reference_tolerance_pct = metadata.get('reference_tolerance_percent', 15)
    
    weights = metadata.get('scoring_weights', {})
    w_cardiac = weights.get('cardiac_diameter_valid', 15)
    w_thoracic = weights.get('thoracic_diameter_valid', 15)
    w_same_level = weights.get('same_level_measurements', 10)
    w_ctr_calc = weights.get('ctr_calculation_correct', 20)
    w_ctr_range = weights.get('ctr_in_expected_range', 15)
    w_classification = weights.get('classification_correct', 15)
    w_report = weights.get('report_complete', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/ctr_task_result.json", temp_result.name)
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

    # ============================================================
    # LOAD GROUND TRUTH REFERENCE
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/ctr_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    ref_cardiac = gt_data.get('reference_cardiac_diameter_mm', 0)
    ref_thoracic = gt_data.get('reference_thoracic_diameter_mm', 0)
    ref_ctr = gt_data.get('reference_ctr', 0)
    ref_classification = gt_data.get('expected_classification', '')

    details['ref_cardiac_mm'] = ref_cardiac
    details['ref_thoracic_mm'] = ref_thoracic
    details['ref_ctr'] = ref_ctr
    details['ref_classification'] = ref_classification

    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    
    # Try to get cardiac diameter from various sources
    cardiac_diameter = 0.0
    for key in ['extracted_cardiac_diameter_mm', 'reported_cardiac_diameter_mm']:
        val = result.get(key, '')
        if val:
            try:
                cardiac_diameter = float(val)
                if cardiac_diameter > 0:
                    break
            except (ValueError, TypeError):
                pass

    # Try to get thoracic diameter
    thoracic_diameter = 0.0
    for key in ['extracted_thoracic_diameter_mm', 'reported_thoracic_diameter_mm']:
        val = result.get(key, '')
        if val:
            try:
                thoracic_diameter = float(val)
                if thoracic_diameter > 0:
                    break
            except (ValueError, TypeError):
                pass

    # Get reported CTR
    reported_ctr = 0.0
    for key in ['reported_ctr', 'calculated_ctr']:
        val = result.get(key, '')
        if val:
            try:
                reported_ctr = float(val)
                if reported_ctr > 0:
                    break
            except (ValueError, TypeError):
                pass

    reported_classification = result.get('reported_classification', '')
    same_level = result.get('same_level_measurements', False)
    report_exists = result.get('report_exists', False)

    details['agent_cardiac_mm'] = cardiac_diameter
    details['agent_thoracic_mm'] = thoracic_diameter
    details['agent_ctr'] = reported_ctr
    details['agent_classification'] = reported_classification

    # ============================================================
    # CRITERION 1: Cardiac diameter valid (15 points)
    # ============================================================
    cardiac_valid = False
    cardiac_min = cardiac_range.get('min', 80)
    cardiac_max = cardiac_range.get('max', 200)
    
    if cardiac_diameter > 0:
        if cardiac_min <= cardiac_diameter <= cardiac_max:
            score += w_cardiac
            feedback_parts.append(f"✓ Cardiac diameter valid: {cardiac_diameter:.1f}mm")
            cardiac_valid = True
        else:
            # Partial credit for measurement outside range but exists
            score += w_cardiac * 0.3
            feedback_parts.append(f"⚠ Cardiac diameter out of range: {cardiac_diameter:.1f}mm (expected {cardiac_min}-{cardiac_max}mm)")
    else:
        feedback_parts.append("✗ No cardiac diameter measurement found")

    # ============================================================
    # CRITERION 2: Thoracic diameter valid (15 points)
    # ============================================================
    thoracic_valid = False
    thoracic_min = thoracic_range.get('min', 200)
    thoracic_max = thoracic_range.get('max', 400)
    
    if thoracic_diameter > 0:
        if thoracic_min <= thoracic_diameter <= thoracic_max:
            score += w_thoracic
            feedback_parts.append(f"✓ Thoracic diameter valid: {thoracic_diameter:.1f}mm")
            thoracic_valid = True
        else:
            score += w_thoracic * 0.3
            feedback_parts.append(f"⚠ Thoracic diameter out of range: {thoracic_diameter:.1f}mm (expected {thoracic_min}-{thoracic_max}mm)")
    else:
        feedback_parts.append("✗ No thoracic diameter measurement found")

    # ============================================================
    # CRITERION 3: Same level measurements (10 points)
    # ============================================================
    if same_level:
        score += w_same_level
        feedback_parts.append("✓ Measurements taken at same level")
    elif cardiac_diameter > 0 and thoracic_diameter > 0:
        # Partial credit if both exist but level unknown
        score += w_same_level * 0.5
        feedback_parts.append("⚠ Measurement levels could not be verified")
    else:
        feedback_parts.append("✗ Cannot verify measurement levels")

    # ============================================================
    # CRITERION 4: CTR calculation correct (20 points)
    # ============================================================
    ctr_calc_correct = False
    calculated_ctr = 0.0
    
    if cardiac_diameter > 0 and thoracic_diameter > 0:
        calculated_ctr = cardiac_diameter / thoracic_diameter
        details['calculated_ctr_from_measurements'] = round(calculated_ctr, 4)
        
        if reported_ctr > 0:
            ctr_diff = abs(reported_ctr - calculated_ctr)
            if ctr_diff <= ctr_tolerance:
                score += w_ctr_calc
                feedback_parts.append(f"✓ CTR calculation correct: {reported_ctr:.3f}")
                ctr_calc_correct = True
            else:
                # Partial credit for close calculation
                score += w_ctr_calc * max(0, (1 - ctr_diff / 0.1))
                feedback_parts.append(f"⚠ CTR mismatch: reported {reported_ctr:.3f}, calculated {calculated_ctr:.3f}")
        else:
            # If CTR not reported, use calculated value
            reported_ctr = calculated_ctr
            score += w_ctr_calc * 0.5
            feedback_parts.append(f"⚠ CTR not explicitly reported (calculated: {calculated_ctr:.3f})")
    else:
        feedback_parts.append("✗ Cannot calculate CTR - missing measurements")

    # ============================================================
    # CRITERION 5: CTR in expected range (15 points)
    # ============================================================
    if reported_ctr > 0 and ref_ctr > 0:
        ctr_error_pct = abs(reported_ctr - ref_ctr) / ref_ctr * 100
        details['ctr_error_percent'] = round(ctr_error_pct, 1)
        
        if ctr_error_pct <= reference_tolerance_pct:
            score += w_ctr_range
            feedback_parts.append(f"✓ CTR within reference range ({ctr_error_pct:.1f}% error)")
        elif ctr_error_pct <= reference_tolerance_pct * 2:
            score += w_ctr_range * 0.5
            feedback_parts.append(f"⚠ CTR moderately differs from reference ({ctr_error_pct:.1f}% error)")
        else:
            feedback_parts.append(f"✗ CTR significantly differs from reference ({ctr_error_pct:.1f}% error)")
    elif reported_ctr > 0:
        # No reference, just check if CTR is physiologically plausible
        if 0.3 <= reported_ctr <= 0.8:
            score += w_ctr_range * 0.5
            feedback_parts.append(f"⚠ CTR plausible ({reported_ctr:.3f}) but no reference available")
        else:
            feedback_parts.append(f"✗ CTR {reported_ctr:.3f} is not physiologically plausible")

    # ============================================================
    # CRITERION 6: Classification correct (15 points)
    # ============================================================
    # Determine expected classification from reported CTR
    expected_classification = ""
    ctr_for_classification = reported_ctr if reported_ctr > 0 else calculated_ctr
    
    if ctr_for_classification > 0:
        if ctr_for_classification < 0.50:
            expected_classification = "Normal"
        elif ctr_for_classification <= 0.55:
            expected_classification = "Borderline"
        else:
            expected_classification = "Cardiomegaly"
        
        details['expected_classification_from_ctr'] = expected_classification
        
        if reported_classification:
            # Normalize classification string
            norm_reported = reported_classification.lower().strip()
            norm_expected = expected_classification.lower()
            
            if norm_reported == norm_expected or norm_reported in norm_expected or norm_expected in norm_reported:
                score += w_classification
                feedback_parts.append(f"✓ Classification correct: {reported_classification}")
            else:
                feedback_parts.append(f"✗ Classification incorrect: reported '{reported_classification}', expected '{expected_classification}'")
        else:
            feedback_parts.append(f"✗ No classification reported (expected: {expected_classification})")
    else:
        feedback_parts.append("✗ Cannot verify classification - no CTR value")

    # ============================================================
    # CRITERION 7: Report completeness (10 points)
    # ============================================================
    if report_exists:
        # Check for required fields
        has_cardiac = result.get('reported_cardiac_diameter_mm', '') != ''
        has_thoracic = result.get('reported_thoracic_diameter_mm', '') != ''
        has_ctr = result.get('reported_ctr', '') != ''
        has_classification = result.get('reported_classification', '') != ''
        
        fields_present = sum([has_cardiac, has_thoracic, has_ctr, has_classification])
        
        if fields_present >= 4:
            score += w_report
            feedback_parts.append("✓ Report complete with all required fields")
        elif fields_present >= 2:
            score += w_report * (fields_present / 4)
            feedback_parts.append(f"⚠ Report partially complete ({fields_present}/4 fields)")
        else:
            feedback_parts.append("✗ Report missing most required fields")
    else:
        feedback_parts.append("✗ No report file found")

    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    max_score = w_cardiac + w_thoracic + w_same_level + w_ctr_calc + w_ctr_range + w_classification + w_report
    
    # Key criteria: both measurements valid AND CTR calculation attempted
    key_criteria_met = cardiac_valid and thoracic_valid and (reported_ctr > 0 or calculated_ctr > 0)
    
    # Pass threshold: 65% AND key criteria
    passed = (score >= 65) and key_criteria_met

    # Compile feedback
    score_pct = (score / max_score) * 100
    feedback = f"Score: {score}/{max_score} ({score_pct:.0f}%) | " + " | ".join(feedback_parts)

    # Summary
    if passed:
        feedback = f"✓ PASSED - {feedback}"
    else:
        if not key_criteria_met:
            feedback = f"✗ FAILED (key criteria not met) - {feedback}"
        else:
            feedback = f"✗ FAILED (score below threshold) - {feedback}"

    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }