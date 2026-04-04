#!/usr/bin/env python3
"""
Verifier for corpus callosum morphometry task.

VERIFICATION METRICS:
1. Total length accuracy - within 8mm of ground truth (25 pts)
2. Genu thickness accuracy - within 3mm of ground truth (15 pts)
3. Body thickness accuracy - within 3mm of ground truth (15 pts)
4. Splenium thickness accuracy - within 3mm of ground truth (15 pts)
5. Mid-sagittal navigation - measurements in correct plane (10 pts)
6. Atrophy classification - correct assessment (10 pts)
7. Report completeness - all required fields present (10 pts)

Ground Truth: Pre-computed measurements from MRHead dataset
Pass Threshold: 60 points with at least 2 thickness measurements within tolerance
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


def parse_float(val):
    """Safely parse a float from various input types."""
    if val is None or val == "":
        return None
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


def classify_atrophy(length_mm, genu_mm, body_mm, splenium_mm):
    """
    Classify corpus callosum atrophy based on measurements.
    
    Returns: "Normal", "Mild", or "Moderate-severe"
    """
    # Get valid measurements
    thicknesses = [t for t in [genu_mm, body_mm, splenium_mm] if t is not None]
    
    if length_mm is None and not thicknesses:
        return "Unknown"
    
    # Check for moderate-severe
    if length_mm is not None and length_mm < 55:
        return "Moderate-severe"
    if any(t < 4 for t in thicknesses if t is not None):
        return "Moderate-severe"
    
    # Check for mild
    if length_mm is not None and 55 <= length_mm <= 65:
        return "Mild"
    if any(4 <= t <= 5 for t in thicknesses if t is not None):
        return "Mild"
    
    # Normal
    if length_mm is not None and length_mm > 65:
        if all(t > 5 for t in thicknesses if t is not None):
            return "Normal"
    
    return "Normal"


def verify_corpus_callosum_morphometry(traj, env_info, task_info):
    """
    Verify corpus callosum morphometry task completion.
    
    Scoring (100 points total):
    - Total length accuracy: 25 points (within 8mm)
    - Genu thickness accuracy: 15 points (within 3mm)
    - Body thickness accuracy: 15 points (within 3mm)
    - Splenium thickness accuracy: 15 points (within 3mm)
    - Mid-sagittal navigation: 10 points
    - Atrophy classification: 10 points
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
    
    length_error_max = thresholds.get('length_error_max_mm', 8.0)
    thickness_error_max = thresholds.get('thickness_error_max_mm', 3.0)
    
    w_length = weights.get('total_length_accuracy', 25)
    w_genu = weights.get('genu_thickness_accuracy', 15)
    w_body = weights.get('body_thickness_accuracy', 15)
    w_splenium = weights.get('splenium_thickness_accuracy', 15)
    w_navigation = weights.get('mid_sagittal_navigation', 10)
    w_classification = weights.get('atrophy_classification', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/cc_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/cc_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use default ground truth values
        gt_data = {
            "measurements": {
                "total_length_mm": 71.5,
                "genu_thickness_mm": 10.8,
                "body_thickness_mm": 6.5,
                "splenium_thickness_mm": 11.2
            },
            "expected_classification": "Normal"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_measurements = gt_data.get('measurements', {})
    gt_length = gt_measurements.get('total_length_mm', 71.5)
    gt_genu = gt_measurements.get('genu_thickness_mm', 10.8)
    gt_body = gt_measurements.get('body_thickness_mm', 6.5)
    gt_splenium = gt_measurements.get('splenium_thickness_mm', 11.2)
    gt_classification = gt_data.get('expected_classification', 'Normal')
    
    details['ground_truth'] = {
        'total_length_mm': gt_length,
        'genu_thickness_mm': gt_genu,
        'body_thickness_mm': gt_body,
        'splenium_thickness_mm': gt_splenium,
        'expected_classification': gt_classification
    }
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    reported_values = result.get('reported_values', {})
    
    agent_length = parse_float(reported_values.get('total_length_mm'))
    agent_genu = parse_float(reported_values.get('genu_thickness_mm'))
    agent_body = parse_float(reported_values.get('body_thickness_mm'))
    agent_splenium = parse_float(reported_values.get('splenium_thickness_mm'))
    agent_classification = reported_values.get('atrophy_classification', '')
    
    # Try to get measurements from markup file if not in report
    if agent_length is None:
        temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_cc_measurements.json", temp_meas.name)
            with open(temp_meas.name, 'r') as f:
                meas_data = json.load(f)
            
            measurements = meas_data.get('measurements', [])
            for m in measurements:
                if m.get('type') == 'line':
                    name = m.get('name', '').lower()
                    length_val = m.get('length_mm', 0)
                    
                    # Try to identify measurement type from name
                    if 'length' in name or 'total' in name or 'genu' in name and 'splenium' in name:
                        if agent_length is None or length_val > 50:  # Length is typically longest
                            agent_length = length_val
                    elif 'genu' in name:
                        agent_genu = length_val
                    elif 'body' in name:
                        agent_body = length_val
                    elif 'splenium' in name:
                        agent_splenium = length_val
                    elif agent_length is None and length_val > 50:
                        # Longest measurement is probably the length
                        agent_length = length_val
                    elif agent_genu is None and 8 < length_val < 16:
                        agent_genu = length_val
                    elif agent_body is None and 4 < length_val < 12:
                        agent_body = length_val
                    elif agent_splenium is None and 8 < length_val < 16:
                        agent_splenium = length_val
        except Exception as e:
            logger.debug(f"Could not load markup file: {e}")
        finally:
            if os.path.exists(temp_meas.name):
                os.unlink(temp_meas.name)
    
    details['agent_measurements'] = {
        'total_length_mm': agent_length,
        'genu_thickness_mm': agent_genu,
        'body_thickness_mm': agent_body,
        'splenium_thickness_mm': agent_splenium,
        'atrophy_classification': agent_classification
    }
    
    # ============================================================
    # CRITERION 1: Total Length Accuracy (25 points)
    # ============================================================
    length_accurate = False
    if agent_length is not None:
        length_error = abs(agent_length - gt_length)
        details['length_error_mm'] = length_error
        
        if length_error <= length_error_max:
            score += w_length
            length_accurate = True
            feedback_parts.append(f"✓ Total length accurate: {agent_length:.1f}mm (error: {length_error:.1f}mm)")
        elif length_error <= length_error_max * 2:
            score += w_length // 2
            feedback_parts.append(f"~ Total length partially accurate: {agent_length:.1f}mm (error: {length_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Total length inaccurate: {agent_length:.1f}mm (error: {length_error:.1f}mm)")
    else:
        feedback_parts.append("✗ Total length not measured")
    
    # ============================================================
    # CRITERION 2: Genu Thickness Accuracy (15 points)
    # ============================================================
    genu_accurate = False
    if agent_genu is not None:
        genu_error = abs(agent_genu - gt_genu)
        details['genu_error_mm'] = genu_error
        
        if genu_error <= thickness_error_max:
            score += w_genu
            genu_accurate = True
            feedback_parts.append(f"✓ Genu thickness accurate: {agent_genu:.1f}mm")
        elif genu_error <= thickness_error_max * 2:
            score += w_genu // 2
            feedback_parts.append(f"~ Genu thickness partially accurate: {agent_genu:.1f}mm")
        else:
            feedback_parts.append(f"✗ Genu thickness inaccurate: {agent_genu:.1f}mm")
    else:
        feedback_parts.append("✗ Genu thickness not measured")
    
    # ============================================================
    # CRITERION 3: Body Thickness Accuracy (15 points)
    # ============================================================
    body_accurate = False
    if agent_body is not None:
        body_error = abs(agent_body - gt_body)
        details['body_error_mm'] = body_error
        
        if body_error <= thickness_error_max:
            score += w_body
            body_accurate = True
            feedback_parts.append(f"✓ Body thickness accurate: {agent_body:.1f}mm")
        elif body_error <= thickness_error_max * 2:
            score += w_body // 2
            feedback_parts.append(f"~ Body thickness partially accurate: {agent_body:.1f}mm")
        else:
            feedback_parts.append(f"✗ Body thickness inaccurate: {agent_body:.1f}mm")
    else:
        feedback_parts.append("✗ Body thickness not measured")
    
    # ============================================================
    # CRITERION 4: Splenium Thickness Accuracy (15 points)
    # ============================================================
    splenium_accurate = False
    if agent_splenium is not None:
        splenium_error = abs(agent_splenium - gt_splenium)
        details['splenium_error_mm'] = splenium_error
        
        if splenium_error <= thickness_error_max:
            score += w_splenium
            splenium_accurate = True
            feedback_parts.append(f"✓ Splenium thickness accurate: {agent_splenium:.1f}mm")
        elif splenium_error <= thickness_error_max * 2:
            score += w_splenium // 2
            feedback_parts.append(f"~ Splenium thickness partially accurate: {agent_splenium:.1f}mm")
        else:
            feedback_parts.append(f"✗ Splenium thickness inaccurate: {agent_splenium:.1f}mm")
    else:
        feedback_parts.append("✗ Splenium thickness not measured")
    
    # ============================================================
    # CRITERION 5: Mid-Sagittal Navigation (10 points)
    # ============================================================
    # Check if measurements were placed and created during task
    measurement_exists = result.get('measurement_exists', False)
    measurement_created = result.get('measurement_created_during_task', False)
    measurement_count = result.get('measurement_count', 0)
    
    if measurement_exists and measurement_created and measurement_count >= 2:
        score += w_navigation
        feedback_parts.append(f"✓ Measurements placed in Slicer ({measurement_count} measurements)")
    elif measurement_exists and measurement_count >= 1:
        score += w_navigation // 2
        feedback_parts.append(f"~ Some measurements placed ({measurement_count})")
    else:
        feedback_parts.append("✗ No measurements detected in Slicer")
    
    # ============================================================
    # CRITERION 6: Atrophy Classification (10 points)
    # ============================================================
    if agent_classification:
        agent_class_normalized = agent_classification.lower().strip()
        gt_class_normalized = gt_classification.lower().strip()
        
        # Map variations
        class_mapping = {
            'normal': 'normal',
            'mild': 'mild',
            'mild atrophy': 'mild',
            'moderate': 'moderate-severe',
            'severe': 'moderate-severe',
            'moderate-severe': 'moderate-severe',
            'moderate-severe atrophy': 'moderate-severe'
        }
        
        agent_mapped = class_mapping.get(agent_class_normalized, agent_class_normalized)
        gt_mapped = class_mapping.get(gt_class_normalized, gt_class_normalized)
        
        if agent_mapped == gt_mapped:
            score += w_classification
            feedback_parts.append(f"✓ Atrophy classification correct: {agent_classification}")
        else:
            feedback_parts.append(f"✗ Atrophy classification incorrect: {agent_classification} (expected: {gt_classification})")
    else:
        # Calculate expected classification from agent's measurements
        expected = classify_atrophy(agent_length, agent_genu, agent_body, agent_splenium)
        feedback_parts.append(f"✗ No atrophy classification provided (would be: {expected})")
    
    # ============================================================
    # CRITERION 7: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    fields_present = sum([
        agent_length is not None,
        agent_genu is not None,
        agent_body is not None,
        agent_splenium is not None,
        bool(agent_classification)
    ])
    
    if report_exists and report_created and fields_present >= 4:
        score += w_report
        feedback_parts.append(f"✓ Report complete ({fields_present}/5 fields)")
    elif report_exists and fields_present >= 2:
        score += w_report // 2
        feedback_parts.append(f"~ Report partially complete ({fields_present}/5 fields)")
    else:
        feedback_parts.append("✗ Report incomplete or missing")
    
    # ============================================================
    # VLM VERIFICATION (optional bonus/validation)
    # ============================================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            if frames or final:
                vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The task was to measure the corpus callosum (a brain structure) on a mid-sagittal MRI view.

