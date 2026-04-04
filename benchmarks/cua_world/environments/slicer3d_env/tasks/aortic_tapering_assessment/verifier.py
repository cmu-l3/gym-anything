#!/usr/bin/env python3
"""
Verifier for aortic tapering assessment task.

VERIFICATION METRICS (100 points total):
1. Suprarenal measurement accuracy (12 points) - within 4mm of ground truth
2. Infrarenal measurement accuracy (12 points) - within 4mm of ground truth
3. Bifurcation measurement accuracy (12 points) - within 4mm of ground truth
4. Measurement locations valid (8 points) - Z-coordinates at appropriate levels
5. Ratio calculations correct (10 points) - within 0.1 of expected
6. Focal dilation detected (15 points) - binary detection
7. Focal dilation size (8 points) - within 5mm of ground truth
8. Tapering assessment (10 points) - correct classification
9. Clinical recommendation (5 points) - appropriate given findings
10. File completeness (8 points) - all required fields present

Pass Threshold: 60 points with at least 2/3 measurements accurate AND focal dilation detected
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


def verify_aortic_tapering(traj, env_info, task_info):
    """
    Verify aortic tapering assessment task completion.
    
    Uses multi-criteria scoring with anti-gaming measures.
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
    
    diameter_error_max = thresholds.get('diameter_error_max_mm', 4.0)
    ratio_error_max = thresholds.get('ratio_error_max', 0.1)
    focal_size_error_max = thresholds.get('focal_dilation_size_error_mm', 5.0)
    
    w_suprarenal = weights.get('suprarenal_measurement', 12)
    w_infrarenal = weights.get('infrarenal_measurement', 12)
    w_bifurcation = weights.get('bifurcation_measurement', 12)
    w_locations = weights.get('measurement_locations_valid', 8)
    w_ratios = weights.get('ratio_calculations_correct', 10)
    w_focal_detect = weights.get('focal_dilation_detected', 15)
    w_focal_size = weights.get('focal_dilation_size', 8)
    w_tapering = weights.get('tapering_assessment', 10)
    w_clinical = weights.get('clinical_recommendation', 5)
    w_completeness = weights.get('file_completeness', 8)
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/aortic_tapering_result.json", temp_result.name)
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
    # Initialize scoring
    # ================================================================
    score = 0
    feedback_parts = []
    details = {}
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/aortic_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Extract ground truth values
    gt_max_diameter = gt_data.get('max_diameter_mm', 33.0)
    gt_classification = gt_data.get('classification', 'Ectatic')
    gt_max_slice = gt_data.get('max_slice_idx', 45)
    gt_vertebral_level = gt_data.get('approximate_vertebral_level', 'L2')
    
    # For synthetic AMOS data, we know the aortic geometry:
    # Suprarenal (~z=80-90): ~22-24mm
    # Infrarenal (~z=50-60): ~18-20mm (normal taper)
    # Bifurcation (~z=10-20): ~16-18mm
    # Focal dilation (~z=45): ~33mm (ectatic)
    
    gt_suprarenal = gt_data.get('suprarenal_diameter_mm', 23.0)
    gt_infrarenal = gt_data.get('infrarenal_diameter_mm', 19.0)
    gt_bifurcation = gt_data.get('bifurcation_diameter_mm', 17.0)
    gt_focal_diameter = gt_data.get('focal_dilation_diameter_mm', gt_max_diameter)
    gt_has_focal = gt_data.get('has_focal_dilation', True)
    
    # Expected ratios
    gt_infrarenal_ratio = gt_infrarenal / gt_suprarenal if gt_suprarenal > 0 else 0
    gt_bifurcation_ratio = gt_bifurcation / gt_suprarenal if gt_suprarenal > 0 else 0
    
    details['ground_truth'] = {
        'suprarenal_mm': gt_suprarenal,
        'infrarenal_mm': gt_infrarenal,
        'bifurcation_mm': gt_bifurcation,
        'focal_dilation_mm': gt_focal_diameter,
        'has_focal_dilation': gt_has_focal,
        'infrarenal_ratio': round(gt_infrarenal_ratio, 3),
        'bifurcation_ratio': round(gt_bifurcation_ratio, 3)
    }
    
    # ================================================================
    # Load agent report
    # ================================================================
    agent_report = {}
    if result.get('report_exists', False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                agent_report = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load agent report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    
    # ================================================================
    # Load agent measurements
    # ================================================================
    agent_measurements = []
    if result.get('measurement_exists', False):
        temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_measurements.json", temp_meas.name)
            with open(temp_meas.name, 'r') as f:
                meas_data = json.load(f)
                agent_measurements = meas_data.get('measurements', [])
        except Exception as e:
            logger.warning(f"Failed to load agent measurements: {e}")
        finally:
            if os.path.exists(temp_meas.name):
                os.unlink(temp_meas.name)
    
    details['agent_measurement_count'] = len(agent_measurements)
    
    # ================================================================
    # Extract agent values from report or measurements
    # ================================================================
    agent_suprarenal = None
    agent_infrarenal = None
    agent_bifurcation = None
    agent_focal_present = None
    agent_focal_diameter = None
    agent_tapering_assessment = None
    agent_clinical_rec = None
    agent_infrarenal_ratio = None
    agent_bifurcation_ratio = None
    
    # Try to get values from report first
    if agent_report:
        agent_suprarenal = agent_report.get('suprarenal_diameter_mm')
        agent_infrarenal = agent_report.get('infrarenal_diameter_mm')
        agent_bifurcation = agent_report.get('bifurcation_diameter_mm')
        agent_focal_present = agent_report.get('focal_dilation_present')
        agent_focal_diameter = agent_report.get('focal_dilation_max_diameter_mm')
        agent_tapering_assessment = agent_report.get('tapering_assessment')
        agent_clinical_rec = agent_report.get('clinical_recommendation')
        agent_infrarenal_ratio = agent_report.get('infrarenal_suprarenal_ratio')
        agent_bifurcation_ratio = agent_report.get('bifurcation_suprarenal_ratio')
    
    # Try to extract from measurements if not in report
    if agent_measurements and (agent_suprarenal is None or agent_infrarenal is None or agent_bifurcation is None):
        # Sort measurements by Z coordinate (descending = superior to inferior)
        line_measurements = [m for m in agent_measurements if m.get('type') == 'line']
        line_measurements.sort(key=lambda x: x.get('z_coordinate', 0), reverse=True)
        
        # Assign measurements based on position
        # Highest Z = suprarenal, Middle = infrarenal, Lowest = bifurcation
        if len(line_measurements) >= 3:
            if agent_suprarenal is None:
                agent_suprarenal = line_measurements[0].get('length_mm')
            if agent_infrarenal is None:
                agent_infrarenal = line_measurements[1].get('length_mm')
            if agent_bifurcation is None:
                agent_bifurcation = line_measurements[2].get('length_mm')
        elif len(line_measurements) == 2:
            if agent_suprarenal is None:
                agent_suprarenal = line_measurements[0].get('length_mm')
            if agent_infrarenal is None:
                agent_infrarenal = line_measurements[1].get('length_mm')
        elif len(line_measurements) == 1:
            # Single measurement - might be focal dilation
            single_val = line_measurements[0].get('length_mm')
            if single_val and single_val > 28:  # Likely focal dilation
                agent_focal_diameter = single_val
    
    details['agent_values'] = {
        'suprarenal_mm': agent_suprarenal,
        'infrarenal_mm': agent_infrarenal,
        'bifurcation_mm': agent_bifurcation,
        'focal_present': agent_focal_present,
        'focal_diameter_mm': agent_focal_diameter,
        'tapering_assessment': agent_tapering_assessment,
        'infrarenal_ratio': agent_infrarenal_ratio,
        'bifurcation_ratio': agent_bifurcation_ratio
    }
    
    # ================================================================
    # CRITERION 1: Suprarenal measurement (12 points)
    # ================================================================
    suprarenal_accurate = False
    if agent_suprarenal is not None:
        try:
            agent_suprarenal = float(agent_suprarenal)
            suprarenal_error = abs(agent_suprarenal - gt_suprarenal)
            if suprarenal_error <= diameter_error_max:
                score += w_suprarenal
                suprarenal_accurate = True
                feedback_parts.append(f"✓ Suprarenal: {agent_suprarenal:.1f}mm (GT: {gt_suprarenal:.1f}mm)")
            else:
                partial = w_suprarenal * max(0, 1 - suprarenal_error / 10)
                score += partial
                feedback_parts.append(f"✗ Suprarenal: {agent_suprarenal:.1f}mm (GT: {gt_suprarenal:.1f}mm, error: {suprarenal_error:.1f}mm)")
        except (TypeError, ValueError):
            feedback_parts.append("✗ Suprarenal: Invalid value")
    else:
        feedback_parts.append("✗ Suprarenal: Not measured")
    
    # ================================================================
    # CRITERION 2: Infrarenal measurement (12 points)
    # ================================================================
    infrarenal_accurate = False
    if agent_infrarenal is not None:
        try:
            agent_infrarenal = float(agent_infrarenal)
            infrarenal_error = abs(agent_infrarenal - gt_infrarenal)
            if infrarenal_error <= diameter_error_max:
                score += w_infrarenal
                infrarenal_accurate = True
                feedback_parts.append(f"✓ Infrarenal: {agent_infrarenal:.1f}mm (GT: {gt_infrarenal:.1f}mm)")
            else:
                partial = w_infrarenal * max(0, 1 - infrarenal_error / 10)
                score += partial
                feedback_parts.append(f"✗ Infrarenal: {agent_infrarenal:.1f}mm (GT: {gt_infrarenal:.1f}mm, error: {infrarenal_error:.1f}mm)")
        except (TypeError, ValueError):
            feedback_parts.append("✗ Infrarenal: Invalid value")
    else:
        feedback_parts.append("✗ Infrarenal: Not measured")
    
    # ================================================================
    # CRITERION 3: Bifurcation measurement (12 points)
    # ================================================================
    bifurcation_accurate = False
    if agent_bifurcation is not None:
        try:
            agent_bifurcation = float(agent_bifurcation)
            bifurcation_error = abs(agent_bifurcation - gt_bifurcation)
            if bifurcation_error <= diameter_error_max:
                score += w_bifurcation
                bifurcation_accurate = True
                feedback_parts.append(f"✓ Bifurcation: {agent_bifurcation:.1f}mm (GT: {gt_bifurcation:.1f}mm)")
            else:
                partial = w_bifurcation * max(0, 1 - bifurcation_error / 10)
                score += partial
                feedback_parts.append(f"✗ Bifurcation: {agent_bifurcation:.1f}mm (GT: {gt_bifurcation:.1f}mm, error: {bifurcation_error:.1f}mm)")
        except (TypeError, ValueError):
            feedback_parts.append("✗ Bifurcation: Invalid value")
    else:
        feedback_parts.append("✗ Bifurcation: Not measured")
    
    accurate_count = sum([suprarenal_accurate, infrarenal_accurate, bifurcation_accurate])
    details['accurate_measurements'] = accurate_count
    
    # ================================================================
    # CRITERION 4: Measurement locations valid (8 points)
    # ================================================================
    locations_valid = False
    if agent_measurements:
        line_measurements = [m for m in agent_measurements if m.get('type') == 'line']
        if len(line_measurements) >= 3:
            # Check if measurements are at different Z levels
            z_coords = [m.get('z_coordinate', 0) for m in line_measurements]
            z_range = max(z_coords) - min(z_coords) if z_coords else 0
            
            # For synthetic data: volume is 100 slices * 2.5mm spacing = 250mm
            # Suprarenal to bifurcation should span at least 100mm
            if z_range >= 50:  # At least 50mm spread (conservative threshold)
                score += w_locations
                locations_valid = True
                feedback_parts.append(f"✓ Measurement locations span {z_range:.1f}mm")
            else:
                score += w_locations * 0.5
                feedback_parts.append(f"△ Measurement locations span only {z_range:.1f}mm")
        else:
            feedback_parts.append(f"✗ Only {len(line_measurements)} measurements placed (need 3)")
    else:
        feedback_parts.append("✗ No measurements found")
    
    # ================================================================
    # CRITERION 5: Ratio calculations correct (10 points)
    # ================================================================
    ratios_correct = False
    if agent_infrarenal_ratio is not None and agent_bifurcation_ratio is not None:
        try:
            agent_ir = float(agent_infrarenal_ratio)
            agent_br = float(agent_bifurcation_ratio)
            
            ir_error = abs(agent_ir - gt_infrarenal_ratio)
            br_error = abs(agent_br - gt_bifurcation_ratio)
            
            if ir_error <= ratio_error_max and br_error <= ratio_error_max:
                score += w_ratios
                ratios_correct = True
                feedback_parts.append(f"✓ Ratios correct (IR: {agent_ir:.2f}, BR: {agent_br:.2f})")
            else:
                # Partial credit
                ratio_score = 0
                if ir_error <= ratio_error_max:
                    ratio_score += w_ratios / 2
                if br_error <= ratio_error_max:
                    ratio_score += w_ratios / 2
                score += ratio_score
                feedback_parts.append(f"△ Ratio errors: IR={ir_error:.2f}, BR={br_error:.2f}")
        except (TypeError, ValueError):
            feedback_parts.append("✗ Invalid ratio values")
    elif agent_suprarenal and agent_infrarenal and agent_bifurcation:
        # Calculate ratios from measurements if not provided
        try:
            calc_ir = float(agent_infrarenal) / float(agent_suprarenal)
            calc_br = float(agent_bifurcation) / float(agent_suprarenal)
            
            ir_error = abs(calc_ir - gt_infrarenal_ratio)
            br_error = abs(calc_br - gt_bifurcation_ratio)
            
            if ir_error <= ratio_error_max and br_error <= ratio_error_max:
                score += w_ratios * 0.8  # Slight penalty for not reporting explicitly
                feedback_parts.append(f"✓ Calculated ratios correct (IR: {calc_ir:.2f}, BR: {calc_br:.2f})")
            else:
                feedback_parts.append(f"△ Calculated ratio errors: IR={ir_error:.2f}, BR={br_error:.2f}")
        except (TypeError, ValueError, ZeroDivisionError):
            feedback_parts.append("✗ Could not calculate ratios")
    else:
        feedback_parts.append("✗ Ratios not provided or calculable")
    
    # ================================================================
    # CRITERION 6: Focal dilation detected (15 points)
    # ================================================================
    focal_detected = False
    if agent_focal_present is not None:
        if agent_focal_present == gt_has_focal:
            score += w_focal_detect
            focal_detected = True
            feedback_parts.append(f"✓ Focal dilation correctly {'detected' if gt_has_focal else 'not detected'}")
        else:
            feedback_parts.append(f"✗ Focal dilation: reported {agent_focal_present}, GT: {gt_has_focal}")
    elif agent_focal_diameter is not None:
        # Infer detection from diameter
        if float(agent_focal_diameter) > 28 and gt_has_focal:
            score += w_focal_detect
            focal_detected = True
            feedback_parts.append(f"✓ Focal dilation detected via measurement ({agent_focal_diameter}mm)")
    else:
        # Check if any measurement exceeds normal range
        for m in agent_measurements:
            if m.get('type') == 'line' and m.get('length_mm', 0) > 28:
                score += w_focal_detect * 0.7
                focal_detected = True
                feedback_parts.append(f"△ Large measurement found ({m.get('length_mm'):.1f}mm) - likely focal dilation")
                break
        if not focal_detected:
            feedback_parts.append("✗ Focal dilation not detected")
    
    # ================================================================
    # CRITERION 7: Focal dilation size (8 points)
    # ================================================================
    focal_size_accurate = False
    if agent_focal_diameter is not None:
        try:
            agent_focal = float(agent_focal_diameter)
            focal_error = abs(agent_focal - gt_focal_diameter)
            if focal_error <= focal_size_error_max:
                score += w_focal_size
                focal_size_accurate = True
                feedback_parts.append(f"✓ Focal size: {agent_focal:.1f}mm (GT: {gt_focal_diameter:.1f}mm)")
            else:
                partial = w_focal_size * max(0, 1 - focal_error / 15)
                score += partial
                feedback_parts.append(f"△ Focal size: {agent_focal:.1f}mm (GT: {gt_focal_diameter:.1f}mm, error: {focal_error:.1f}mm)")
        except (TypeError, ValueError):
            feedback_parts.append("✗ Invalid focal diameter value")
    else:
        feedback_parts.append("✗ Focal dilation size not reported")
    
    # ================================================================
    # CRITERION 8: Tapering assessment (10 points)
    # ================================================================
    tapering_correct = False
    # Expected: with focal dilation present, assessment should be "Focal dilation"
    expected_tapering = "Focal dilation" if gt_has_focal else "Normal"
    
    if agent_tapering_assessment:
        assessment_lower = agent_tapering_assessment.lower()
        expected_lower = expected_tapering.lower()
        
        if expected_lower in assessment_lower or assessment_lower in expected_lower:
            score += w_tapering
            tapering_correct = True
            feedback_parts.append(f"✓ Tapering assessment: {agent_tapering_assessment}")
        elif 'ectatic' in assessment_lower or 'dilation' in assessment_lower:
            # Partial credit for identifying abnormality
            score += w_tapering * 0.7
            feedback_parts.append(f"△ Tapering assessment: {agent_tapering_assessment} (expected: {expected_tapering})")
        else:
            feedback_parts.append(f"✗ Tapering assessment: {agent_tapering_assessment} (expected: {expected_tapering})")
    else:
        feedback_parts.append("✗ Tapering assessment not provided")
    
    # ================================================================
    # CRITERION 9: Clinical recommendation (5 points)
    # ================================================================
    clinical_appropriate = False
    if agent_clinical_rec:
        rec_lower = agent_clinical_rec.lower()
        # For ectatic aorta, should recommend surveillance or referral
        if gt_has_focal and ('surveillance' in rec_lower or 'follow' in rec_lower or 
                            'monitor' in rec_lower or 'refer' in rec_lower or
                            'vascular' in rec_lower):
            score += w_clinical
            clinical_appropriate = True
            feedback_parts.append(f"✓ Clinical recommendation appropriate")
        elif not gt_has_focal and ('routine' in rec_lower or 'normal' in rec_lower):
            score += w_clinical
            clinical_appropriate = True
            feedback_parts.append(f"✓ Clinical recommendation appropriate")
        else:
            score += w_clinical * 0.5
            feedback_parts.append(f"△ Clinical recommendation: {agent_clinical_rec[:50]}...")
    else:
        feedback_parts.append("✗ Clinical recommendation not provided")
    
    # ================================================================
    # CRITERION 10: File completeness (8 points)
    # ================================================================
    required_fields = ['suprarenal_diameter_mm', 'infrarenal_diameter_mm', 'bifurcation_diameter_mm',
                      'infrarenal_suprarenal_ratio', 'bifurcation_suprarenal_ratio',
                      'focal_dilation_present', 'tapering_assessment']
    
    present_fields = 0
    for field in required_fields:
        if field in agent_report:
            present_fields += 1
    
    completeness_pct = present_fields / len(required_fields)
    completeness_score = w_completeness * completeness_pct
    score += completeness_score
    
    if completeness_pct >= 0.9:
        feedback_parts.append(f"✓ Report completeness: {present_fields}/{len(required_fields)} fields")
    elif completeness_pct >= 0.5:
        feedback_parts.append(f"△ Report partially complete: {present_fields}/{len(required_fields)} fields")
    else:
        feedback_parts.append(f"✗ Report incomplete: {present_fields}/{len(required_fields)} fields")
    
    # ================================================================
    # Anti-gaming: Check timestamps
    # ================================================================
    if not result.get('measurement_created_during_task', False) and not result.get('report_created_during_task', False):
        feedback_parts.append("⚠ Warning: Files may have been pre-existing")
        score = score * 0.5  # Penalize potential gaming
    
    # ================================================================
    # Final scoring
    # ================================================================
    score = min(100, max(0, int(round(score))))
    
    # Pass criteria: 60+ points AND (at least 2/3 measurements accurate AND focal dilation detected)
    key_criteria_met = accurate_count >= 2 and focal_detected
    passed = score >= 60 and key_criteria_met
    
    details['score_breakdown'] = {
        'suprarenal_accurate': suprarenal_accurate,
        'infrarenal_accurate': infrarenal_accurate,
        'bifurcation_accurate': bifurcation_accurate,
        'locations_valid': locations_valid,
        'ratios_correct': ratios_correct,
        'focal_detected': focal_detected,
        'focal_size_accurate': focal_size_accurate,
        'tapering_correct': tapering_correct,
        'clinical_appropriate': clinical_appropriate,
        'completeness_pct': completeness_pct
    }
    
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED (Score: {score}/100) | " + feedback
    else:
        if not key_criteria_met:
            feedback = f"FAILED - Key criteria not met (need 2+ accurate measurements AND focal detection) | " + feedback
        else:
            feedback = f"FAILED (Score: {score}/100, need 60) | " + feedback
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    })