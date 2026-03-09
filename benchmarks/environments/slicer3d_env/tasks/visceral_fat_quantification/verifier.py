#!/usr/bin/env python3
"""
Verifier for visceral fat quantification task.

VERIFICATION METRICS:
1. Correct slice level - L4-L5 identification (within tolerance)
2. SAT area accuracy - comparison with ground truth
3. VAT area accuracy - comparison with ground truth
4. VAT/SAT ratio accuracy
5. Classification correctness (Gynoid/Intermediate/Android)
6. Report completeness

Ground Truth: Computed from AMOS 2022 abdominal CT data
"""

import json
import os
import sys
import tempfile
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


def parse_numeric(value):
    """Safely parse a numeric value from string or number."""
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def classify_fat_distribution(vat_sat_ratio):
    """Classify fat distribution based on VAT/SAT ratio."""
    if vat_sat_ratio is None:
        return None
    if vat_sat_ratio < 0.4:
        return "Gynoid"
    elif vat_sat_ratio <= 1.0:
        return "Intermediate"
    else:
        return "Android"


def verify_visceral_fat_quantification(traj, env_info, task_info):
    """
    Verify visceral fat quantification task completion.

    Scoring (100 points total):
    - Correct slice level: 15 points (within tolerance of L4-L5)
    - SAT area accuracy: 25 points (within 20% of ground truth)
    - VAT area accuracy: 25 points (within 20% of ground truth)
    - VAT/SAT ratio: 15 points (within 0.15 of ground truth)
    - Classification correct: 10 points
    - Report completeness: 10 points
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

    sat_error_max = thresholds.get('sat_area_error_percent', 20) / 100.0
    vat_error_max = thresholds.get('vat_area_error_percent', 20) / 100.0
    ratio_error_max = thresholds.get('ratio_error', 0.15)
    slice_tolerance = thresholds.get('slice_tolerance', 3)

    w_slice = weights.get('correct_slice_level', 15)
    w_sat = weights.get('sat_area_accuracy', 25)
    w_vat = weights.get('vat_area_accuracy', 25)
    w_ratio = weights.get('vat_sat_ratio', 15)
    w_class = weights.get('classification_correct', 10)
    w_report = weights.get('report_completeness', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fat_task_result.json", temp_result.name)
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
        feedback_parts.append("Slicer was not running")
        # Don't immediately fail - agent might have closed it

    # ============================================================
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/fat_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load ground truth: {e}"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_slice = gt_data.get('ground_truth_slice_index', 0)
    gt_sat = gt_data.get('sat_area_cm2', 0)
    gt_vat = gt_data.get('vat_area_cm2', 0)
    gt_ratio = gt_data.get('vat_sat_ratio', 0)
    gt_classification = gt_data.get('fat_distribution', '')

    details['gt_slice_index'] = gt_slice
    details['gt_sat_area_cm2'] = gt_sat
    details['gt_vat_area_cm2'] = gt_vat
    details['gt_vat_sat_ratio'] = gt_ratio
    details['gt_classification'] = gt_classification

    # ============================================================
    # ANTI-GAMING: Check timestamps
    # ============================================================
    seg_created = result.get('segmentation_created_during_task', False)
    report_created = result.get('report_created_during_task', False)
    
    if not seg_created and not report_created:
        feedback_parts.append("WARNING: No files created during task")
        details['anti_gaming_flag'] = "no_files_created"

    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    agent_sat = parse_numeric(result.get('reported_sat_area_cm2', ''))
    agent_vat = parse_numeric(result.get('reported_vat_area_cm2', ''))
    agent_ratio = parse_numeric(result.get('reported_vat_sat_ratio', ''))
    agent_classification = result.get('reported_classification', '')
    agent_slice_str = result.get('reported_slice_index', '')
    
    # Try to parse slice index
    agent_slice = None
    if agent_slice_str:
        try:
            agent_slice = int(agent_slice_str)
        except (ValueError, TypeError):
            # Might be vertebral level string like "L4-L5"
            if 'l4' in str(agent_slice_str).lower() or 'l5' in str(agent_slice_str).lower():
                agent_slice = gt_slice  # Accept if they identified correct level

    details['agent_sat_area_cm2'] = agent_sat
    details['agent_vat_area_cm2'] = agent_vat
    details['agent_vat_sat_ratio'] = agent_ratio
    details['agent_classification'] = agent_classification
    details['agent_slice_index'] = agent_slice

    # ============================================================
    # CRITERION 1: Correct Slice Level (15 points)
    # ============================================================
    slice_correct = False
    if agent_slice is not None:
        slice_diff = abs(agent_slice - gt_slice)
        if slice_diff <= slice_tolerance:
            score += w_slice
            slice_correct = True
            feedback_parts.append(f"✓ Slice level correct (within {slice_diff} slices)")
        else:
            partial = max(0, w_slice * (1 - slice_diff / 10))
            score += partial
            feedback_parts.append(f"✗ Slice off by {slice_diff} (expected ~{gt_slice})")
        details['slice_difference'] = slice_diff
    else:
        feedback_parts.append("✗ Slice level not reported")

    # ============================================================
    # CRITERION 2: SAT Area Accuracy (25 points)
    # ============================================================
    sat_correct = False
    if agent_sat is not None and gt_sat > 0:
        sat_error = abs(agent_sat - gt_sat) / gt_sat
        details['sat_error_percent'] = sat_error * 100
        
        if sat_error <= sat_error_max:
            score += w_sat
            sat_correct = True
            feedback_parts.append(f"✓ SAT area accurate ({agent_sat:.1f} vs {gt_sat:.1f} cm², error {sat_error*100:.1f}%)")
        elif sat_error <= sat_error_max * 1.5:
            partial = w_sat * 0.5
            score += partial
            feedback_parts.append(f"~ SAT area partially accurate ({agent_sat:.1f} vs {gt_sat:.1f} cm², error {sat_error*100:.1f}%)")
        else:
            feedback_parts.append(f"✗ SAT area inaccurate ({agent_sat:.1f} vs {gt_sat:.1f} cm², error {sat_error*100:.1f}%)")
    elif agent_sat is not None:
        # Check if physiologically plausible even without exact match
        if 50 <= agent_sat <= 600:
            score += w_sat * 0.25
            feedback_parts.append(f"~ SAT area plausible ({agent_sat:.1f} cm²) but no GT comparison")
        else:
            feedback_parts.append(f"✗ SAT area implausible ({agent_sat:.1f} cm²)")
    else:
        feedback_parts.append("✗ SAT area not reported")

    # ============================================================
    # CRITERION 3: VAT Area Accuracy (25 points)
    # ============================================================
    vat_correct = False
    if agent_vat is not None and gt_vat > 0:
        vat_error = abs(agent_vat - gt_vat) / gt_vat
        details['vat_error_percent'] = vat_error * 100
        
        if vat_error <= vat_error_max:
            score += w_vat
            vat_correct = True
            feedback_parts.append(f"✓ VAT area accurate ({agent_vat:.1f} vs {gt_vat:.1f} cm², error {vat_error*100:.1f}%)")
        elif vat_error <= vat_error_max * 1.5:
            partial = w_vat * 0.5
            score += partial
            feedback_parts.append(f"~ VAT area partially accurate ({agent_vat:.1f} vs {gt_vat:.1f} cm², error {vat_error*100:.1f}%)")
        else:
            feedback_parts.append(f"✗ VAT area inaccurate ({agent_vat:.1f} vs {gt_vat:.1f} cm², error {vat_error*100:.1f}%)")
    elif agent_vat is not None:
        # Check if physiologically plausible
        if 30 <= agent_vat <= 400:
            score += w_vat * 0.25
            feedback_parts.append(f"~ VAT area plausible ({agent_vat:.1f} cm²) but no GT comparison")
        else:
            feedback_parts.append(f"✗ VAT area implausible ({agent_vat:.1f} cm²)")
    else:
        feedback_parts.append("✗ VAT area not reported")

    # ============================================================
    # CRITERION 4: VAT/SAT Ratio (15 points)
    # ============================================================
    ratio_correct = False
    if agent_ratio is not None:
        ratio_diff = abs(agent_ratio - gt_ratio)
        details['ratio_difference'] = ratio_diff
        
        if ratio_diff <= ratio_error_max:
            score += w_ratio
            ratio_correct = True
            feedback_parts.append(f"✓ VAT/SAT ratio accurate ({agent_ratio:.3f} vs {gt_ratio:.3f})")
        elif ratio_diff <= ratio_error_max * 2:
            partial = w_ratio * 0.5
            score += partial
            feedback_parts.append(f"~ VAT/SAT ratio partially accurate ({agent_ratio:.3f} vs {gt_ratio:.3f})")
        else:
            feedback_parts.append(f"✗ VAT/SAT ratio inaccurate ({agent_ratio:.3f} vs {gt_ratio:.3f})")
    elif agent_sat is not None and agent_vat is not None and agent_sat > 0:
        # Calculate ratio from reported values
        computed_ratio = agent_vat / agent_sat
        ratio_diff = abs(computed_ratio - gt_ratio)
        if ratio_diff <= ratio_error_max:
            score += w_ratio * 0.75
            feedback_parts.append(f"~ VAT/SAT ratio computed correctly ({computed_ratio:.3f})")
        else:
            feedback_parts.append(f"✗ Computed VAT/SAT ratio inaccurate ({computed_ratio:.3f})")
    else:
        feedback_parts.append("✗ VAT/SAT ratio not determinable")

    # ============================================================
    # CRITERION 5: Classification Correct (10 points)
    # ============================================================
    if agent_classification:
        agent_class_normalized = agent_classification.lower().strip()
        gt_class_normalized = gt_classification.lower().strip()
        
        if agent_class_normalized == gt_class_normalized:
            score += w_class
            feedback_parts.append(f"✓ Classification correct ({agent_classification})")
        elif agent_ratio is not None:
            # Check if classification matches their ratio (consistent reasoning)
            expected_from_ratio = classify_fat_distribution(agent_ratio)
            if expected_from_ratio and agent_class_normalized == expected_from_ratio.lower():
                score += w_class * 0.5
                feedback_parts.append(f"~ Classification consistent with reported ratio but not GT")
            else:
                feedback_parts.append(f"✗ Classification incorrect (got {agent_classification}, expected {gt_classification})")
        else:
            feedback_parts.append(f"✗ Classification incorrect (got {agent_classification}, expected {gt_classification})")
    else:
        feedback_parts.append("✗ Classification not reported")

    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    seg_exists = result.get('segmentation_exists', False)
    
    report_score = 0
    if report_exists:
        report_score += 5
        # Check for required fields
        required_fields = ['sat_area_cm2', 'vat_area_cm2', 'vat_sat_ratio', 'fat_distribution']
        reported_fields = sum([
            agent_sat is not None,
            agent_vat is not None,
            agent_ratio is not None,
            bool(agent_classification)
        ])
        report_score += (reported_fields / len(required_fields)) * 5
        
    if seg_exists:
        seg_size = result.get('segmentation_size_bytes', 0)
        if seg_size > 1000:  # Non-trivial segmentation
            report_score += 2
            
    score += min(report_score, w_report)
    
    if report_exists and seg_exists:
        feedback_parts.append(f"✓ Report and segmentation saved")
    elif report_exists:
        feedback_parts.append("~ Report saved, segmentation missing")
    elif seg_exists:
        feedback_parts.append("~ Segmentation saved, report missing")
    else:
        feedback_parts.append("✗ Neither report nor segmentation saved")

    # ============================================================
    # FINAL SCORING
    # ============================================================
    score = int(min(100, max(0, score)))
    
    # Key criteria: at least one area must be somewhat accurate
    key_criteria_met = (sat_correct or vat_correct) or (
        agent_sat is not None and agent_vat is not None and 
        50 <= agent_sat <= 600 and 30 <= agent_vat <= 400
    )
    
    # Pass threshold: 60 points AND key criteria
    passed = score >= 60 and key_criteria_met
    
    # Construct feedback
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details,
        "subscores": {
            "slice_level": w_slice if slice_correct else 0,
            "sat_accuracy": w_sat if sat_correct else 0,
            "vat_accuracy": w_vat if vat_correct else 0,
            "ratio_accuracy": w_ratio if ratio_correct else 0,
            "classification": w_class if agent_classification and agent_classification.lower() == gt_classification.lower() else 0,
            "report_completeness": min(report_score, w_report)
        }
    })