Look for evidence that the agent:
1. Navigated to the sagittal view (Green slice panel)
2. Found the corpus callosum (bright curved structure connecting brain hemispheres)
3. Placed measurement rulers on the structure
4. May have opened Markups module or measurement tools

Respond in JSON:
{
    "sagittal_view_visible": true/false,
    "corpus_callosum_visible": true/false,
    "measurements_placed": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                images = (frames or []) + ([final] if final else [])
                vlm_result = query_vlm(prompt=vlm_prompt, images=images[:4])
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_verification'] = parsed
                    
                    if parsed.get('measurements_placed') and parsed.get('corpus_callosum_visible'):
                        feedback_parts.append("✓ VLM: Measurements visible on corpus callosum")
                    elif parsed.get('sagittal_view_visible'):
                        feedback_parts.append("~ VLM: Sagittal view accessed")
        except Exception as e:
            logger.debug(f"VLM verification skipped: {e}")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    accurate_thickness_count = sum([genu_accurate, body_accurate, splenium_accurate])
    
    # Key criteria: at least 2 thickness measurements within tolerance
    key_criteria_met = accurate_thickness_count >= 2 or (length_accurate and accurate_thickness_count >= 1)
    
    passed = score >= 60 and key_criteria_met
    
    details['score_breakdown'] = {
        'total_length': w_length if length_accurate else 0,
        'genu_thickness': w_genu if genu_accurate else 0,
        'body_thickness': w_body if body_accurate else 0,
        'splenium_thickness': w_splenium if splenium_accurate else 0,
        'accurate_thickness_count': accurate_thickness_count
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }