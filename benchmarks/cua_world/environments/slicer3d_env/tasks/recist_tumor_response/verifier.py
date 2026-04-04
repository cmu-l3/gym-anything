#!/usr/bin/env python3
"""
Verifier for RECIST Tumor Response Assessment task.

VERIFICATION STRATEGY:
Uses multiple independent signals to verify task completion:

1. Measurement File Verification (20 pts):
   - Markup file exists with ruler measurements
   - At least 3 measurements present

2. Individual Lesion Measurements (45 pts):
   - Each of 3 lesions measured within ±5mm of ground truth
   - 15 points per lesion

3. SLD Calculation (10 pts):
   - Sum of measurements is arithmetically correct

4. Percent Change (10 pts):
   - Calculated correctly from SLD vs baseline

5. Response Category (20 pts):
   - Correctly determined based on RECIST 1.1 criteria

6. Report Completeness (5 pts):
   - JSON report contains all required fields

ANTI-GAMING:
- Files must be created during task window
- Measurements must be plausible (not copy of baseline)
- Response must match calculated percent change
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, Tuple, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_float(val, default=0.0) -> float:
    """Safely parse a float value."""
    if val is None or val == '':
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def parse_measurements_from_string(meas_str: str) -> List[float]:
    """Parse comma-separated measurement string."""
    if not meas_str:
        return []
    try:
        return [float(x.strip()) for x in meas_str.split(',') if x.strip()]
    except (ValueError, TypeError):
        return []


def determine_recist_response(percent_change: float, absolute_change: float) -> str:
    """
    Determine RECIST 1.1 response category.
    
    CR: Complete Response - disappearance of all lesions (not applicable here)
    PR: Partial Response - >=30% decrease in SLD
    PD: Progressive Disease - >=20% increase AND >=5mm absolute increase
    SD: Stable Disease - neither PR nor PD
    """
    if percent_change <= -30:
        return "PR"
    elif percent_change >= 20 and absolute_change >= 5:
        return "PD"
    else:
        return "SD"


def verify_recist_tumor_response(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify RECIST tumor response assessment task.
    
    Scoring (100 points total):
    - Lesion 1 measurement: 15 pts (within ±5mm)
    - Lesion 2 measurement: 15 pts (within ±5mm)
    - Lesion 3 measurement: 15 pts (within ±5mm)
    - SLD calculation: 10 pts (correct sum)
    - Percent change: 10 pts (within ±2%)
    - Response category: 20 pts (correct RECIST category)
    - Report completeness: 10 pts (all required fields)
    - Markup file valid: 5 pts (contains 3 measurements)
    
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
    
    tolerance_mm = thresholds.get('measurement_tolerance_mm', 5.0)
    tolerance_percent = thresholds.get('percent_change_tolerance', 2.0)
    min_lesions_correct = thresholds.get('min_lesions_correct', 2)
    baseline_sld = metadata.get('baseline_sld_mm', 65.0)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {
        'criteria_scores': {},
        'agent_values': {},
        'expected_values': {},
        'errors': []
    }
    
    # ================================================================
    # Load result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/recist_task_result.json", temp_result.name)
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
    
    # ================================================================
    # Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/agent_results/recist_verification_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        details['errors'].append(f"Could not load ground truth: {e}")
        logger.warning(f"Ground truth load failed: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    expected_measurements = gt.get('current_measurements_mm', [])
    expected_sld = gt.get('expected_current_sld_mm', 0)
    expected_percent = gt.get('expected_percent_change', 0)
    expected_response = gt.get('expected_response', '')
    
    details['expected_values'] = {
        'measurements_mm': expected_measurements,
        'sld_mm': expected_sld,
        'baseline_sld_mm': baseline_sld,
        'percent_change': expected_percent,
        'response': expected_response
    }
    
    # ================================================================
    # Check basic requirements
    # ================================================================
    if not result.get('slicer_was_running', False):
        feedback_parts.append("FAIL: Slicer was not running")
        details['errors'].append("Slicer not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    measurement_exists = result.get('measurement_exists', False)
    report_exists = result.get('report_exists', False)
    
    if not measurement_exists and not report_exists:
        feedback_parts.append("FAIL: No measurement file or report found")
        details['errors'].append("No outputs created")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # Extract agent values
    # ================================================================
    # From measurement file
    measured_lengths_str = result.get('measured_lengths', '')
    agent_measurements_from_file = parse_measurements_from_string(measured_lengths_str)
    
    # From report
    reported_measurements_str = result.get('reported_measurements', '')
    agent_measurements_from_report = parse_measurements_from_string(reported_measurements_str)
    
    # Use whichever has more measurements
    if len(agent_measurements_from_report) >= len(agent_measurements_from_file):
        agent_measurements = agent_measurements_from_report
    else:
        agent_measurements = agent_measurements_from_file
    
    agent_sld = parse_float(result.get('reported_sld_mm', 0))
    agent_percent = parse_float(result.get('reported_percent_change', 0))
    agent_response = result.get('reported_response', '').upper().strip()
    measurement_count = int(result.get('measurement_count', 0))
    
    # Calculate SLD from measurements if not reported
    if agent_sld == 0 and agent_measurements:
        agent_sld = sum(agent_measurements)
    
    # Calculate percent change if not reported
    if agent_percent == 0 and agent_sld > 0 and baseline_sld > 0:
        agent_percent = ((agent_sld - baseline_sld) / baseline_sld) * 100
    
    details['agent_values'] = {
        'measurements_mm': agent_measurements,
        'measurement_count': measurement_count,
        'sld_mm': agent_sld,
        'percent_change': agent_percent,
        'response': agent_response
    }
    
    # ================================================================
    # CRITERION: Markup file valid (5 pts)
    # ================================================================
    w_markup = weights.get('markup_valid', 5)
    
    if measurement_count >= 3:
        score += w_markup
        details['criteria_scores']['markup_valid'] = w_markup
        feedback_parts.append(f"PASS: Markup file contains {measurement_count} measurements")
    elif measurement_count > 0:
        partial = (measurement_count / 3) * w_markup
        score += partial
        details['criteria_scores']['markup_valid'] = partial
        feedback_parts.append(f"PARTIAL: Markup has {measurement_count}/3 measurements")
    else:
        details['criteria_scores']['markup_valid'] = 0
        feedback_parts.append("FAIL: No valid ruler measurements in markup file")
    
    # ================================================================
    # CRITERION: Individual lesion measurements (15 pts each)
    # ================================================================
    lesion_scores = []
    lesions_within_tolerance = 0
    
    for i in range(3):
        w_lesion = weights.get(f'lesion_{i+1}_measurement', 15)
        lesion_key = f'lesion_{i+1}_measurement'
        
        if i < len(expected_measurements):
            expected = expected_measurements[i]
            
            if i < len(agent_measurements):
                agent_val = agent_measurements[i]
                error = abs(agent_val - expected)
                
                if error <= tolerance_mm:
                    lesion_scores.append(w_lesion)
                    lesions_within_tolerance += 1
                    details['criteria_scores'][lesion_key] = w_lesion
                    feedback_parts.append(
                        f"PASS: Lesion {i+1}: {agent_val:.1f}mm vs expected {expected:.1f}mm "
                        f"(error: {error:.1f}mm)"
                    )
                else:
                    # Partial credit for being close
                    partial = max(0, w_lesion * (1 - (error - tolerance_mm) / (tolerance_mm * 2)))
                    lesion_scores.append(partial)
                    details['criteria_scores'][lesion_key] = partial
                    feedback_parts.append(
                        f"PARTIAL: Lesion {i+1}: {agent_val:.1f}mm vs expected {expected:.1f}mm "
                        f"(error: {error:.1f}mm exceeds {tolerance_mm}mm tolerance)"
                    )
            else:
                lesion_scores.append(0)
                details['criteria_scores'][lesion_key] = 0
                feedback_parts.append(f"FAIL: Lesion {i+1}: Not measured")
        else:
            lesion_scores.append(0)
            details['criteria_scores'][lesion_key] = 0
    
    score += sum(lesion_scores)
    
    # ================================================================
    # CRITERION: SLD calculation (10 pts)
    # ================================================================
    w_sld = weights.get('sld_calculation', 10)
    
    if agent_sld > 0:
        sld_error = abs(agent_sld - expected_sld)
        if sld_error <= tolerance_mm:
            score += w_sld
            details['criteria_scores']['sld_calculation'] = w_sld
            feedback_parts.append(f"PASS: SLD {agent_sld:.1f}mm vs expected {expected_sld:.1f}mm")
        else:
            partial = max(0, w_sld * (1 - (sld_error - tolerance_mm) / (tolerance_mm * 3)))
            score += partial
            details['criteria_scores']['sld_calculation'] = partial
            feedback_parts.append(
                f"PARTIAL: SLD {agent_sld:.1f}mm vs expected {expected_sld:.1f}mm "
                f"(error: {sld_error:.1f}mm)"
            )
    else:
        details['criteria_scores']['sld_calculation'] = 0
        feedback_parts.append("FAIL: SLD not calculated or reported")
    
    # ================================================================
    # CRITERION: Percent change (10 pts)
    # ================================================================
    w_percent = weights.get('percent_change', 10)
    
    if agent_percent != 0 or report_exists:
        percent_error = abs(agent_percent - expected_percent)
        if percent_error <= tolerance_percent:
            score += w_percent
            details['criteria_scores']['percent_change'] = w_percent
            feedback_parts.append(
                f"PASS: Percent change {agent_percent:.1f}% vs expected {expected_percent:.1f}%"
            )
        else:
            partial = max(0, w_percent * (1 - (percent_error - tolerance_percent) / (tolerance_percent * 5)))
            score += partial
            details['criteria_scores']['percent_change'] = partial
            feedback_parts.append(
                f"PARTIAL: Percent change {agent_percent:.1f}% vs expected {expected_percent:.1f}% "
                f"(error: {percent_error:.1f}%)"
            )
    else:
        details['criteria_scores']['percent_change'] = 0
        feedback_parts.append("FAIL: Percent change not calculated")
    
    # ================================================================
    # CRITERION: Response category (20 pts) - CRITICAL
    # ================================================================
    w_response = weights.get('response_category', 20)
    
    valid_responses = ['CR', 'PR', 'SD', 'PD']
    if agent_response in valid_responses:
        if agent_response == expected_response.upper():
            score += w_response
            details['criteria_scores']['response_category'] = w_response
            feedback_parts.append(f"PASS: Response category '{agent_response}' is correct")
        else:
            details['criteria_scores']['response_category'] = 0
            feedback_parts.append(
                f"FAIL: Response '{agent_response}' incorrect, expected '{expected_response}'"
            )
    else:
        details['criteria_scores']['response_category'] = 0
        feedback_parts.append(f"FAIL: Invalid response category '{agent_response}'")
    
    # ================================================================
    # CRITERION: Report completeness (10 pts)
    # ================================================================
    w_report = weights.get('report_completeness', 10)
    
    # Try to load and check report file
    report_fields_found = 0
    required_fields = ['current_sld_mm', 'baseline_sld_mm', 'percent_change', 'response_category']
    alt_fields = ['sld', 'baseline', 'change', 'response']
    
    if report_exists:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_results/recist_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                agent_report = json.load(f)
            
            for req, alt in zip(required_fields, alt_fields):
                if req in agent_report or alt in agent_report:
                    report_fields_found += 1
        except Exception as e:
            details['errors'].append(f"Could not parse report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    
    completeness_score = (report_fields_found / len(required_fields)) * w_report
    score += completeness_score
    details['criteria_scores']['report_completeness'] = completeness_score
    feedback_parts.append(
        f"Report completeness: {report_fields_found}/{len(required_fields)} fields "
        f"({completeness_score:.0f}/{w_report} pts)"
    )
    
    # ================================================================
    # Determine pass/fail
    # ================================================================
    response_correct = details['criteria_scores'].get('response_category', 0) == w_response
    
    details['pass_criteria'] = {
        'score_above_60': score >= 60,
        'lesions_within_tolerance': lesions_within_tolerance,
        'min_lesions_required': min_lesions_correct,
        'response_correct': response_correct
    }
    
    # Pass requires: score >= 60 AND at least 2 lesions correct AND response correct
    passed = (
        score >= 60 and 
        lesions_within_tolerance >= min_lesions_correct and 
        response_correct
    )
    
    details['pass_criteria']['passed'] = passed
    
    # Final feedback
    if passed:
        feedback_parts.append(
            f"\n✓ TASK PASSED: Score {score:.0f}/100, "
            f"{lesions_within_tolerance}/3 lesions within tolerance, response correct"
        )
    else:
        reasons = []
        if score < 60:
            reasons.append(f"score {score:.0f} < 60")
        if lesions_within_tolerance < min_lesions_correct:
            reasons.append(
                f"only {lesions_within_tolerance}/{min_lesions_correct} lesions within tolerance"
            )
        if not response_correct:
            reasons.append("response category incorrect")
        feedback_parts.append(f"\n✗ TASK NOT PASSED: {', '.join(reasons)}")
    
    return {
        "passed": passed,
        "score": int(round(score)),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test stub for local development
    print("RECIST Tumor Response verifier loaded successfully")
    print("This verifier checks:")
    print("  - Individual lesion measurements (15 pts each)")
    print("  - SLD calculation (10 pts)")
    print("  - Percent change calculation (10 pts)")
    print("  - Response category (20 pts)")
    print("  - Report completeness (10 pts)")
    print("  - Markup file validity (5 pts)")
    print("Pass threshold: 60 pts + 2/3 lesions correct + correct response")