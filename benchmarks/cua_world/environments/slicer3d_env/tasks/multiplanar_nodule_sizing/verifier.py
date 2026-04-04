#!/usr/bin/env python3
"""
Verifier for multi-planar nodule sizing task.

VERIFICATION METRICS:
1. Max diameter accuracy - agent's max diameter within 2mm of ground truth
2. Per-plane measurements - each plane within 3mm
3. Asphericity calculation - within 5%
4. Discrepancy flag - correctly identifies if initial was discrepant
5. Shape classification - correct SPHERICAL/ELONGATED

SCORING:
- Max diameter accuracy: 25 points
- Axial measurement: 10 points
- Coronal measurement: 10 points
- Sagittal measurement: 10 points
- Asphericity calculation: 15 points
- Discrepancy flag correct: 10 points
- Shape classification: 10 points
- Report completeness: 10 points
Total: 100 points

Pass threshold: 60 points with max diameter accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_multiplanar_nodule_sizing(traj, env_info, task_info):
    """
    Verify multi-planar nodule sizing task completion.
    
    Uses copy_from_env to read result files from container.
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
    
    max_diam_error = thresholds.get('max_diameter_error_mm', 2.0)
    per_plane_error = thresholds.get('per_plane_error_mm', 3.0)
    asphericity_error = thresholds.get('asphericity_error_percent', 5.0)
    
    w_max_diam = weights.get('max_diameter_accuracy', 25)
    w_axial = weights.get('axial_measurement', 10)
    w_coronal = weights.get('coronal_measurement', 10)
    w_sagittal = weights.get('sagittal_measurement', 10)
    w_asphericity = weights.get('asphericity_calculation', 15)
    w_discrepancy = weights.get('discrepancy_flag', 10)
    w_shape = weights.get('shape_classification', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/multiplanar_task_result.json", temp_result.name)
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
        "max_diameter_correct": False,
        "axial_correct": False,
        "coronal_correct": False,
        "sagittal_correct": False,
        "asphericity_correct": False,
        "discrepancy_correct": False,
        "shape_correct": False,
        "report_complete": False,
        "multi_plane_performed": False
    }
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task"
        }
    
    if not result.get('report_file_exists', False):
        feedback_parts.append("Report file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file not created. " + "; ".join(feedback_parts),
            "details": details
        }
    
    # Anti-gaming: check if files were created during task
    if not result.get('report_created_during_task', False):
        feedback_parts.append("WARNING: Report file may have existed before task")
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/multiplanar_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use fallback values
        gt_data = {
            "axial_diameter_mm": 9.5,
            "coronal_diameter_mm": 12.8,
            "sagittal_diameter_mm": 11.2,
            "max_diameter_mm": 12.8,
            "min_diameter_mm": 9.5,
            "asphericity_percent": 25.8,
            "shape_classification": "ELONGATED",
            "discrepancy_flag": True
        }
        feedback_parts.append("Using fallback ground truth")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Extract ground truth values
    gt_axial = gt_data.get('axial_diameter_mm', 9.5)
    gt_coronal = gt_data.get('coronal_diameter_mm', 12.8)
    gt_sagittal = gt_data.get('sagittal_diameter_mm', 11.2)
    gt_max = gt_data.get('max_diameter_mm', 12.8)
    gt_min = gt_data.get('min_diameter_mm', 9.5)
    gt_asphericity = gt_data.get('asphericity_percent', 25.8)
    gt_shape = gt_data.get('shape_classification', 'ELONGATED')
    gt_discrepant = gt_data.get('discrepancy_flag', True)
    
    details['ground_truth'] = {
        'axial_mm': gt_axial,
        'coronal_mm': gt_coronal,
        'sagittal_mm': gt_sagittal,
        'max_mm': gt_max,
        'asphericity': gt_asphericity,
        'shape': gt_shape,
        'discrepant': gt_discrepant
    }
    
    # Extract agent measurements
    agent = result.get('agent_measurements', {})
    
    agent_axial = agent.get('axial_mm')
    agent_coronal = agent.get('coronal_mm')
    agent_sagittal = agent.get('sagittal_mm')
    agent_max = agent.get('max_diameter_mm')
    agent_min = agent.get('min_diameter_mm')
    agent_asphericity = agent.get('asphericity_percent')
    agent_discrepant = agent.get('discrepancy_flag')
    agent_shape = str(agent.get('shape_classification', '')).upper() if agent.get('shape_classification') else None
    
    details['agent_values'] = {
        'axial_mm': agent_axial,
        'coronal_mm': agent_coronal,
        'sagittal_mm': agent_sagittal,
        'max_mm': agent_max,
        'asphericity': agent_asphericity,
        'shape': agent_shape,
        'discrepant': agent_discrepant
    }
    
    # Helper function to safely compare measurements
    def safe_compare(agent_val, gt_val, tolerance):
        try:
            if agent_val is None or agent_val == 'null':
                return False
            return abs(float(agent_val) - float(gt_val)) <= tolerance
        except (ValueError, TypeError):
            return False
    
    def is_valid_number(val):
        try:
            if val is None or val == 'null':
                return False
            float(val)
            return True
        except (ValueError, TypeError):
            return False
    
    # Check multi-plane assessment was performed
    planes_measured = sum([
        1 for v in [agent_axial, agent_coronal, agent_sagittal]
        if is_valid_number(v)
    ])
    
    if planes_measured >= 3:
        details["multi_plane_performed"] = True
        feedback_parts.append(f"Multi-planar assessment performed ({planes_measured} planes)")
    else:
        feedback_parts.append(f"Incomplete multi-planar assessment ({planes_measured}/3 planes)")
    
    # ================================================================
    # SCORING
    # ================================================================
    
    # 1. Max diameter accuracy (25 pts)
    if safe_compare(agent_max, gt_max, max_diam_error):
        score += w_max_diam
        details["max_diameter_correct"] = True
        feedback_parts.append(f"Max diameter correct: {agent_max}mm (GT: {gt_max}mm)")
    else:
        if is_valid_number(agent_max):
            feedback_parts.append(f"Max diameter incorrect: {agent_max}mm vs GT: {gt_max}mm")
        else:
            feedback_parts.append("Max diameter not reported")
    
    # 2. Axial measurement (10 pts)
    if safe_compare(agent_axial, gt_axial, per_plane_error):
        score += w_axial
        details["axial_correct"] = True
        feedback_parts.append(f"Axial correct: {agent_axial}mm")
    else:
        if is_valid_number(agent_axial):
            feedback_parts.append(f"Axial: {agent_axial}mm (expected ~{gt_axial}mm)")
        else:
            feedback_parts.append("Axial measurement missing")
    
    # 3. Coronal measurement (10 pts)
    if safe_compare(agent_coronal, gt_coronal, per_plane_error):
        score += w_coronal
        details["coronal_correct"] = True
        feedback_parts.append(f"Coronal correct: {agent_coronal}mm")
    else:
        if is_valid_number(agent_coronal):
            feedback_parts.append(f"Coronal: {agent_coronal}mm (expected ~{gt_coronal}mm)")
        else:
            feedback_parts.append("Coronal measurement missing")
    
    # 4. Sagittal measurement (10 pts)
    if safe_compare(agent_sagittal, gt_sagittal, per_plane_error):
        score += w_sagittal
        details["sagittal_correct"] = True
        feedback_parts.append(f"Sagittal correct: {agent_sagittal}mm")
    else:
        if is_valid_number(agent_sagittal):
            feedback_parts.append(f"Sagittal: {agent_sagittal}mm (expected ~{gt_sagittal}mm)")
        else:
            feedback_parts.append("Sagittal measurement missing")
    
    # 5. Asphericity calculation (15 pts)
    if safe_compare(agent_asphericity, gt_asphericity, asphericity_error):
        score += w_asphericity
        details["asphericity_correct"] = True
        feedback_parts.append(f"Asphericity correct: {agent_asphericity}%")
    else:
        # Check for internal consistency (partial credit)
        if is_valid_number(agent_max) and is_valid_number(agent_min) and is_valid_number(agent_asphericity):
            try:
                expected_asph = (float(agent_max) - float(agent_min)) / float(agent_max) * 100
                if abs(float(agent_asphericity) - expected_asph) < 2.0:
                    # Formula is correct, just different input values
                    score += int(w_asphericity * 0.5)
                    feedback_parts.append(f"Asphericity formula correct, value differs: {agent_asphericity}%")
                else:
                    feedback_parts.append(f"Asphericity: {agent_asphericity}% (expected ~{gt_asphericity}%)")
            except:
                feedback_parts.append(f"Asphericity: {agent_asphericity}% (expected ~{gt_asphericity}%)")
        else:
            feedback_parts.append("Asphericity not properly calculated")
    
    # 6. Discrepancy flag (10 pts)
    if agent_discrepant is not None and agent_discrepant != 'null':
        agent_disc_bool = str(agent_discrepant).lower() == 'true'
        if agent_disc_bool == gt_discrepant:
            score += w_discrepancy
            details["discrepancy_correct"] = True
            feedback_parts.append(f"Discrepancy flag correct: {agent_discrepant}")
        else:
            feedback_parts.append(f"Discrepancy flag wrong: {agent_discrepant} (expected {gt_discrepant})")
    else:
        feedback_parts.append("Discrepancy flag not reported")
    
    # 7. Shape classification (10 pts)
    if agent_shape and agent_shape in ['SPHERICAL', 'ELONGATED']:
        if agent_shape == gt_shape:
            score += w_shape
            details["shape_correct"] = True
            feedback_parts.append(f"Shape classification correct: {agent_shape}")
        else:
            feedback_parts.append(f"Shape classification wrong: {agent_shape} (expected {gt_shape})")
    else:
        feedback_parts.append(f"Shape classification invalid or missing: {agent_shape}")
    
    # 8. Report completeness (10 pts)
    required_fields = ['axial_mm', 'coronal_mm', 'sagittal_mm', 'max_diameter_mm', 'asphericity_percent']
    present_fields = sum(1 for f in required_fields if is_valid_number(agent.get(f)))
    
    if present_fields >= 5:
        score += w_report
        details["report_complete"] = True
        feedback_parts.append("Report complete with all required fields")
    elif present_fields >= 3:
        score += int(w_report * 0.5)
        feedback_parts.append(f"Report partially complete ({present_fields}/5 fields)")
    else:
        feedback_parts.append(f"Report incomplete ({present_fields}/5 fields)")
    
    # Anti-gaming: Check for do-nothing
    measurement_count = result.get('measurement_count', 0)
    if not details["multi_plane_performed"] and measurement_count < 2:
        score = 0
        feedback_parts.append("ANTI-GAMING: No evidence of multi-planar measurement performed")
    
    # Determine pass/fail
    key_criteria_met = details["max_diameter_correct"]
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    if passed:
        feedback = f"PASSED ({score}/100): " + "; ".join(feedback_parts)
    else:
        feedback = f"FAILED ({score}/100): " + "; ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }