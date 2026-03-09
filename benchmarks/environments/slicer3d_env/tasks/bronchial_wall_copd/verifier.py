#!/usr/bin/env python3
"""
Verifier for bronchial wall thickness assessment task.

VERIFICATION STRATEGY:
This task has no absolute ground truth (varies by patient), so we verify:
1. Measurement plausibility - are values within physiological bounds?
2. Internal consistency - do measurements make physical sense?
3. Calculation correctness - does WA% match the formula?
4. Classification accuracy - does classification match calculated WA%?
5. Process evidence - were files created during the task?

SCORING (100 points total):
- Outer diameter valid (3-12mm range): 15 points
- Inner diameter valid (< outer): 15 points
- Anatomical plausibility (wall thickness reasonable): 15 points
- WA% calculation correct (±2%): 20 points
- Classification matches WA%: 15 points
- Report completeness: 10 points
- Measurement technique evidence: 10 points

PASS THRESHOLD: 60 points with valid diameter measurements and WA% calculation
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bronchial_wall_copd(traj, env_info, task_info):
    """
    Verify bronchial wall thickness assessment task completion.
    
    Uses copy_from_env to read exported results from container.
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
    
    # Weight configuration
    w_outer = weights.get('outer_diameter_valid', 15)
    w_inner = weights.get('inner_diameter_valid', 15)
    w_anatomical = weights.get('anatomical_location', 15)
    w_calculation = weights.get('wa_calculation_correct', 20)
    w_classification = weights.get('classification_matches', 15)
    w_report = weights.get('report_complete', 10)
    w_technique = weights.get('measurement_technique', 10)
    
    # Expected ranges
    outer_range = metadata.get('expected_outer_diameter_range_mm', [3.0, 12.0])
    wall_thickness_range = metadata.get('expected_wall_thickness_range_mm', [0.3, 4.0])
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/bronchial_task_result.json", temp_result.name)
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
    details = {
        "criteria": {},
        "measurements": {},
        "calculations": {}
    }
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task completion"
        }
    
    # Extract values from result
    outer_d = float(result.get('outer_diameter_mm', 0))
    inner_d = float(result.get('inner_diameter_mm', 0))
    wa_reported = float(result.get('wall_area_percentage_reported', 0))
    wa_expected = float(result.get('wall_area_percentage_expected', 0))
    classification = result.get('classification', '')
    measurement_exists = result.get('measurement_file_exists', False)
    report_exists = result.get('report_file_exists', False)
    meas_created_during_task = result.get('measurement_created_during_task', False)
    report_created_during_task = result.get('report_created_during_task', False)
    
    details["measurements"] = {
        "outer_diameter_mm": outer_d,
        "inner_diameter_mm": inner_d,
        "wall_area_reported": wa_reported,
        "wall_area_calculated": wa_expected,
        "classification": classification
    }
    
    # ================================================================
    # CRITERION 1: Valid outer diameter (15 points)
    # Segmental bronchi are typically 5-8mm, range 3-12mm acceptable
    # ================================================================
    outer_valid = False
    if outer_range[0] <= outer_d <= outer_range[1]:
        score += w_outer
        outer_valid = True
        details["criteria"]["outer_diameter"] = "PASS"
        feedback_parts.append(f"✓ Outer diameter {outer_d:.1f}mm valid (range {outer_range[0]}-{outer_range[1]}mm)")
    elif outer_d > 0:
        # Partial credit for any measurement
        score += w_outer * 0.3
        details["criteria"]["outer_diameter"] = "PARTIAL"
        feedback_parts.append(f"△ Outer diameter {outer_d:.1f}mm outside expected range ({outer_range[0]}-{outer_range[1]}mm)")
    else:
        details["criteria"]["outer_diameter"] = "FAIL"
        feedback_parts.append("✗ No outer diameter measurement found")
    
    # ================================================================
    # CRITERION 2: Valid inner diameter (15 points)
    # Must be positive and less than outer diameter
    # ================================================================
    inner_valid = False
    if inner_d > 0 and inner_d < outer_d:
        score += w_inner
        inner_valid = True
        details["criteria"]["inner_diameter"] = "PASS"
        feedback_parts.append(f"✓ Inner diameter {inner_d:.1f}mm valid (< outer)")
    elif inner_d > 0:
        # Inner >= outer is physically impossible
        score += w_inner * 0.2
        details["criteria"]["inner_diameter"] = "PARTIAL"
        feedback_parts.append(f"△ Inner diameter {inner_d:.1f}mm >= outer diameter (invalid)")
    else:
        details["criteria"]["inner_diameter"] = "FAIL"
        feedback_parts.append("✗ No valid inner diameter measurement found")
    
    # ================================================================
    # CRITERION 3: Anatomical plausibility (15 points)
    # Wall thickness should be reasonable (0.3-4mm typically)
    # ================================================================
    anatomical_score = 0
    if outer_valid and inner_valid:
        wall_thickness = (outer_d - inner_d) / 2
        details["calculations"]["wall_thickness_mm"] = wall_thickness
        
        if wall_thickness_range[0] <= wall_thickness <= wall_thickness_range[1]:
            anatomical_score = w_anatomical
            details["criteria"]["anatomical_plausibility"] = "PASS"
            feedback_parts.append(f"✓ Wall thickness {wall_thickness:.2f}mm anatomically plausible")
        elif 0 < wall_thickness < wall_thickness_range[0] * 0.5:
            anatomical_score = w_anatomical * 0.5
            details["criteria"]["anatomical_plausibility"] = "PARTIAL"
            feedback_parts.append(f"△ Wall thickness {wall_thickness:.2f}mm unusually thin")
        elif wall_thickness > wall_thickness_range[1]:
            anatomical_score = w_anatomical * 0.5
            details["criteria"]["anatomical_plausibility"] = "PARTIAL"
            feedback_parts.append(f"△ Wall thickness {wall_thickness:.2f}mm unusually thick")
        else:
            details["criteria"]["anatomical_plausibility"] = "FAIL"
            feedback_parts.append(f"✗ Wall thickness {wall_thickness:.2f}mm not plausible")
    elif measurement_exists:
        anatomical_score = w_anatomical * 0.3
        details["criteria"]["anatomical_plausibility"] = "PARTIAL"
        feedback_parts.append("△ Measurements incomplete - cannot verify anatomy")
    else:
        details["criteria"]["anatomical_plausibility"] = "FAIL"
        feedback_parts.append("✗ No measurements to verify anatomical plausibility")
    
    score += anatomical_score
    
    # ================================================================
    # CRITERION 4: WA% calculation correct (20 points)
    # Formula: WA% = [(Do² - Di²) / Do²] × 100
    # ================================================================
    calculation_correct = False
    if outer_d > 0 and inner_d > 0 and inner_d < outer_d:
        # Calculate expected WA%
        calculated_wa = ((outer_d**2 - inner_d**2) / outer_d**2) * 100
        details["calculations"]["wa_calculated"] = calculated_wa
        
        if wa_reported > 0:
            wa_error = abs(wa_reported - calculated_wa)
            details["calculations"]["wa_error"] = wa_error
            
            if wa_error <= 2.0:  # Within 2% tolerance
                score += w_calculation
                calculation_correct = True
                details["criteria"]["wa_calculation"] = "PASS"
                feedback_parts.append(f"✓ WA% calculation correct: {wa_reported:.1f}% (expected {calculated_wa:.1f}%)")
            elif wa_error <= 5.0:
                score += w_calculation * 0.6
                details["criteria"]["wa_calculation"] = "PARTIAL"
                feedback_parts.append(f"△ WA% calculation close: {wa_reported:.1f}% (expected {calculated_wa:.1f}%, error {wa_error:.1f}%)")
            else:
                score += w_calculation * 0.2
                details["criteria"]["wa_calculation"] = "PARTIAL"
                feedback_parts.append(f"△ WA% calculation error: reported {wa_reported:.1f}%, expected {calculated_wa:.1f}%")
        elif wa_expected > 0:
            # No reported WA% but we calculated it from diameters
            score += w_calculation * 0.4
            calculation_correct = True  # Give benefit of doubt
            details["criteria"]["wa_calculation"] = "PARTIAL"
            feedback_parts.append(f"△ WA% not explicitly reported but calculable: {calculated_wa:.1f}%")
            wa_reported = calculated_wa  # Use for classification check
        else:
            details["criteria"]["wa_calculation"] = "FAIL"
            feedback_parts.append("✗ No WA% calculation found")
    else:
        details["criteria"]["wa_calculation"] = "FAIL"
        feedback_parts.append("✗ Cannot verify WA% - measurements incomplete")
    
    # ================================================================
    # CRITERION 5: Classification matches WA% (15 points)
    # ================================================================
    def expected_classification(wa_pct):
        """Determine expected classification from WA%."""
        if wa_pct < 60:
            return "normal"
        elif wa_pct < 70:
            return "mild"
        elif wa_pct < 80:
            return "moderate"
        else:
            return "severe"
    
    # Use calculated WA% if reported not available
    reference_wa = wa_reported if wa_reported > 0 else (wa_expected if wa_expected > 0 else 0)
    
    if reference_wa > 0 and classification:
        expected_class = expected_classification(reference_wa)
        classification_lower = classification.lower()
        
        # Check for match (allow flexibility in naming)
        class_matches = (
            (expected_class == "normal" and "normal" in classification_lower) or
            (expected_class == "mild" and ("mild" in classification_lower)) or
            (expected_class == "moderate" and ("moderate" in classification_lower)) or
            (expected_class == "severe" and ("severe" in classification_lower))
        )
        
        if class_matches:
            score += w_classification
            details["criteria"]["classification"] = "PASS"
            feedback_parts.append(f"✓ Classification '{classification}' correct for WA% {reference_wa:.1f}%")
        else:
            # Check if adjacent category (partial credit)
            adjacent = (
                (expected_class == "normal" and "mild" in classification_lower) or
                (expected_class == "mild" and ("normal" in classification_lower or "moderate" in classification_lower)) or
                (expected_class == "moderate" and ("mild" in classification_lower or "severe" in classification_lower)) or
                (expected_class == "severe" and "moderate" in classification_lower)
            )
            if adjacent:
                score += w_classification * 0.5
                details["criteria"]["classification"] = "PARTIAL"
                feedback_parts.append(f"△ Classification '{classification}' adjacent to expected '{expected_class}'")
            else:
                score += w_classification * 0.2
                details["criteria"]["classification"] = "PARTIAL"
                feedback_parts.append(f"△ Classification '{classification}' does not match expected '{expected_class}'")
    elif classification:
        # Classification provided but no WA% to verify
        score += w_classification * 0.3
        details["criteria"]["classification"] = "PARTIAL"
        feedback_parts.append(f"△ Classification '{classification}' provided but cannot verify")
    else:
        details["criteria"]["classification"] = "FAIL"
        feedback_parts.append("✗ No classification provided")
    
    # ================================================================
    # CRITERION 6: Report completeness (10 points)
    # ================================================================
    if report_exists:
        required_fields = ['outer_diameter', 'inner_diameter', 'wall_area', 'classification']
        present_count = 0
        if outer_d > 0:
            present_count += 1
        if inner_d > 0:
            present_count += 1
        if wa_reported > 0 or wa_expected > 0:
            present_count += 1
        if classification:
            present_count += 1
        
        completeness_ratio = present_count / len(required_fields)
        
        if completeness_ratio >= 0.9:
            score += w_report
            details["criteria"]["report_complete"] = "PASS"
            feedback_parts.append(f"✓ Report complete ({present_count}/{len(required_fields)} fields)")
        elif completeness_ratio >= 0.5:
            score += w_report * completeness_ratio
            details["criteria"]["report_complete"] = "PARTIAL"
            feedback_parts.append(f"△ Report partially complete ({present_count}/{len(required_fields)} fields)")
        else:
            score += w_report * 0.2
            details["criteria"]["report_complete"] = "PARTIAL"
            feedback_parts.append(f"△ Report incomplete ({present_count}/{len(required_fields)} fields)")
    else:
        details["criteria"]["report_complete"] = "FAIL"
        feedback_parts.append("✗ Report file not created")
    
    # ================================================================
    # CRITERION 7: Measurement technique evidence (10 points)
    # Evidence that proper workflow was followed
    # ================================================================
    technique_score = 0
    
    if measurement_exists and meas_created_during_task:
        technique_score += w_technique * 0.5
        feedback_parts.append("✓ Measurement file created during task")
    elif measurement_exists:
        technique_score += w_technique * 0.2
        feedback_parts.append("△ Measurement file exists (may be pre-existing)")
    
    if outer_valid and inner_valid and calculation_correct:
        technique_score += w_technique * 0.5
        feedback_parts.append("✓ Measurements show correct technique")
    
    score += technique_score
    if technique_score >= w_technique * 0.7:
        details["criteria"]["technique"] = "PASS"
    elif technique_score > 0:
        details["criteria"]["technique"] = "PARTIAL"
    else:
        details["criteria"]["technique"] = "FAIL"
    
    # ================================================================
    # FINAL SCORING AND PASS DETERMINATION
    # ================================================================
    # Pass requires: score >= 60 AND valid diameter measurements
    min_score = thresholds.get('min_score', 60)
    require_valid_diameters = thresholds.get('require_valid_diameters', True)
    
    key_criteria_met = True
    if require_valid_diameters:
        key_criteria_met = outer_valid and inner_valid
    
    passed = score >= min_score and key_criteria_met
    
    details["final_score"] = score
    details["passed"] = passed
    details["pass_threshold"] = min_score
    details["key_criteria_met"] = key_criteria_met
    
    # Generate summary feedback
    if passed:
        feedback_parts.insert(0, f"✓ TASK PASSED with score {score:.0f}/100")
    else:
        feedback_parts.insert(0, f"✗ TASK FAILED with score {score:.0f}/100")
        if not key_criteria_met:
            feedback_parts.append("Required: valid outer and inner diameter measurements")
        if score < min_score:
            feedback_parts.append(f"Required: score >= {min_score}")
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }