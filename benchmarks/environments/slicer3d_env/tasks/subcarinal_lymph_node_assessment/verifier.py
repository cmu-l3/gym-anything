#!/usr/bin/env python3
"""
Verifier for Subcarinal Lymph Node Station Assessment task.

VERIFICATION STRATEGY:
1. Correct anatomical location (25 pts) - measurement in subcarinal space
2. Mediastinal window applied (10 pts) - evidence of appropriate W/L
3. Measurement accuracy (20 pts) - short axis within tolerance of GT
4. Classification correct (20 pts) - Normal/Indeterminate/Enlarged
5. Report completeness (15 pts) - all required fields present
6. Internal consistency (10 pts) - measurement matches classification

Station 7 (Subcarinal) boundaries:
- Superior: Carina (tracheal bifurcation)
- Inferior: ~40mm below carina
- Lateral: Main bronchi
- Posterior: Esophagus
- Anterior: Main pulmonary artery
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


def verify_subcarinal_lymph_node_assessment(traj, env_info, task_info):
    """
    Verify subcarinal lymph node assessment task completion.
    
    Scoring (100 points total):
    - Correct anatomical location: 25 points
    - Mediastinal window applied: 10 points
    - Measurement accuracy: 20 points
    - Classification correct: 20 points
    - Report completeness: 15 points
    - Internal consistency: 10 points
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
    size_thresholds = metadata.get('size_thresholds', {})
    
    location_tolerance = thresholds.get('location_tolerance_mm', 30)
    measurement_tolerance = thresholds.get('measurement_tolerance_mm', 3)
    
    normal_max = size_thresholds.get('normal_max_mm', 10)
    indeterminate_max = size_thresholds.get('indeterminate_max_mm', 15)
    
    w_location = weights.get('correct_anatomical_location', 25)
    w_window = weights.get('mediastinal_window', 10)
    w_measurement = weights.get('measurement_accuracy', 20)
    w_classification = weights.get('classification_correct', 20)
    w_report = weights.get('report_completeness', 15)
    w_consistency = weights.get('internal_consistency', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/subcarinal_task_result.json", temp_result.name)
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
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/station7_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Extract ground truth values
    carina_z = gt_data.get('carina_z_mm', 0)
    subcarinal_range = gt_data.get('subcarinal_z_range_mm', [0, -45])
    gt_ln = gt_data.get('reference_lymph_node', {})
    gt_ln_present = gt_ln.get('present', False)
    gt_short_axis = gt_ln.get('short_axis_mm')
    gt_classification = gt_ln.get('classification', 'Normal')
    
    details['gt_carina_z'] = carina_z
    details['gt_subcarinal_range'] = subcarinal_range
    details['gt_ln_present'] = gt_ln_present
    details['gt_short_axis'] = gt_short_axis
    details['gt_classification'] = gt_classification
    
    # ================================================================
    # CRITERION 1: Correct Anatomical Location (25 points)
    # ================================================================
    location_score = 0
    
    # Check measurement Z position or current slice position
    meas_z_str = result.get('measurement_z_mm', '') or result.get('current_slice_z_mm', '')
    agent_z = None
    
    if meas_z_str:
        try:
            agent_z = float(meas_z_str)
        except (ValueError, TypeError):
            pass
    
    # Also check from reported slice position
    if agent_z is None:
        reported_z_str = result.get('reported_slice_z_mm', '')
        if reported_z_str:
            try:
                agent_z = float(reported_z_str)
            except (ValueError, TypeError):
                pass
    
    if agent_z is not None:
        details['agent_z_position'] = agent_z
        
        # Check if within subcarinal region
        subcarinal_sup = subcarinal_range[0] if len(subcarinal_range) > 0 else carina_z - 5
        subcarinal_inf = subcarinal_range[1] if len(subcarinal_range) > 1 else carina_z - 45
        
        # Allow some tolerance
        in_subcarinal = (subcarinal_inf - location_tolerance <= agent_z <= subcarinal_sup + location_tolerance)
        
        if in_subcarinal:
            location_score = w_location
            feedback_parts.append(f"✓ Correct anatomical location (z={agent_z:.1f}mm in subcarinal space)")
        else:
            # Partial credit if close
            distance_to_region = min(
                abs(agent_z - subcarinal_sup),
                abs(agent_z - subcarinal_inf)
            )
            if distance_to_region < location_tolerance * 2:
                location_score = w_location * 0.5
                feedback_parts.append(f"~ Partially correct location (z={agent_z:.1f}mm, {distance_to_region:.1f}mm from Station 7)")
            else:
                feedback_parts.append(f"✗ Incorrect location (z={agent_z:.1f}mm, not in subcarinal space)")
    else:
        # Can still get partial credit if measurement exists
        if result.get('measurement_exists', False):
            location_score = w_location * 0.3
            feedback_parts.append("~ Measurement exists but location uncertain")
        else:
            feedback_parts.append("✗ No measurement or location data found")
    
    score += location_score
    details['location_score'] = location_score
    
    # ================================================================
    # CRITERION 2: Mediastinal Window Applied (10 points)
    # ================================================================
    window_score = 0
    
    # Use VLM to check screenshot for mediastinal window if available
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import get_final_screenshot
            final_screenshot = get_final_screenshot(traj)
            
            if final_screenshot:
                vlm_prompt = """Look at this medical imaging screenshot from 3D Slicer.

Is the CT image displayed with mediastinal/soft tissue window settings?
Mediastinal window shows:
- Soft tissues (heart, vessels, mediastinal structures) as varying shades of gray
- NOT lung window (where lungs appear very dark/black and airways are prominent)

Look for: gray mediastinal structures visible, not predominantly black lung fields.

Respond with JSON:
{
    "mediastinal_window": true/false,
    "reasoning": "brief explanation"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('mediastinal_window', False):
                        window_score = w_window
                        feedback_parts.append("✓ Mediastinal window applied")
                    else:
                        window_score = w_window * 0.3
                        feedback_parts.append("~ Window settings may not be optimal")
                    details['vlm_window_check'] = parsed
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Give benefit of doubt
            window_score = w_window * 0.5
            feedback_parts.append("~ Window settings could not be verified")
    else:
        # Give partial credit without VLM
        window_score = w_window * 0.5
        feedback_parts.append("~ Window settings not verified (VLM unavailable)")
    
    score += window_score
    details['window_score'] = window_score
    
    # ================================================================
    # CRITERION 3: Measurement Accuracy (20 points)
    # ================================================================
    measurement_score = 0
    agent_measurement = None
    
    # Get agent's measurement
    meas_str = result.get('measured_length_mm', '') or result.get('reported_short_axis_mm', '')
    if meas_str:
        try:
            agent_measurement = float(meas_str)
        except (ValueError, TypeError):
            pass
    
    details['agent_measurement_mm'] = agent_measurement
    
    if gt_ln_present and gt_short_axis is not None:
        # Ground truth has a lymph node - check measurement accuracy
        if agent_measurement is not None:
            error = abs(agent_measurement - gt_short_axis)
            details['measurement_error_mm'] = error
            
            if error <= measurement_tolerance:
                measurement_score = w_measurement
                feedback_parts.append(f"✓ Measurement accurate ({agent_measurement:.1f}mm, error: {error:.1f}mm)")
            elif error <= measurement_tolerance * 2:
                measurement_score = w_measurement * 0.6
                feedback_parts.append(f"~ Measurement close ({agent_measurement:.1f}mm, error: {error:.1f}mm)")
            elif error <= measurement_tolerance * 3:
                measurement_score = w_measurement * 0.3
                feedback_parts.append(f"~ Measurement imprecise ({agent_measurement:.1f}mm, error: {error:.1f}mm)")
            else:
                feedback_parts.append(f"✗ Measurement inaccurate ({agent_measurement:.1f}mm vs GT: {gt_short_axis:.1f}mm)")
        else:
            # Lymph node exists but not measured
            feedback_parts.append("✗ Lymph node present but no measurement made")
    else:
        # No ground truth lymph node
        if agent_measurement is None:
            # Correctly did not measure (no LN)
            measurement_score = w_measurement
            feedback_parts.append("✓ Correctly identified no discrete lymph node requiring measurement")
        else:
            # Agent measured something when no LN exists
            # Partial credit if measurement is in reasonable range
            if 3 <= agent_measurement <= 15:
                measurement_score = w_measurement * 0.3
                feedback_parts.append(f"~ Measurement made ({agent_measurement:.1f}mm) but no significant LN in GT")
            else:
                feedback_parts.append(f"✗ Spurious measurement ({agent_measurement:.1f}mm)")
    
    score += measurement_score
    details['measurement_score'] = measurement_score
    
    # ================================================================
    # CRITERION 4: Classification Correct (20 points)
    # ================================================================
    classification_score = 0
    agent_classification = result.get('reported_classification', '').strip()
    
    details['agent_classification'] = agent_classification
    
    # Normalize classification strings
    def normalize_class(c):
        c = str(c).lower().strip()
        if 'normal' in c:
            return 'Normal'
        elif 'indeterminate' in c or 'borderline' in c:
            return 'Indeterminate'
        elif 'enlarged' in c or 'pathologic' in c or 'abnormal' in c:
            return 'Pathologically Enlarged'
        return c
    
    agent_class_norm = normalize_class(agent_classification)
    gt_class_norm = normalize_class(gt_classification)
    
    if agent_class_norm and gt_class_norm:
        if agent_class_norm == gt_class_norm:
            classification_score = w_classification
            feedback_parts.append(f"✓ Classification correct ({agent_class_norm})")
        else:
            # Check if adjacent category (partial credit)
            categories = ['Normal', 'Indeterminate', 'Pathologically Enlarged']
            try:
                agent_idx = categories.index(agent_class_norm)
                gt_idx = categories.index(gt_class_norm)
                if abs(agent_idx - gt_idx) == 1:
                    classification_score = w_classification * 0.5
                    feedback_parts.append(f"~ Classification partially correct ({agent_class_norm} vs {gt_class_norm})")
                else:
                    feedback_parts.append(f"✗ Classification incorrect ({agent_class_norm} vs {gt_class_norm})")
            except ValueError:
                feedback_parts.append(f"✗ Classification incorrect ({agent_class_norm} vs {gt_class_norm})")
    elif not agent_classification:
        feedback_parts.append("✗ No classification provided")
    
    score += classification_score
    details['classification_score'] = classification_score
    
    # ================================================================
    # CRITERION 5: Report Completeness (15 points)
    # ================================================================
    report_score = 0
    
    if result.get('report_exists', False):
        # Check required fields
        required_fields = ['lymph_node_identified', 'classification']
        optional_fields = ['short_axis_mm', 'slice_position_mm', 'station']
        
        fields_present = 0
        
        # Check from report content
        ln_found = result.get('reported_lymph_node_found', '')
        if ln_found:
            fields_present += 1
        
        if agent_classification:
            fields_present += 1
        
        reported_axis = result.get('reported_short_axis_mm', '')
        if reported_axis:
            fields_present += 1
        
        reported_z = result.get('reported_slice_z_mm', '')
        if reported_z:
            fields_present += 1
        
        # Calculate score
        if fields_present >= 4:
            report_score = w_report
            feedback_parts.append("✓ Report complete with all fields")
        elif fields_present >= 2:
            report_score = w_report * 0.7
            feedback_parts.append(f"~ Report partially complete ({fields_present}/4 key fields)")
        elif fields_present >= 1:
            report_score = w_report * 0.3
            feedback_parts.append(f"~ Report minimal ({fields_present}/4 key fields)")
        
        # Bonus for task-specific file creation
        if result.get('report_created_during_task', False):
            report_score = min(report_score + 2, w_report)
    else:
        feedback_parts.append("✗ No report file created")
    
    score += report_score
    details['report_score'] = report_score
    
    # ================================================================
    # CRITERION 6: Internal Consistency (10 points)
    # ================================================================
    consistency_score = 0
    
    if agent_measurement is not None and agent_classification:
        # Check if classification matches measurement
        expected_class = 'Normal'
        if agent_measurement >= 10:
            expected_class = 'Indeterminate'
        if agent_measurement > 15:
            expected_class = 'Pathologically Enlarged'
        
        if agent_class_norm == expected_class:
            consistency_score = w_consistency
            feedback_parts.append("✓ Classification consistent with measurement")
        else:
            feedback_parts.append(f"~ Classification inconsistent (measured {agent_measurement:.1f}mm → expected {expected_class})")
    elif agent_measurement is None and agent_class_norm == 'Normal':
        # No measurement + Normal classification is consistent
        consistency_score = w_consistency
        feedback_parts.append("✓ No lymph node found - Normal classification consistent")
    elif agent_measurement is None and not agent_classification:
        # No data
        feedback_parts.append("~ Consistency cannot be verified (missing data)")
    else:
        # Measurement without classification or vice versa
        consistency_score = w_consistency * 0.3
        feedback_parts.append("~ Partial consistency check")
    
    score += consistency_score
    details['consistency_score'] = consistency_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Pass requires: 60+ points AND at least one of (location correct OR measurement made)
    key_criteria_met = (location_score >= w_location * 0.5) or (measurement_score >= w_measurement * 0.5)
    passed = score >= 60 and key_criteria_met
    
    # Compile final feedback
    feedback = " | ".join(feedback_parts)
    
    # Convert all numpy types
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": int(round(score)),
        "feedback": feedback,
        "details": details,
        "subscores": {
            "location": location_score,
            "window": window_score,
            "measurement": measurement_score,
            "classification": classification_score,
            "report": report_score,
            "consistency": consistency_score
        }
    }