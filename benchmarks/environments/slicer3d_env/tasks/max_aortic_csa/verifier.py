#!/usr/bin/env python3
"""
Verifier for maximum aortic cross-sectional area (CSA) measurement task.

VERIFICATION METRICS:
1. CSA Accuracy - how close is agent's measurement to ground truth (±20%)
2. CSA Accuracy Bonus - extra points for ±10% accuracy
3. Location Accuracy - was measurement taken at the correct slice (±15mm)
4. Measurement File Exists - did agent create a measurement markup
5. Equivalent Diameter Correct - mathematically correct calculation
6. Clinical Assessment Correct - proper classification (Normal/Ectatic/Aneurysmal)
7. Screenshot Captured - evidence of measurement process

ANTI-GAMING:
- Check file timestamps to ensure work was done during task
- Verify CSA is anatomically reasonable (200-2000 mm²)
- Require both CSA accuracy AND location accuracy for full pass

Scoring (100 points total):
- CSA accuracy ±20%: 30 points
- CSA accuracy ±10% bonus: 10 points
- Location accuracy: 20 points
- Measurement file exists: 15 points
- Equivalent diameter correct: 10 points
- Clinical assessment correct: 10 points
- Screenshot captured: 5 points

Pass threshold: 60 points with CSA accuracy ±20% achieved
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


def parse_float(val, default=0.0):
    """Safely parse a float value from various input types."""
    if val is None or val == '':
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def calculate_equivalent_diameter(csa_mm2):
    """Calculate equivalent diameter from CSA: d = 2 * sqrt(CSA / π)"""
    if csa_mm2 <= 0:
        return 0.0
    return 2 * math.sqrt(csa_mm2 / math.pi)


def get_classification(diameter_mm):
    """Get clinical classification based on equivalent diameter."""
    if diameter_mm < 30:
        return "Normal"
    elif diameter_mm < 35:
        return "Ectatic"
    else:
        return "Aneurysmal"


def verify_max_aortic_csa(traj, env_info, task_info):
    """
    Verify maximum aortic CSA measurement task completion.
    
    Uses copy_from_env to retrieve task results and ground truth.
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
    anatomical_bounds = metadata.get('anatomical_bounds', {})
    
    csa_error_max_pct = thresholds.get('csa_error_max_percent', 20)
    location_error_max_mm = thresholds.get('location_error_max_mm', 15)
    
    w_csa_20pct = weights.get('csa_accuracy_20pct', 30)
    w_csa_10pct_bonus = weights.get('csa_accuracy_10pct_bonus', 10)
    w_location = weights.get('location_accuracy', 20)
    w_measurement = weights.get('measurement_file_exists', 15)
    w_diameter = weights.get('equivalent_diameter_correct', 10)
    w_classification = weights.get('clinical_assessment_correct', 10)
    w_screenshot = weights.get('screenshot_captured', 5)
    
    min_csa = anatomical_bounds.get('min_csa_mm2', 200)
    max_csa = anatomical_bounds.get('max_csa_mm2', 2000)
    
    # ============================================================
    # LOAD TASK RESULT
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/max_aorta_task_result.json", temp_result.name)
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
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/max_csa_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_csa = parse_float(gt_data.get('max_csa_mm2', 0))
    gt_z_mm = parse_float(gt_data.get('slice_z_mm', 0))
    gt_diameter = parse_float(gt_data.get('equivalent_diameter_mm', 0))
    gt_classification = gt_data.get('classification', '')
    
    # ============================================================
    # INITIALIZE SCORING
    # ============================================================
    score = 0
    feedback_parts = []
    details = {
        "gt_csa_mm2": gt_csa,
        "gt_z_mm": gt_z_mm,
        "gt_diameter_mm": gt_diameter,
        "gt_classification": gt_classification
    }
    
    # ============================================================
    # CHECK BASIC REQUIREMENTS
    # ============================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion",
            "details": to_python_type(details)
        }
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    agent_csa = 0.0
    agent_z = 0.0
    agent_diameter = 0.0
    agent_classification = ''
    
    # Try from reported values in result
    reported_csa_str = result.get('reported_csa_mm2', '')
    reported_z_str = result.get('reported_z_mm', '')
    reported_diameter_str = result.get('reported_diameter_mm', '')
    reported_classification = result.get('reported_classification', '')
    
    if reported_csa_str:
        agent_csa = parse_float(reported_csa_str)
    
    if reported_z_str:
        agent_z = parse_float(reported_z_str)
    
    if reported_diameter_str:
        agent_diameter = parse_float(reported_diameter_str)
    
    if reported_classification:
        agent_classification = reported_classification.strip()
    
    # If no report, try from measurement file
    if agent_csa == 0:
        measured_csa_str = result.get('measured_csa_mm2', '')
        if measured_csa_str:
            agent_csa = parse_float(measured_csa_str)
    
    # Also try to load agent's measurement file directly
    if agent_csa == 0:
        temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_measurement.json", temp_meas.name)
            with open(temp_meas.name, 'r') as f:
                meas_data = json.load(f)
            
            measurements = meas_data.get('measurements', [])
            for m in measurements:
                if m.get('type') == 'closed_curve' and m.get('area_mm2', 0) > 0:
                    agent_csa = parse_float(m.get('area_mm2'))
                    center = m.get('center', [0, 0, 0])
                    if len(center) >= 3:
                        agent_z = parse_float(center[2])
                    break
                elif m.get('type') == 'line' and m.get('estimated_csa_mm2', 0) > 0:
                    agent_csa = parse_float(m.get('estimated_csa_mm2'))
                    agent_z = parse_float(m.get('center_z', 0))
                    break
        except Exception as e:
            logger.debug(f"Could not load agent measurement file: {e}")
        finally:
            if os.path.exists(temp_meas.name):
                os.unlink(temp_meas.name)
    
    # Try agent's report file
    if agent_csa == 0 or agent_classification == '':
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_data = json.load(f)
            
            if agent_csa == 0:
                for key in ['max_csa_mm2', 'csa_mm2', 'area_mm2', 'cross_sectional_area']:
                    if key in report_data:
                        agent_csa = parse_float(report_data[key])
                        break
            
            if agent_z == 0:
                for key in ['slice_z_mm', 'z_mm', 'location_z', 'slice_location']:
                    if key in report_data:
                        agent_z = parse_float(report_data[key])
                        break
            
            if agent_diameter == 0:
                for key in ['equivalent_diameter_mm', 'diameter_mm', 'equiv_diameter']:
                    if key in report_data:
                        agent_diameter = parse_float(report_data[key])
                        break
            
            if agent_classification == '':
                for key in ['clinical_assessment', 'classification', 'assessment']:
                    if key in report_data:
                        agent_classification = str(report_data[key]).strip()
                        break
        except Exception as e:
            logger.debug(f"Could not load agent report file: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    
    details['agent_csa_mm2'] = agent_csa
    details['agent_z_mm'] = agent_z
    details['agent_diameter_mm'] = agent_diameter
    details['agent_classification'] = agent_classification
    
    # ============================================================
    # CRITERION 1: CSA ACCURACY (30 points for ±20%)
    # ============================================================
    csa_accurate_20pct = False
    csa_accurate_10pct = False
    
    if agent_csa > 0 and gt_csa > 0:
        csa_error_pct = abs(agent_csa - gt_csa) / gt_csa * 100
        details['csa_error_percent'] = round(csa_error_pct, 1)
        
        # Check anatomical reasonableness
        if agent_csa < min_csa or agent_csa > max_csa:
            feedback_parts.append(f"❌ CSA {agent_csa:.0f}mm² outside anatomical range ({min_csa}-{max_csa}mm²)")
        elif csa_error_pct <= csa_error_max_pct:
            csa_accurate_20pct = True
            score += w_csa_20pct
            feedback_parts.append(f"✅ CSA accurate within {csa_error_max_pct}%: {agent_csa:.0f}mm² (GT: {gt_csa:.0f}mm², error: {csa_error_pct:.1f}%)")
            
            # Bonus for ±10%
            if csa_error_pct <= 10:
                csa_accurate_10pct = True
                score += w_csa_10pct_bonus
                feedback_parts.append(f"✅ BONUS: CSA accurate within 10%")
        else:
            feedback_parts.append(f"❌ CSA error too large: {agent_csa:.0f}mm² vs GT {gt_csa:.0f}mm² ({csa_error_pct:.1f}% > {csa_error_max_pct}%)")
    elif agent_csa > 0:
        feedback_parts.append(f"⚠️ Agent measured CSA {agent_csa:.0f}mm² but no ground truth available")
    else:
        feedback_parts.append("❌ No CSA measurement found")
    
    # ============================================================
    # CRITERION 2: LOCATION ACCURACY (20 points)
    # ============================================================
    location_accurate = False
    
    if agent_z != 0 and gt_z_mm != 0:
        z_error_mm = abs(agent_z - gt_z_mm)
        details['z_error_mm'] = round(z_error_mm, 1)
        
        if z_error_mm <= location_error_max_mm:
            location_accurate = True
            score += w_location
            feedback_parts.append(f"✅ Location accurate: z={agent_z:.1f}mm (GT: {gt_z_mm:.1f}mm, error: {z_error_mm:.1f}mm)")
        else:
            feedback_parts.append(f"❌ Location error too large: z={agent_z:.1f}mm vs GT {gt_z_mm:.1f}mm ({z_error_mm:.1f}mm > {location_error_max_mm}mm)")
    elif agent_z != 0:
        feedback_parts.append(f"⚠️ Agent reported z={agent_z:.1f}mm but no ground truth available")
        score += w_location // 2  # Partial credit
    else:
        feedback_parts.append("❌ No slice location reported")
    
    # ============================================================
    # CRITERION 3: MEASUREMENT FILE EXISTS (15 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    
    if measurement_exists:
        score += w_measurement
        feedback_parts.append("✅ Measurement file created")
    else:
        feedback_parts.append("❌ No measurement file found")
    
    # ============================================================
    # CRITERION 4: EQUIVALENT DIAMETER CORRECT (10 points)
    # ============================================================
    if agent_csa > 0:
        expected_diameter = calculate_equivalent_diameter(agent_csa)
        details['expected_diameter_from_csa'] = round(expected_diameter, 1)
        
        if agent_diameter > 0:
            diameter_error = abs(agent_diameter - expected_diameter)
            if diameter_error <= 1.0:  # Within 1mm tolerance
                score += w_diameter
                feedback_parts.append(f"✅ Equivalent diameter correct: {agent_diameter:.1f}mm (expected: {expected_diameter:.1f}mm)")
            else:
                feedback_parts.append(f"❌ Diameter calculation incorrect: {agent_diameter:.1f}mm (expected: {expected_diameter:.1f}mm)")
        else:
            feedback_parts.append("❌ No equivalent diameter reported")
    
    # ============================================================
    # CRITERION 5: CLINICAL ASSESSMENT CORRECT (10 points)
    # ============================================================
    if agent_classification:
        # Normalize classification
        agent_class_normalized = agent_classification.lower().strip()
        gt_class_normalized = gt_classification.lower().strip() if gt_classification else ''
        
        # Also check against what their CSA would indicate
        if agent_csa > 0:
            expected_class_from_csa = get_classification(calculate_equivalent_diameter(agent_csa)).lower()
        else:
            expected_class_from_csa = ''
        
        classification_correct = False
        if gt_class_normalized and agent_class_normalized == gt_class_normalized:
            classification_correct = True
        elif expected_class_from_csa and agent_class_normalized == expected_class_from_csa:
            classification_correct = True
        
        if classification_correct:
            score += w_classification
            feedback_parts.append(f"✅ Clinical classification correct: {agent_classification}")
        else:
            feedback_parts.append(f"❌ Classification incorrect: '{agent_classification}' (expected: '{gt_classification}')")
    else:
        feedback_parts.append("❌ No clinical classification provided")
    
    # ============================================================
    # CRITERION 6: SCREENSHOT CAPTURED (5 points)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_during_task = result.get('screenshot_created_during_task', False)
    
    if screenshot_during_task:
        score += w_screenshot
        feedback_parts.append("✅ Screenshot captured during task")
    elif screenshot_exists:
        score += w_screenshot // 2
        feedback_parts.append("⚠️ Screenshot exists but may not be from this task")
    else:
        feedback_parts.append("❌ No screenshot captured")
    
    # ============================================================
    # FINAL DETERMINATION
    # ============================================================
    # Pass requires:
    # 1. Score >= 60
    # 2. CSA accuracy within 20% achieved
    key_criteria_met = csa_accurate_20pct
    passed = score >= 60 and key_criteria_met
    
    if passed:
        feedback_parts.insert(0, f"✅ PASSED - Score: {score}/100")
    else:
        if not key_criteria_met:
            feedback_parts.insert(0, f"❌ FAILED - CSA accuracy not achieved. Score: {score}/100")
        else:
            feedback_parts.insert(0, f"❌ FAILED - Score below threshold. Score: {score}/100")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }