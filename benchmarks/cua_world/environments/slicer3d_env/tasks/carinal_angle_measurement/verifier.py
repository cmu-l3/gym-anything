#!/usr/bin/env python3
"""
Verifier for carinal angle measurement task.

VERIFICATION METRICS:
1. Angle accuracy - how close is agent's measurement to ground truth (35 pts)
2. Correct anatomical level - is measurement at the carina location (20 pts)
3. Markup quality - proper angle markup placed (15 pts)
4. Classification correct - Normal/Widened/Narrowed (15 pts)
5. Report completeness - all required fields present (10 pts)
6. Vertebral level correct - approximate location (5 pts)

Ground Truth: Calculated from airway geometry or literature reference values
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


def classify_angle(angle_degrees):
    """Classify carinal angle based on clinical thresholds."""
    if angle_degrees < 50:
        return "Narrowed"
    elif angle_degrees > 100:
        return "Widened"
    else:
        return "Normal"


def verify_carinal_angle(traj, env_info, task_info):
    """
    Verify carinal angle measurement task completion.
    
    Scoring (100 points total):
    - Angle accuracy: 35 points (within 10 degrees)
    - Correct anatomical level: 20 points (z-position near carina)
    - Markup quality: 15 points (angle markup exists)
    - Classification correct: 15 points
    - Report completeness: 10 points
    - Vertebral level correct: 5 points
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
    normal_range = metadata.get('normal_angle_range', {'min': 50, 'max': 100})
    
    angle_error_max = thresholds.get('angle_error_max_degrees', 10.0)
    z_error_max = thresholds.get('z_position_error_max_mm', 15.0)
    
    w_angle = weights.get('angle_accuracy', 35)
    w_level = weights.get('correct_anatomical_level', 20)
    w_markup = weights.get('markup_quality', 15)
    w_class = weights.get('classification_correct', 15)
    w_report = weights.get('report_completeness', 10)
    w_vert = weights.get('vertebral_level_correct', 5)
    
    # ============================================================
    # Copy result file from container
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/carinal_task_result.json", temp_result.name)
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
    
    # ============================================================
    # Load ground truth
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/carinal_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use default reference values
        gt_data = {
            "carinal_angle_degrees": 70.0,
            "carina_z_mm": 0,
            "vertebral_level": "T6",
            "classification": "Normal"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_angle = gt_data.get('carinal_angle_degrees', 70.0)
    gt_z_mm = gt_data.get('carina_z_mm', 0)
    gt_vertebral = gt_data.get('vertebral_level', 'T6')
    gt_classification = gt_data.get('classification', 'Normal')
    data_source = gt_data.get('data_source', 'unknown')
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {
        'gt_angle_degrees': gt_angle,
        'gt_classification': gt_classification,
        'gt_vertebral_level': gt_vertebral,
        'data_source': data_source
    }
    
    # ============================================================
    # Check if Slicer was running
    # ============================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion",
            "details": to_python_type(details)
        }
    
    # ============================================================
    # CRITERION 1: Markup Quality (15 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if measurement_exists and file_created:
        score += w_markup
        feedback_parts.append(f"✓ Angle markup created ({w_markup} pts)")
    elif measurement_exists:
        score += w_markup * 0.7
        feedback_parts.append(f"△ Markup exists but may not be from this task ({int(w_markup * 0.7)} pts)")
    else:
        feedback_parts.append("✗ No angle markup found")
        details['measurement_exists'] = False
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    # ============================================================
    # CRITERION 2: Angle Accuracy (35 points)
    # ============================================================
    agent_angle = 0.0
    measured_str = result.get('measured_angle_degrees', '')
    reported_str = result.get('reported_angle_degrees', '')
    
    # Try measured angle first, then reported
    for angle_str in [measured_str, reported_str]:
        if angle_str:
            try:
                agent_angle = float(angle_str)
                if agent_angle > 0:
                    break
            except (ValueError, TypeError):
                continue
    
    details['agent_angle_degrees'] = agent_angle
    
    if agent_angle > 0:
        angle_error = abs(agent_angle - gt_angle)
        details['angle_error_degrees'] = angle_error
        
        # For real CT data with reference values, be more lenient
        effective_error_max = angle_error_max
        if data_source in ['CTChest_sample', 'CTChest_downloaded']:
            effective_error_max = 15.0  # More tolerance for real data
        
        if angle_error <= effective_error_max:
            score += w_angle
            feedback_parts.append(f"✓ Angle accurate: {agent_angle:.1f}° (GT: {gt_angle:.1f}°, error: {angle_error:.1f}°) ({w_angle} pts)")
        elif angle_error <= effective_error_max * 2:
            partial = int(w_angle * 0.5)
            score += partial
            feedback_parts.append(f"△ Angle partially accurate: {agent_angle:.1f}° (GT: {gt_angle:.1f}°, error: {angle_error:.1f}°) ({partial} pts)")
        else:
            feedback_parts.append(f"✗ Angle inaccurate: {agent_angle:.1f}° (GT: {gt_angle:.1f}°, error: {angle_error:.1f}°)")
    else:
        feedback_parts.append("✗ Could not extract angle measurement")
    
    # ============================================================
    # CRITERION 3: Correct Anatomical Level (20 points)
    # ============================================================
    agent_z_mm = 0.0
    z_str = result.get('measurement_z_mm', '')
    if z_str:
        try:
            agent_z_mm = float(z_str)
        except (ValueError, TypeError):
            pass
    
    details['agent_z_mm'] = agent_z_mm
    
    if agent_z_mm != 0 and gt_z_mm != 0:
        z_error = abs(agent_z_mm - gt_z_mm)
        details['z_error_mm'] = z_error
        
        if z_error <= z_error_max:
            score += w_level
            feedback_parts.append(f"✓ Correct anatomical level (z-error: {z_error:.1f}mm) ({w_level} pts)")
        elif z_error <= z_error_max * 2:
            partial = int(w_level * 0.5)
            score += partial
            feedback_parts.append(f"△ Near correct level (z-error: {z_error:.1f}mm) ({partial} pts)")
        else:
            feedback_parts.append(f"✗ Measurement not at carina level (z-error: {z_error:.1f}mm)")
    elif agent_z_mm != 0:
        # Can't verify z-position exactly, give partial credit if measurement exists
        score += int(w_level * 0.5)
        feedback_parts.append(f"△ Cannot verify exact z-position ({int(w_level * 0.5)} pts)")
    else:
        feedback_parts.append("✗ Cannot determine measurement location")
    
    # ============================================================
    # CRITERION 4: Classification Correct (15 points)
    # ============================================================
    agent_classification = result.get('reported_classification', '')
    
    # Also derive classification from measured angle
    if agent_angle > 0 and not agent_classification:
        agent_classification = classify_angle(agent_angle)
    
    details['agent_classification'] = agent_classification
    
    if agent_classification:
        # Normalize for comparison
        agent_class_norm = agent_classification.lower().strip()
        gt_class_norm = gt_classification.lower().strip()
        
        if agent_class_norm == gt_class_norm:
            score += w_class
            feedback_parts.append(f"✓ Classification correct: {agent_classification} ({w_class} pts)")
        else:
            feedback_parts.append(f"✗ Classification incorrect: {agent_classification} (expected: {gt_classification})")
    else:
        feedback_parts.append("✗ No classification provided")
    
    # ============================================================
    # CRITERION 5: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        has_angle = bool(result.get('reported_angle_degrees', ''))
        has_class = bool(result.get('reported_classification', ''))
        has_level = bool(result.get('reported_vertebral_level', ''))
        
        completeness = sum([has_angle, has_class, has_level]) / 3.0
        report_points = int(w_report * completeness)
        score += report_points
        
        if completeness >= 0.9:
            feedback_parts.append(f"✓ Report complete ({report_points} pts)")
        elif completeness > 0:
            feedback_parts.append(f"△ Report partially complete ({report_points} pts)")
        else:
            feedback_parts.append("✗ Report empty")
    else:
        feedback_parts.append("✗ No report file found")
    
    # ============================================================
    # CRITERION 6: Vertebral Level (5 points)
    # ============================================================
    agent_vertebral = result.get('reported_vertebral_level', '')
    details['agent_vertebral_level'] = agent_vertebral
    
    if agent_vertebral and gt_vertebral:
        # Extract vertebral numbers for comparison
        def parse_vertebra(v):
            v = v.upper().strip()
            if v.startswith('T'):
                try:
                    return ('T', int(v[1:]))
                except:
                    return (v, 0)
            elif v.startswith('C'):
                try:
                    return ('C', int(v[1:]))
                except:
                    return (v, 0)
            return (v, 0)
        
        agent_parsed = parse_vertebra(agent_vertebral)
        gt_parsed = parse_vertebra(gt_vertebral)
        
        if agent_parsed[0] == gt_parsed[0]:
            level_diff = abs(agent_parsed[1] - gt_parsed[1])
            if level_diff == 0:
                score += w_vert
                feedback_parts.append(f"✓ Vertebral level correct: {agent_vertebral} ({w_vert} pts)")
            elif level_diff <= 1:
                score += int(w_vert * 0.5)
                feedback_parts.append(f"△ Vertebral level close: {agent_vertebral} (GT: {gt_vertebral}) ({int(w_vert * 0.5)} pts)")
            else:
                feedback_parts.append(f"✗ Vertebral level incorrect: {agent_vertebral} (GT: {gt_vertebral})")
        else:
            feedback_parts.append(f"✗ Vertebral region incorrect: {agent_vertebral}")
    elif agent_vertebral:
        score += int(w_vert * 0.3)
        feedback_parts.append(f"△ Vertebral level provided but cannot verify ({int(w_vert * 0.3)} pts)")
    
    # ============================================================
    # Determine pass/fail
    # ============================================================
    # Pass requires:
    # 1. Score >= 60
    # 2. Angle measurement exists
    # 3. Reasonable angle value (20-150 degrees - physiologically plausible)
    
    angle_plausible = 20 <= agent_angle <= 150
    key_criteria_met = measurement_exists and (agent_angle > 0) and angle_plausible
    
    passed = score >= 60 and key_criteria_met
    
    if not angle_plausible and agent_angle > 0:
        feedback_parts.append(f"⚠ Angle {agent_angle:.1f}° outside plausible range (20-150°)")
    
    details['score_breakdown'] = {
        'markup_quality': w_markup if (measurement_exists and file_created) else 0,
        'angle_accuracy': w_angle if (agent_angle > 0 and abs(agent_angle - gt_angle) <= angle_error_max) else 0,
        'anatomical_level': 'partial',
        'classification': w_class if (agent_classification.lower().strip() == gt_classification.lower().strip()) else 0,
        'report': 'partial',
        'vertebral_level': 'partial'
    }
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }