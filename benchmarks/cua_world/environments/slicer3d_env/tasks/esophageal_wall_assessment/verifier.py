#!/usr/bin/env python3
"""
Verifier for esophageal wall thickness assessment task.

VERIFICATION METRICS:
1. Esophagus located - measurement placed in posterior mediastinum (15 pts)
2. Measurement accuracy - close to ground truth thickness (25 pts)
3. Measurement level documented - vertebral level specified (10 pts)
4. Classification correct - Normal/Mildly/Significantly thickened (20 pts)
5. Classification-measurement consistency - classification matches value (10 pts)
6. Recommendation appropriate - follows clinical guidelines (10 pts)
7. Report completeness - all required fields present (10 pts)

Pass threshold: 60 points with "Esophagus Located" achieved
"""

import json
import os
import sys
import tempfile
import logging
import re

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


def classify_by_thickness(thickness_mm):
    """
    Classify esophageal wall based on thickness.
    
    Returns standardized classification string.
    """
    if thickness_mm is None:
        return None
    
    try:
        t = float(thickness_mm)
    except (ValueError, TypeError):
        return None
    
    if t <= 5.0:
        return "Normal"
    elif t <= 10.0:
        return "Mildly thickened"
    else:
        return "Significantly thickened"


def normalize_classification(cls_str):
    """
    Normalize classification string for comparison.
    """
    if not cls_str:
        return None
    
    cls_lower = cls_str.lower().strip()
    
    if "significant" in cls_lower or "markedly" in cls_lower:
        return "Significantly thickened"
    elif "mild" in cls_lower or "slight" in cls_lower:
        return "Mildly thickened"
    elif "normal" in cls_lower or "unremarkable" in cls_lower or "within normal" in cls_lower:
        return "Normal"
    elif "thicken" in cls_lower:
        # Generic thickened - treat as mild
        return "Mildly thickened"
    
    return cls_str


def parse_vertebral_level(level_str):
    """
    Parse vertebral level from string.
    Returns tuple (region, number) or None.
    """
    if not level_str:
        return None
    
    level_str = level_str.upper().strip()
    
    # Match patterns like T7, T8, T 7, etc.
    match = re.search(r'([TCL])\s*(\d+)', level_str)
    if match:
        return (match.group(1), int(match.group(2)))
    
    # Match descriptive terms
    if "mid" in level_str.lower() and "thorac" in level_str.lower():
        return ("T", 7)  # Mid-thoracic approximation
    if "lower" in level_str.lower() and "thorac" in level_str.lower():
        return ("T", 9)
    if "upper" in level_str.lower() and "thorac" in level_str.lower():
        return ("T", 5)
    
    return None


def verify_esophageal_wall_assessment(traj, env_info, task_info):
    """
    Verify esophageal wall assessment task completion.
    
    Scoring (100 points total):
    - Esophagus located: 15 points
    - Measurement accuracy: 25 points
    - Measurement level documented: 10 points
    - Classification correct: 20 points
    - Classification-measurement consistency: 10 points
    - Recommendation appropriate: 10 points
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
    
    measurement_error_max = thresholds.get('measurement_error_max_mm', 3.0)
    plausible_range = metadata.get('plausible_range_mm', [2.0, 15.0])
    
    w_located = weights.get('esophagus_located', 15)
    w_accuracy = weights.get('measurement_accuracy', 25)
    w_level = weights.get('measurement_level_documented', 10)
    w_classification = weights.get('classification_correct', 20)
    w_consistency = weights.get('classification_consistency', 10)
    w_recommendation = weights.get('recommendation_appropriate', 10)
    w_report = weights.get('report_complete', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/esophageal_task_result.json", temp_result.name)
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
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/esophageal_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_thickness = gt_data.get('wall_thickness_mm', 4.0)
    gt_classification = gt_data.get('classification', 'Normal')
    gt_level = gt_data.get('measurement_level', 'T7')
    gt_acceptable_levels = gt_data.get('acceptable_levels', ['T6', 'T7', 'T8', 'T9'])
    gt_tolerance = gt_data.get('measurement_tolerance_mm', 2.0)
    
    details['gt_thickness_mm'] = gt_thickness
    details['gt_classification'] = gt_classification
    details['gt_level'] = gt_level
    
    # ============================================================
    # CRITERION 1: ESOPHAGUS LOCATED (15 points)
    # Check if measurement was placed (anywhere reasonable)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    measurement_created_during_task = result.get('measurement_created_during_task', False)
    measured_thickness_str = result.get('measured_thickness_mm', '')
    
    esophagus_located = False
    agent_thickness = None
    
    if measurement_exists:
        # Try to parse measured thickness
        try:
            if measured_thickness_str:
                agent_thickness = float(measured_thickness_str)
        except (ValueError, TypeError):
            pass
        
        # Also check reported thickness if measurement extraction failed
        if agent_thickness is None:
            reported_thickness_str = result.get('reported_thickness_mm', '')
            try:
                if reported_thickness_str:
                    agent_thickness = float(reported_thickness_str)
            except (ValueError, TypeError):
                pass
        
        # Check if measurement is plausible (within anatomical range)
        if agent_thickness is not None:
            if plausible_range[0] <= agent_thickness <= plausible_range[1]:
                esophagus_located = True
                if measurement_created_during_task:
                    score += w_located
                    feedback_parts.append(f"✅ Esophagus located (measurement: {agent_thickness:.1f}mm)")
                else:
                    score += w_located * 0.7  # Partial credit if file existed before
                    feedback_parts.append(f"⚠️ Measurement found but may predate task ({agent_thickness:.1f}mm)")
            else:
                feedback_parts.append(f"⚠️ Measurement ({agent_thickness:.1f}mm) outside plausible range ({plausible_range[0]}-{plausible_range[1]}mm)")
                esophagus_located = False
        else:
            feedback_parts.append("⚠️ Measurement file exists but could not extract thickness value")
    else:
        feedback_parts.append("❌ No measurement markup found")
    
    details['esophagus_located'] = esophagus_located
    details['agent_thickness_mm'] = agent_thickness
    
    # If esophagus not located, can still get partial credit for report
    
    # ============================================================
    # CRITERION 2: MEASUREMENT ACCURACY (25 points)
    # Compare to ground truth
    # ============================================================
    if agent_thickness is not None:
        error_mm = abs(agent_thickness - gt_thickness)
        details['measurement_error_mm'] = error_mm
        
        if error_mm <= gt_tolerance:
            score += w_accuracy
            feedback_parts.append(f"✅ Measurement accurate (error: {error_mm:.1f}mm ≤ {gt_tolerance}mm)")
        elif error_mm <= measurement_error_max:
            # Partial credit for close measurements
            partial = w_accuracy * (1 - (error_mm - gt_tolerance) / (measurement_error_max - gt_tolerance))
            score += max(0, partial)
            feedback_parts.append(f"⚠️ Measurement close (error: {error_mm:.1f}mm)")
        else:
            feedback_parts.append(f"❌ Measurement inaccurate (error: {error_mm:.1f}mm > {measurement_error_max}mm)")
    else:
        feedback_parts.append("❌ No thickness measurement to evaluate")
    
    # ============================================================
    # CRITERION 3: MEASUREMENT LEVEL DOCUMENTED (10 points)
    # ============================================================
    reported_level = result.get('reported_level', '')
    level_documented = False
    level_accurate = False
    
    if reported_level:
        level_documented = True
        parsed_level = parse_vertebral_level(reported_level)
        gt_parsed = parse_vertebral_level(gt_level)
        
        if parsed_level and gt_parsed:
            # Check if within 1 vertebral level
            if parsed_level[0] == gt_parsed[0]:  # Same region (T, C, L)
                level_diff = abs(parsed_level[1] - gt_parsed[1])
                if level_diff <= 1:
                    level_accurate = True
                    score += w_level
                    feedback_parts.append(f"✅ Level documented and accurate ({reported_level})")
                else:
                    score += w_level * 0.5
                    feedback_parts.append(f"⚠️ Level documented but differs from expected ({reported_level} vs {gt_level})")
            else:
                score += w_level * 0.3
                feedback_parts.append(f"⚠️ Level documented but wrong region ({reported_level})")
        else:
            score += w_level * 0.5
            feedback_parts.append(f"⚠️ Level documented ({reported_level})")
    else:
        feedback_parts.append("❌ Measurement level not documented")
    
    details['level_documented'] = level_documented
    details['reported_level'] = reported_level
    
    # ============================================================
    # CRITERION 4: CLASSIFICATION CORRECT (20 points)
    # ============================================================
    reported_classification = result.get('reported_classification', '')
    agent_classification = normalize_classification(reported_classification)
    
    if agent_classification:
        if agent_classification == gt_classification:
            score += w_classification
            feedback_parts.append(f"✅ Classification correct ({agent_classification})")
        else:
            # Check if one step off
            classifications = ["Normal", "Mildly thickened", "Significantly thickened"]
            try:
                agent_idx = classifications.index(agent_classification)
                gt_idx = classifications.index(gt_classification)
                if abs(agent_idx - gt_idx) == 1:
                    score += w_classification * 0.5
                    feedback_parts.append(f"⚠️ Classification close ({agent_classification} vs {gt_classification})")
                else:
                    feedback_parts.append(f"❌ Classification incorrect ({agent_classification} vs {gt_classification})")
            except ValueError:
                feedback_parts.append(f"⚠️ Classification not recognized ({reported_classification})")
    else:
        feedback_parts.append("❌ No classification provided")
    
    details['agent_classification'] = agent_classification
    
    # ============================================================
    # CRITERION 5: CLASSIFICATION-MEASUREMENT CONSISTENCY (10 points)
    # Check if classification matches the measured value
    # ============================================================
    if agent_thickness is not None and agent_classification:
        expected_classification = classify_by_thickness(agent_thickness)
        if agent_classification == expected_classification:
            score += w_consistency
            feedback_parts.append("✅ Classification consistent with measurement")
        else:
            feedback_parts.append(f"⚠️ Classification inconsistent ({agent_classification} for {agent_thickness:.1f}mm)")
    elif agent_thickness is not None or agent_classification:
        feedback_parts.append("⚠️ Cannot verify consistency (missing data)")
    
    # ============================================================
    # CRITERION 6: RECOMMENDATION APPROPRIATE (10 points)
    # ============================================================
    reported_recommendation = result.get('reported_recommendation', '')
    
    if reported_recommendation:
        rec_lower = reported_recommendation.lower()
        
        # Check if recommendation aligns with classification
        recommendation_appropriate = False
        
        if agent_classification == "Normal":
            if any(word in rec_lower for word in ["no further", "routine", "unremarkable", "no evaluation", "normal"]):
                recommendation_appropriate = True
        elif agent_classification == "Mildly thickened":
            if any(word in rec_lower for word in ["correlation", "follow", "consider", "clinical", "if symptomatic"]):
                recommendation_appropriate = True
        elif agent_classification == "Significantly thickened":
            if any(word in rec_lower for word in ["endoscopy", "egd", "evaluate", "urgent", "further evaluation"]):
                recommendation_appropriate = True
        
        if recommendation_appropriate:
            score += w_recommendation
            feedback_parts.append("✅ Recommendation appropriate")
        else:
            score += w_recommendation * 0.5
            feedback_parts.append(f"⚠️ Recommendation provided but may not match classification")
    else:
        feedback_parts.append("❌ No recommendation provided")
    
    details['reported_recommendation'] = reported_recommendation
    
    # ============================================================
    # CRITERION 7: REPORT COMPLETENESS (10 points)
    # Check for all required fields
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created_during_task = result.get('report_created_during_task', False)
    
    required_fields = {
        'thickness': agent_thickness is not None,
        'level': bool(reported_level),
        'classification': bool(agent_classification),
        'appearance': bool(result.get('reported_appearance', '')),
        'recommendation': bool(reported_recommendation),
    }
    
    fields_present = sum(required_fields.values())
    total_fields = len(required_fields)
    
    if report_exists and report_created_during_task:
        completeness_ratio = fields_present / total_fields
        score += w_report * completeness_ratio
        
        if fields_present == total_fields:
            feedback_parts.append("✅ Report complete with all fields")
        else:
            missing = [k for k, v in required_fields.items() if not v]
            feedback_parts.append(f"⚠️ Report incomplete (missing: {', '.join(missing)})")
    elif report_exists:
        score += w_report * 0.5 * (fields_present / total_fields)
        feedback_parts.append("⚠️ Report found but may predate task")
    else:
        feedback_parts.append("❌ No report file found")
    
    details['report_fields'] = required_fields
    
    # ============================================================
    # FINAL SCORING AND RESULT
    # ============================================================
    score = min(100, max(0, int(round(score))))
    
    # Key criteria: esophagus must be located
    key_criteria_met = esophagus_located
    passed = score >= 60 and key_criteria_met
    
    if not key_criteria_met:
        feedback_parts.append("🚫 Key criterion not met: esophagus not located")
    
    # Convert all details to Python types
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "esophagus_located": esophagus_located,
            "measurement_accuracy": agent_thickness is not None and abs(agent_thickness - gt_thickness) <= measurement_error_max,
            "level_documented": level_documented,
            "classification_correct": agent_classification == gt_classification if agent_classification else False,
            "report_complete": fields_present == total_fields,
        }
    }