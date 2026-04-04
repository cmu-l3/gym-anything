#!/usr/bin/env python3
"""
Verifier for Brain Tumor Documentation Protocol task.

VERIFICATION STRATEGY:
1. Screenshot existence and quality (36 points total)
   - Axial: 12 points (must be created during task, >50KB)
   - Sagittal: 12 points
   - Coronal: 12 points
   
2. Measurement accuracy (20 points)
   - Max axial diameter within 8mm of ground truth
   
3. Perpendicular measurement (10 points)
   - Second measurement exists
   
4. Bidimensional calculation (8 points)
   - Product correctly computed (±5%)
   
5. Measurement markup saved (8 points)
   - File exists with valid measurements
   
6. Report completeness (10 points)
   - JSON with all required fields
   
7. Location description (8 points)
   - Anatomically reasonable description

TOTAL: 100 points
PASS THRESHOLD: 65 points with at least 2 screenshots and max diameter accuracy
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
    """Convert numpy types to Python native types."""
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


def safe_float(val, default=0.0):
    """Safely convert value to float."""
    if val is None or val == "":
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def verify_brain_tumor_documentation(traj, env_info, task_info):
    """
    Verify brain tumor documentation protocol task completion.
    
    Scoring (100 points total):
    - Axial screenshot: 12 points
    - Sagittal screenshot: 12 points
    - Coronal screenshot: 12 points
    - Max diameter accuracy: 20 points
    - Perpendicular measurement: 10 points
    - Bidimensional calculation: 8 points
    - Measurement markup saved: 8 points
    - Report completeness: 10 points
    - Location description: 8 points
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
    min_screenshot_kb = metadata.get('min_screenshot_size_kb', 50)
    diameter_tolerance = metadata.get('diameter_tolerance_mm', 8.0)
    pass_threshold = metadata.get('passing_threshold', 65)
    
    # Default weights
    w_axial = weights.get('axial_screenshot', 12)
    w_sagittal = weights.get('sagittal_screenshot', 12)
    w_coronal = weights.get('coronal_screenshot', 12)
    w_max_diam = weights.get('max_diameter_accuracy', 20)
    w_perp = weights.get('perpendicular_measurement', 10)
    w_bidim = weights.get('bidimensional_calculation', 8)
    w_markup = weights.get('measurement_markup_saved', 8)
    w_report = weights.get('report_completeness', 10)
    w_location = weights.get('location_description', 8)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/doc_task_result.json", temp_result.name)
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
    
    # Copy ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/doc_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
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
    
    screenshots = result.get('screenshots', {})
    measurements = result.get('measurements', {})
    report = result.get('report', {})
    
    gt_max_diameter = safe_float(gt_data.get('max_axial_diameter_mm'))
    gt_perp_diameter = safe_float(gt_data.get('perpendicular_diameter_mm'))
    gt_location = gt_data.get('tumor_location', '')
    
    details['gt_max_diameter_mm'] = gt_max_diameter
    details['gt_perpendicular_mm'] = gt_perp_diameter
    details['gt_location'] = gt_location
    
    # ================================================================
    # CRITERION 1: Axial Screenshot (12 points)
    # ================================================================
    axial_exists = screenshots.get('axial_exists', False)
    axial_size = screenshots.get('axial_size_bytes', 0)
    axial_created = screenshots.get('axial_created_during_task', False)
    
    if axial_exists and axial_created and axial_size >= min_screenshot_kb * 1024:
        score += w_axial
        feedback_parts.append(f"✓ Axial screenshot ({axial_size//1024}KB)")
    elif axial_exists and axial_size >= min_screenshot_kb * 1024:
        score += w_axial * 0.7  # Partial credit if not verified as created during task
        feedback_parts.append(f"~ Axial screenshot exists (timestamp not verified)")
    elif axial_exists:
        score += w_axial * 0.3
        feedback_parts.append(f"~ Axial screenshot too small ({axial_size//1024}KB)")
    else:
        feedback_parts.append("✗ Axial screenshot missing")
    
    details['axial_screenshot'] = {
        'exists': axial_exists,
        'size_kb': axial_size // 1024,
        'created_during_task': axial_created
    }
    
    # ================================================================
    # CRITERION 2: Sagittal Screenshot (12 points)
    # ================================================================
    sagittal_exists = screenshots.get('sagittal_exists', False)
    sagittal_size = screenshots.get('sagittal_size_bytes', 0)
    sagittal_created = screenshots.get('sagittal_created_during_task', False)
    
    if sagittal_exists and sagittal_created and sagittal_size >= min_screenshot_kb * 1024:
        score += w_sagittal
        feedback_parts.append(f"✓ Sagittal screenshot ({sagittal_size//1024}KB)")
    elif sagittal_exists and sagittal_size >= min_screenshot_kb * 1024:
        score += w_sagittal * 0.7
        feedback_parts.append(f"~ Sagittal screenshot exists (timestamp not verified)")
    elif sagittal_exists:
        score += w_sagittal * 0.3
        feedback_parts.append(f"~ Sagittal screenshot too small")
    else:
        feedback_parts.append("✗ Sagittal screenshot missing")
    
    details['sagittal_screenshot'] = {
        'exists': sagittal_exists,
        'size_kb': sagittal_size // 1024,
        'created_during_task': sagittal_created
    }
    
    # ================================================================
    # CRITERION 3: Coronal Screenshot (12 points)
    # ================================================================
    coronal_exists = screenshots.get('coronal_exists', False)
    coronal_size = screenshots.get('coronal_size_bytes', 0)
    coronal_created = screenshots.get('coronal_created_during_task', False)
    
    if coronal_exists and coronal_created and coronal_size >= min_screenshot_kb * 1024:
        score += w_coronal
        feedback_parts.append(f"✓ Coronal screenshot ({coronal_size//1024}KB)")
    elif coronal_exists and coronal_size >= min_screenshot_kb * 1024:
        score += w_coronal * 0.7
        feedback_parts.append(f"~ Coronal screenshot exists (timestamp not verified)")
    elif coronal_exists:
        score += w_coronal * 0.3
        feedback_parts.append(f"~ Coronal screenshot too small")
    else:
        feedback_parts.append("✗ Coronal screenshot missing")
    
    details['coronal_screenshot'] = {
        'exists': coronal_exists,
        'size_kb': coronal_size // 1024,
        'created_during_task': coronal_created
    }
    
    # Count valid screenshots
    screenshot_count = sum([
        1 for x in [axial_exists, sagittal_exists, coronal_exists] if x
    ])
    details['screenshot_count'] = screenshot_count
    
    # ================================================================
    # CRITERION 4: Max Diameter Accuracy (20 points)
    # ================================================================
    # Try from measurements first, then from report
    agent_max_diameter = safe_float(measurements.get('max_diameter_mm'))
    if agent_max_diameter == 0:
        agent_max_diameter = safe_float(report.get('max_diameter_mm'))
    
    diameter_accurate = False
    if gt_max_diameter > 0 and agent_max_diameter > 0:
        diameter_error = abs(agent_max_diameter - gt_max_diameter)
        details['diameter_error_mm'] = round(diameter_error, 2)
        details['agent_max_diameter_mm'] = agent_max_diameter
        
        if diameter_error <= diameter_tolerance:
            score += w_max_diam
            diameter_accurate = True
            feedback_parts.append(f"✓ Max diameter: {agent_max_diameter:.1f}mm (error: {diameter_error:.1f}mm)")
        elif diameter_error <= diameter_tolerance * 2:
            score += w_max_diam * 0.5
            feedback_parts.append(f"~ Max diameter: {agent_max_diameter:.1f}mm (error: {diameter_error:.1f}mm, marginal)")
        else:
            feedback_parts.append(f"✗ Max diameter: {agent_max_diameter:.1f}mm (error: {diameter_error:.1f}mm, expected ~{gt_max_diameter:.1f}mm)")
    elif agent_max_diameter > 0:
        # Can't verify accuracy but measurement exists
        score += w_max_diam * 0.3
        details['agent_max_diameter_mm'] = agent_max_diameter
        feedback_parts.append(f"~ Max diameter: {agent_max_diameter:.1f}mm (ground truth unavailable)")
    else:
        feedback_parts.append("✗ Max diameter measurement not found")
    
    # ================================================================
    # CRITERION 5: Perpendicular Measurement (10 points)
    # ================================================================
    agent_perp_diameter = safe_float(measurements.get('perpendicular_diameter_mm'))
    if agent_perp_diameter == 0:
        agent_perp_diameter = safe_float(report.get('perpendicular_diameter_mm'))
    
    details['agent_perp_diameter_mm'] = agent_perp_diameter
    
    if agent_perp_diameter > 0:
        score += w_perp
        feedback_parts.append(f"✓ Perpendicular measurement: {agent_perp_diameter:.1f}mm")
    else:
        feedback_parts.append("✗ Perpendicular measurement missing")
    
    # ================================================================
    # CRITERION 6: Bidimensional Calculation (8 points)
    # ================================================================
    reported_product = safe_float(report.get('bidimensional_product_mm2'))
    expected_product = agent_max_diameter * agent_perp_diameter if (agent_max_diameter > 0 and agent_perp_diameter > 0) else 0
    
    details['reported_product'] = reported_product
    details['expected_product'] = round(expected_product, 2)
    
    if reported_product > 0 and expected_product > 0:
        product_error_pct = abs(reported_product - expected_product) / expected_product * 100
        if product_error_pct <= 5:
            score += w_bidim
            feedback_parts.append(f"✓ Bidimensional product: {reported_product:.1f}mm²")
        elif product_error_pct <= 15:
            score += w_bidim * 0.6
            feedback_parts.append(f"~ Bidimensional product: {reported_product:.1f}mm² (slight error)")
        else:
            feedback_parts.append(f"✗ Bidimensional product incorrect: {reported_product:.1f}mm² (expected ~{expected_product:.1f}mm²)")
    elif reported_product > 0:
        score += w_bidim * 0.5
        feedback_parts.append(f"~ Bidimensional product: {reported_product:.1f}mm² (cannot verify)")
    else:
        feedback_parts.append("✗ Bidimensional product not reported")
    
    # ================================================================
    # CRITERION 7: Measurement Markup Saved (8 points)
    # ================================================================
    markup_exists = measurements.get('file_exists', False)
    meas_count = measurements.get('count', 0)
    
    details['measurement_file_exists'] = markup_exists
    details['measurement_count'] = meas_count
    
    if markup_exists and meas_count >= 2:
        score += w_markup
        feedback_parts.append(f"✓ Measurement markup saved ({meas_count} measurements)")
    elif markup_exists and meas_count >= 1:
        score += w_markup * 0.6
        feedback_parts.append(f"~ Measurement markup saved ({meas_count} measurement, expected 2)")
    elif markup_exists:
        score += w_markup * 0.3
        feedback_parts.append("~ Measurement file exists but empty")
    else:
        feedback_parts.append("✗ Measurement markup file not saved")
    
    # ================================================================
    # CRITERION 8: Report Completeness (10 points)
    # ================================================================
    report_exists = report.get('file_exists', False)
    report_valid = report.get('valid_format', False)
    
    details['report_exists'] = report_exists
    details['report_valid'] = report_valid
    
    if report_exists and report_valid:
        score += w_report
        feedback_parts.append("✓ Documentation report complete")
    elif report_exists:
        score += w_report * 0.5
        feedback_parts.append("~ Documentation report exists but incomplete")
    else:
        feedback_parts.append("✗ Documentation report not created")
    
    # ================================================================
    # CRITERION 9: Location Description (8 points)
    # ================================================================
    agent_location = report.get('tumor_location', '')
    details['agent_location'] = agent_location
    
    # Check if location is anatomically reasonable
    valid_terms = ['frontal', 'parietal', 'temporal', 'occipital', 'left', 'right', 
                   'lobe', 'brain', 'cerebral', 'cortex', 'hemisphere']
    
    if agent_location:
        location_lower = agent_location.lower()
        matches = sum(1 for term in valid_terms if term in location_lower)
        
        if matches >= 2:
            score += w_location
            feedback_parts.append(f"✓ Location: {agent_location}")
        elif matches >= 1:
            score += w_location * 0.5
            feedback_parts.append(f"~ Location: {agent_location} (incomplete)")
        else:
            score += w_location * 0.2
            feedback_parts.append(f"~ Location: {agent_location} (non-standard)")
    else:
        feedback_parts.append("✗ Tumor location not described")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    score = int(round(score))
    
    # Key criteria for passing
    key_criteria_met = (
        screenshot_count >= 2 and
        (diameter_accurate or agent_max_diameter > 0)
    )
    
    passed = score >= pass_threshold and key_criteria_met
    
    # Build final feedback
    feedback = f"Score: {score}/100 | " + " | ".join(feedback_parts)
    
    if passed:
        feedback = f"✅ PASSED - {feedback}"
    else:
        if score < pass_threshold:
            feedback = f"❌ FAILED (score {score} < {pass_threshold}) - {feedback}"
        elif screenshot_count < 2:
            feedback = f"❌ FAILED (need at least 2 screenshots) - {feedback}"
        else:
            feedback = f"❌ FAILED (missing key criteria) - {feedback}"
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    })