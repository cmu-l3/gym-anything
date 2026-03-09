#!/usr/bin/env python3
"""
Verifier for Cardiac RV/LV Ratio Assessment task.

VERIFICATION METRICS:
1. RV diameter accuracy - within 5mm of ground truth (25 points)
2. LV diameter accuracy - within 5mm of ground truth (25 points)
3. RV/LV ratio present in report (10 points)
4. RV/LV ratio accuracy - within 0.15 of ground truth (15 points)
5. Clinical classification correct (15 points)
6. Report completeness - all required fields (10 points)

Anti-gaming checks:
- Measurements must be created during task (timestamp check)
- Values must be in physiological range
- Report values must be consistent with measurements

Pass threshold: 60 points with at least one diameter within tolerance
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


def extract_length_from_markup(markup_data):
    """
    Extract length measurement from Slicer markup JSON format.
    
    Args:
        markup_data: Parsed JSON from .mrk.json file
        
    Returns:
        float or None: Length in mm if found
    """
    try:
        if 'markups' in markup_data and len(markup_data['markups']) > 0:
            markup = markup_data['markups'][0]
            
            # Method 1: Calculate from control points
            if 'controlPoints' in markup and len(markup['controlPoints']) >= 2:
                p1 = markup['controlPoints'][0].get('position', [0, 0, 0])
                p2 = markup['controlPoints'][1].get('position', [0, 0, 0])
                length = math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))
                if length > 0:
                    return length
            
            # Method 2: Look in measurements array
            if 'measurements' in markup:
                for m in markup['measurements']:
                    name = m.get('name', '').lower()
                    if 'length' in name or name == 'length':
                        return float(m.get('value', 0))
        
        # Method 3: Direct measurements field at root
        if 'measurements' in markup_data:
            for m in markup_data['measurements']:
                if m.get('type') == 'line' and 'length_mm' in m:
                    return float(m['length_mm'])
                    
    except Exception as e:
        logger.warning(f"Error extracting length: {e}")
    
    return None


def get_classification(ratio):
    """Get clinical classification based on RV/LV ratio."""
    if ratio < 0.9:
        return "Normal"
    elif ratio <= 1.0:
        return "Borderline"
    else:
        return "RV Dilation"


def verify_cardiac_rv_lv_ratio(traj, env_info, task_info):
    """
    Verify cardiac RV/LV ratio measurement task completion.
    
    Uses multi-criteria scoring:
    - RV diameter accuracy: 25 points (within 5mm)
    - LV diameter accuracy: 25 points (within 5mm)
    - Ratio present: 10 points
    - Ratio accuracy: 15 points (within 0.15)
    - Classification correct: 15 points
    - Report completeness: 10 points
    
    Total: 100 points
    Pass threshold: 60 points with at least one measurement accurate
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
    phys_ranges = metadata.get('physiological_ranges', {})
    
    diameter_error_max = thresholds.get('diameter_error_max_mm', 5.0)
    ratio_error_max = thresholds.get('ratio_error_max', 0.15)
    
    w_rv = weights.get('rv_diameter_accuracy', 25)
    w_lv = weights.get('lv_diameter_accuracy', 25)
    w_ratio_present = weights.get('ratio_present', 10)
    w_ratio_accuracy = weights.get('ratio_accuracy', 15)
    w_classification = weights.get('classification_correct', 15)
    w_report = weights.get('report_completeness', 10)
    
    rv_min = phys_ranges.get('rv_min_mm', 15)
    rv_max = phys_ranges.get('rv_max_mm', 80)
    lv_min = phys_ranges.get('lv_min_mm', 20)
    lv_max = phys_ranges.get('lv_max_mm', 80)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # LOAD TASK RESULT
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/cardiac_task_result.json", temp_result.name)
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
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - task not performed"
        }
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/cardiac_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Ground truth unavailable: {e}"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_rv = gt_data.get('rv_diameter_mm', 0)
    gt_lv = gt_data.get('lv_diameter_mm', 0)
    gt_ratio = gt_data.get('rv_lv_ratio', 0)
    gt_classification = gt_data.get('classification', '')
    
    details['ground_truth'] = {
        'rv_mm': gt_rv,
        'lv_mm': gt_lv,
        'ratio': gt_ratio,
        'classification': gt_classification
    }
    
    # ================================================================
    # EXTRACT AGENT MEASUREMENTS
    # ================================================================
    agent_rv = None
    agent_lv = None
    agent_ratio = None
    agent_classification = None
    
    # Try to get RV from measurement file
    rv_str = result.get('rv_diameter_mm', '')
    if rv_str:
        try:
            agent_rv = float(rv_str)
        except ValueError:
            pass
    
    # If not in result, try to load markup file directly
    if agent_rv is None and result.get('rv_measurement_exists', False):
        temp_rv = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/home/ga/Documents/SlicerData/Cardiac/rv_measurement.mrk.json", temp_rv.name)
            with open(temp_rv.name, 'r') as f:
                rv_markup = json.load(f)
            agent_rv = extract_length_from_markup(rv_markup)
        except Exception as e:
            logger.warning(f"Could not load RV markup: {e}")
        finally:
            if os.path.exists(temp_rv.name):
                os.unlink(temp_rv.name)
    
    # Try to get LV from measurement file
    lv_str = result.get('lv_diameter_mm', '')
    if lv_str:
        try:
            agent_lv = float(lv_str)
        except ValueError:
            pass
    
    # If not in result, try to load markup file directly
    if agent_lv is None and result.get('lv_measurement_exists', False):
        temp_lv = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/home/ga/Documents/SlicerData/Cardiac/lv_measurement.mrk.json", temp_lv.name)
            with open(temp_lv.name, 'r') as f:
                lv_markup = json.load(f)
            agent_lv = extract_length_from_markup(lv_markup)
        except Exception as e:
            logger.warning(f"Could not load LV markup: {e}")
        finally:
            if os.path.exists(temp_lv.name):
                os.unlink(temp_lv.name)
    
    # Get reported values from JSON report
    reported_rv = result.get('reported_rv_mm', '')
    reported_lv = result.get('reported_lv_mm', '')
    reported_ratio_str = result.get('reported_ratio', '')
    reported_class = result.get('reported_classification', '')
    
    # Use reported values if measurement extraction failed
    if agent_rv is None and reported_rv:
        try:
            agent_rv = float(reported_rv)
        except ValueError:
            pass
    
    if agent_lv is None and reported_lv:
        try:
            agent_lv = float(reported_lv)
        except ValueError:
            pass
    
    if reported_ratio_str:
        try:
            agent_ratio = float(reported_ratio_str)
        except ValueError:
            pass
    
    agent_classification = reported_class.strip() if reported_class else None
    
    details['agent'] = {
        'rv_mm': agent_rv,
        'lv_mm': agent_lv,
        'ratio': agent_ratio,
        'classification': agent_classification
    }
    
    # ================================================================
    # CRITERION 1: RV Diameter Accuracy (25 points)
    # ================================================================
    rv_accurate = False
    if agent_rv is not None:
        details['agent_rv_mm'] = round(agent_rv, 1)
        
        # Check physiological range
        if rv_min <= agent_rv <= rv_max:
            rv_error = abs(agent_rv - gt_rv)
            details['rv_error_mm'] = round(rv_error, 1)
            
            if rv_error <= diameter_error_max:
                score += w_rv
                rv_accurate = True
                feedback_parts.append(f"✓ RV accurate: {agent_rv:.1f}mm (GT: {gt_rv:.1f}mm, error: {rv_error:.1f}mm)")
            elif rv_error <= diameter_error_max * 2:
                score += w_rv * 0.5
                feedback_parts.append(f"~ RV close: {agent_rv:.1f}mm (GT: {gt_rv:.1f}mm, error: {rv_error:.1f}mm)")
            else:
                feedback_parts.append(f"✗ RV inaccurate: {agent_rv:.1f}mm (GT: {gt_rv:.1f}mm, error: {rv_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ RV outside physiological range: {agent_rv:.1f}mm (expected {rv_min}-{rv_max}mm)")
    else:
        feedback_parts.append("✗ RV measurement not found")
    
    # ================================================================
    # CRITERION 2: LV Diameter Accuracy (25 points)
    # ================================================================
    lv_accurate = False
    if agent_lv is not None:
        details['agent_lv_mm'] = round(agent_lv, 1)
        
        if lv_min <= agent_lv <= lv_max:
            lv_error = abs(agent_lv - gt_lv)
            details['lv_error_mm'] = round(lv_error, 1)
            
            if lv_error <= diameter_error_max:
                score += w_lv
                lv_accurate = True
                feedback_parts.append(f"✓ LV accurate: {agent_lv:.1f}mm (GT: {gt_lv:.1f}mm, error: {lv_error:.1f}mm)")
            elif lv_error <= diameter_error_max * 2:
                score += w_lv * 0.5
                feedback_parts.append(f"~ LV close: {agent_lv:.1f}mm (GT: {gt_lv:.1f}mm, error: {lv_error:.1f}mm)")
            else:
                feedback_parts.append(f"✗ LV inaccurate: {agent_lv:.1f}mm (GT: {gt_lv:.1f}mm, error: {lv_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ LV outside physiological range: {agent_lv:.1f}mm (expected {lv_min}-{lv_max}mm)")
    else:
        feedback_parts.append("✗ LV measurement not found")
    
    # ================================================================
    # CRITERION 3: Ratio Present (10 points)
    # ================================================================
    if agent_ratio is not None:
        score += w_ratio_present
        details['agent_ratio'] = round(agent_ratio, 3)
        feedback_parts.append(f"✓ RV/LV ratio reported: {agent_ratio:.3f}")
    elif agent_rv is not None and agent_lv is not None and agent_lv > 0:
        # Calculate from measurements
        agent_ratio = agent_rv / agent_lv
        score += w_ratio_present * 0.5
        details['agent_ratio_calculated'] = round(agent_ratio, 3)
        feedback_parts.append(f"~ Ratio calculated from measurements: {agent_ratio:.3f}")
    else:
        feedback_parts.append("✗ RV/LV ratio not found")
    
    # ================================================================
    # CRITERION 4: Ratio Accuracy (15 points)
    # ================================================================
    if agent_ratio is not None:
        ratio_error = abs(agent_ratio - gt_ratio)
        details['ratio_error'] = round(ratio_error, 3)
        
        if ratio_error <= ratio_error_max:
            score += w_ratio_accuracy
            feedback_parts.append(f"✓ Ratio accurate (error: {ratio_error:.3f})")
        elif ratio_error <= ratio_error_max * 2:
            score += w_ratio_accuracy * 0.5
            feedback_parts.append(f"~ Ratio close (error: {ratio_error:.3f})")
        else:
            feedback_parts.append(f"✗ Ratio inaccurate (error: {ratio_error:.3f}, max: {ratio_error_max})")
    
    # ================================================================
    # CRITERION 5: Classification Correct (15 points)
    # ================================================================
    if agent_classification:
        details['agent_classification'] = agent_classification
        
        # Normalize for comparison
        agent_class_norm = agent_classification.lower().replace('_', ' ').replace('-', ' ').strip()
        gt_class_norm = gt_classification.lower()
        
        # Check for match
        class_correct = False
        if gt_class_norm == 'normal' and 'normal' in agent_class_norm:
            class_correct = True
        elif gt_class_norm == 'borderline' and 'borderline' in agent_class_norm:
            class_correct = True
        elif gt_class_norm == 'rv dilation' and ('dilation' in agent_class_norm or 'dilat' in agent_class_norm or 'strain' in agent_class_norm or 'enlarged' in agent_class_norm):
            class_correct = True
        
        if class_correct:
            score += w_classification
            feedback_parts.append(f"✓ Classification correct: {agent_classification}")
        else:
            feedback_parts.append(f"✗ Classification incorrect: {agent_classification} (expected: {gt_classification})")
    else:
        feedback_parts.append("✗ Classification not provided")
    
    # ================================================================
    # CRITERION 6: Report Completeness (10 points)
    # ================================================================
    report_fields_found = 0
    required_fields = ['rv', 'lv', 'ratio', 'classification']
    
    if agent_rv is not None:
        report_fields_found += 1
    if agent_lv is not None:
        report_fields_found += 1
    if agent_ratio is not None:
        report_fields_found += 1
    if agent_classification:
        report_fields_found += 1
    
    completeness_ratio = report_fields_found / len(required_fields)
    score += int(w_report * completeness_ratio)
    details['report_completeness'] = f"{report_fields_found}/{len(required_fields)}"
    
    if report_fields_found == len(required_fields):
        feedback_parts.append("✓ Report complete")
    elif report_fields_found > 0:
        feedback_parts.append(f"~ Report partial ({report_fields_found}/{len(required_fields)} fields)")
    else:
        feedback_parts.append("✗ Report empty")
    
    # ================================================================
    # ANTI-GAMING: Timestamp Checks
    # ================================================================
    rv_created = result.get('rv_created_during_task', False)
    lv_created = result.get('lv_created_during_task', False)
    
    if not rv_created and not lv_created:
        if agent_rv is not None or agent_lv is not None:
            score = max(0, score - 15)
            feedback_parts.append("⚠ Warning: Measurements may predate task")
            details['timestamp_warning'] = True
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    score = int(score)
    
    # Key criteria: at least one diameter accurate
    key_criteria_met = rv_accurate or lv_accurate
    
    passed = score >= 60 and key_criteria_met
    
    if passed:
        feedback_parts.insert(0, f"✓ PASSED (Score: {score}/100)")
    else:
        if not key_criteria_met:
            feedback_parts.insert(0, f"✗ FAILED - No accurate measurements (Score: {score}/100)")
        else:
            feedback_parts.insert(0, f"✗ FAILED - Score below threshold (Score: {score}/100)")
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "max_score": 100,
        "feedback": " | ".join(feedback_parts),
        "details": details
    })


if __name__ == "__main__":
    # For testing
    result = verify_cardiac_rv_lv_ratio({}, {}, {})
    print(json.dumps(result, indent=2))
    sys.exit(0 if result.get("passed") else 1)