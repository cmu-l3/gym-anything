#!/usr/bin/env python3
"""
Verifier for PA:Aorta Ratio Assessment task.

VERIFICATION STRATEGY:
This task requires the agent to:
1. Measure main pulmonary artery (MPA) diameter
2. Measure ascending aorta diameter
3. Calculate PA:Ao ratio
4. Classify finding (Normal/Elevated/Significantly elevated)

Scoring (100 points total):
- PA diameter plausible (18-45mm): 15 points
- Aorta diameter plausible (22-45mm): 15 points
- Ratio correctly calculated: 20 points
- Classification correct: 20 points
- PA markup exists: 8 points
- Aorta markup exists: 8 points
- Report complete: 9 points
- Measurements different (anti-gaming): 5 points

Pass threshold: 70 points with classification correct
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    try:
        import numpy as np
        if isinstance(val, (np.integer, np.int32, np.int64)):
            return int(val)
        elif isinstance(val, (np.floating, np.float32, np.float64)):
            return float(val)
        elif isinstance(val, np.ndarray):
            return val.tolist()
        elif isinstance(val, np.bool_):
            return bool(val)
    except ImportError:
        pass
    
    if isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def classify_pa_aorta_ratio(ratio: float) -> str:
    """Classify PA:Ao ratio according to clinical thresholds."""
    if ratio < 1.0:
        return "Normal"
    elif ratio <= 1.3:
        return "Elevated"
    else:
        return "Significantly elevated"


def verify_pa_aorta_ratio(traj, env_info, task_info):
    """
    Verify PA:Aorta ratio assessment task completion.
    
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
    ranges = metadata.get('anatomical_ranges', {})
    weights = metadata.get('scoring_weights', {})
    thresholds = metadata.get('classification_thresholds', {})
    
    # Anatomical plausibility ranges
    pa_min = ranges.get('pa_min_mm', 18)
    pa_max = ranges.get('pa_max_mm', 45)
    aorta_min = ranges.get('aorta_min_mm', 22)
    aorta_max = ranges.get('aorta_max_mm', 45)
    ratio_min = ranges.get('ratio_min', 0.6)
    ratio_max = ranges.get('ratio_max', 2.0)
    
    # Scoring weights
    w_pa_plausible = weights.get('pa_plausible', 15)
    w_aorta_plausible = weights.get('aorta_plausible', 15)
    w_ratio_calc = weights.get('ratio_calculated', 20)
    w_classification = weights.get('classification_correct', 20)
    w_pa_markup = weights.get('pa_markup_exists', 8)
    w_aorta_markup = weights.get('aorta_markup_exists', 8)
    w_report = weights.get('report_complete', 9)
    w_different = weights.get('measurements_different', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/pa_aorta_task_result.json", temp_result.name)
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
    
    # Load ground truth if available
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/pa_aorta_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # Extract agent's measurements
    # ============================================================
    pa_meas = result.get('pa_measurement', {})
    aorta_meas = result.get('aorta_measurement', {})
    report = result.get('report', {})
    
    # Get PA diameter
    agent_pa = 0.0
    pa_source = "none"
    if pa_meas.get('diameter_mm'):
        try:
            agent_pa = float(pa_meas['diameter_mm'])
            pa_source = "measurement"
        except (ValueError, TypeError):
            pass
    if agent_pa == 0 and report.get('pa_diameter_mm'):
        try:
            agent_pa = float(report['pa_diameter_mm'])
            pa_source = "report"
        except (ValueError, TypeError):
            pass
    
    # Get Aorta diameter
    agent_aorta = 0.0
    aorta_source = "none"
    if aorta_meas.get('diameter_mm'):
        try:
            agent_aorta = float(aorta_meas['diameter_mm'])
            aorta_source = "measurement"
        except (ValueError, TypeError):
            pass
    if agent_aorta == 0 and report.get('aorta_diameter_mm'):
        try:
            agent_aorta = float(report['aorta_diameter_mm'])
            aorta_source = "report"
        except (ValueError, TypeError):
            pass
    
    # Get agent's reported ratio and classification
    agent_ratio = 0.0
    if report.get('pa_aorta_ratio'):
        try:
            agent_ratio = float(report['pa_aorta_ratio'])
        except (ValueError, TypeError):
            pass
    
    agent_assessment = report.get('assessment', '').strip()
    
    details['agent_pa_mm'] = agent_pa
    details['agent_aorta_mm'] = agent_aorta
    details['agent_ratio'] = agent_ratio
    details['agent_assessment'] = agent_assessment
    details['pa_source'] = pa_source
    details['aorta_source'] = aorta_source
    
    # Ground truth values
    gt_pa = gt_data.get('pa_diameter_mm', 0)
    gt_aorta = gt_data.get('aorta_diameter_mm', 0)
    gt_ratio = gt_data.get('pa_aorta_ratio', 0)
    gt_classification = gt_data.get('classification', '')
    
    details['gt_pa_mm'] = gt_pa
    details['gt_aorta_mm'] = gt_aorta
    details['gt_ratio'] = gt_ratio
    details['gt_classification'] = gt_classification
    
    # ============================================================
    # CRITERION 1: PA diameter plausible (15 points)
    # ============================================================
    if agent_pa > 0:
        if pa_min <= agent_pa <= pa_max:
            score += w_pa_plausible
            feedback_parts.append(f"PA diameter plausible ({agent_pa:.1f}mm)")
            details['pa_plausible'] = True
        else:
            feedback_parts.append(f"PA diameter out of range ({agent_pa:.1f}mm, expected {pa_min}-{pa_max}mm)")
            details['pa_plausible'] = False
            # Partial credit if close
            if pa_min - 5 <= agent_pa <= pa_max + 5:
                score += w_pa_plausible // 2
    else:
        feedback_parts.append("PA diameter not measured")
        details['pa_plausible'] = False
    
    # ============================================================
    # CRITERION 2: Aorta diameter plausible (15 points)
    # ============================================================
    if agent_aorta > 0:
        if aorta_min <= agent_aorta <= aorta_max:
            score += w_aorta_plausible
            feedback_parts.append(f"Aorta diameter plausible ({agent_aorta:.1f}mm)")
            details['aorta_plausible'] = True
        else:
            feedback_parts.append(f"Aorta diameter out of range ({agent_aorta:.1f}mm, expected {aorta_min}-{aorta_max}mm)")
            details['aorta_plausible'] = False
            # Partial credit if close
            if aorta_min - 5 <= agent_aorta <= aorta_max + 5:
                score += w_aorta_plausible // 2
    else:
        feedback_parts.append("Aorta diameter not measured")
        details['aorta_plausible'] = False
    
    # ============================================================
    # CRITERION 3: Ratio correctly calculated (20 points)
    # ============================================================
    calculated_ratio = 0.0
    if agent_pa > 0 and agent_aorta > 0:
        calculated_ratio = agent_pa / agent_aorta
        details['calculated_ratio'] = round(calculated_ratio, 3)
        
        if agent_ratio > 0:
            # Check if agent's reported ratio matches calculated
            ratio_diff = abs(agent_ratio - calculated_ratio)
            if ratio_diff <= 0.05:
                score += w_ratio_calc
                feedback_parts.append(f"Ratio correctly calculated ({agent_ratio:.3f})")
                details['ratio_correct'] = True
            elif ratio_diff <= 0.1:
                score += w_ratio_calc // 2
                feedback_parts.append(f"Ratio approximately correct ({agent_ratio:.3f} vs calculated {calculated_ratio:.3f})")
                details['ratio_correct'] = "partial"
            else:
                feedback_parts.append(f"Ratio calculation error ({agent_ratio:.3f} vs expected {calculated_ratio:.3f})")
                details['ratio_correct'] = False
        else:
            # Agent didn't report ratio, but we can calculate it
            feedback_parts.append(f"Ratio not reported (calculated: {calculated_ratio:.3f})")
            details['ratio_correct'] = False
            # Give partial credit if measurements were made
            score += w_ratio_calc // 3
    else:
        feedback_parts.append("Cannot calculate ratio - missing measurements")
        details['ratio_correct'] = False
    
    # ============================================================
    # CRITERION 4: Classification correct (20 points)
    # ============================================================
    classification_correct = False
    
    # Determine expected classification based on agent's measurements
    if calculated_ratio > 0:
        expected_classification = classify_pa_aorta_ratio(calculated_ratio)
    elif gt_ratio > 0:
        expected_classification = gt_classification
    else:
        expected_classification = ""
    
    details['expected_classification'] = expected_classification
    
    if agent_assessment:
        # Normalize assessment strings for comparison
        agent_norm = agent_assessment.lower().strip()
        expected_norm = expected_classification.lower().strip()
        
        # Check for match (allow some flexibility in wording)
        match = False
        if expected_norm == "normal" and "normal" in agent_norm:
            match = True
        elif expected_norm == "elevated" and ("elevated" in agent_norm or "borderline" in agent_norm):
            if "significantly" not in agent_norm:
                match = True
        elif expected_norm == "significantly elevated" and "significantly" in agent_norm:
            match = True
        
        if match:
            score += w_classification
            feedback_parts.append(f"Classification correct ({agent_assessment})")
            classification_correct = True
            details['classification_correct'] = True
        else:
            feedback_parts.append(f"Classification incorrect ('{agent_assessment}' vs expected '{expected_classification}')")
            details['classification_correct'] = False
            # Partial credit for any classification attempt
            score += w_classification // 4
    else:
        feedback_parts.append("No classification provided")
        details['classification_correct'] = False
    
    # ============================================================
    # CRITERION 5: PA markup exists (8 points)
    # ============================================================
    if pa_meas.get('exists', False):
        score += w_pa_markup
        if pa_meas.get('created_during_task', False):
            feedback_parts.append("PA markup created during task")
        else:
            feedback_parts.append("PA markup exists (may be pre-existing)")
            score -= w_pa_markup // 2  # Penalty for possible pre-existing
        details['pa_markup_exists'] = True
    else:
        feedback_parts.append("PA markup not found")
        details['pa_markup_exists'] = False
    
    # ============================================================
    # CRITERION 6: Aorta markup exists (8 points)
    # ============================================================
    if aorta_meas.get('exists', False):
        score += w_aorta_markup
        if aorta_meas.get('created_during_task', False):
            feedback_parts.append("Aorta markup created during task")
        else:
            feedback_parts.append("Aorta markup exists (may be pre-existing)")
            score -= w_aorta_markup // 2
        details['aorta_markup_exists'] = True
    else:
        feedback_parts.append("Aorta markup not found")
        details['aorta_markup_exists'] = False
    
    # ============================================================
    # CRITERION 7: Report completeness (9 points)
    # ============================================================
    if report.get('exists', False):
        required_fields = ['pa_diameter_mm', 'aorta_diameter_mm', 'pa_aorta_ratio', 'assessment']
        found_fields = sum(1 for f in required_fields if report.get(f))
        
        field_score = int((found_fields / len(required_fields)) * w_report)
        score += field_score
        
        if found_fields == len(required_fields):
            feedback_parts.append("Report complete with all fields")
            details['report_complete'] = True
        else:
            missing = [f for f in required_fields if not report.get(f)]
            feedback_parts.append(f"Report missing fields: {missing}")
            details['report_complete'] = False
            details['missing_fields'] = missing
    else:
        feedback_parts.append("Report not created")
        details['report_complete'] = False
    
    # ============================================================
    # CRITERION 8: Measurements are different (anti-gaming) (5 points)
    # ============================================================
    if agent_pa > 0 and agent_aorta > 0:
        if abs(agent_pa - agent_aorta) > 1.0:  # At least 1mm different
            score += w_different
            feedback_parts.append("PA and Aorta measurements appropriately different")
            details['measurements_different'] = True
        else:
            feedback_parts.append("PA and Aorta suspiciously similar (possible copy-paste)")
            details['measurements_different'] = False
    else:
        details['measurements_different'] = "N/A"
    
    # ============================================================
    # Calculate final result
    # ============================================================
    
    # Determine pass/fail
    # Need 70 points AND classification correct
    passed = score >= 70 and classification_correct
    
    # If close to ground truth, give bonus feedback
    if gt_pa > 0 and agent_pa > 0:
        pa_error = abs(agent_pa - gt_pa)
        details['pa_error_mm'] = round(pa_error, 1)
        if pa_error <= 3:
            feedback_parts.append(f"PA measurement very accurate (within {pa_error:.1f}mm of ground truth)")
        elif pa_error <= 5:
            feedback_parts.append(f"PA measurement accurate (within {pa_error:.1f}mm)")
    
    if gt_aorta > 0 and agent_aorta > 0:
        aorta_error = abs(agent_aorta - gt_aorta)
        details['aorta_error_mm'] = round(aorta_error, 1)
        if aorta_error <= 3:
            feedback_parts.append(f"Aorta measurement very accurate (within {aorta_error:.1f}mm of ground truth)")
        elif aorta_error <= 5:
            feedback_parts.append(f"Aorta measurement accurate (within {aorta_error:.1f}mm)")
    
    # Ensure score is in valid range
    score = max(0, min(100, score))
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }