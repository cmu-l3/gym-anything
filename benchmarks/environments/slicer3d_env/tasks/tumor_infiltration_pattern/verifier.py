#!/usr/bin/env python3
"""
Verifier for tumor infiltration pattern assessment task.

VERIFICATION METRICS:
1. Infiltration Index Accuracy - agent's FLAIR/T1ce ratio vs ground truth (20 pts)
2. Max Infiltration Radius - measured distance vs computed ground truth (20 pts)
3. Border Characterization - sharp/intermediate/infiltrative classification (15 pts)
4. Infiltration Grade - grade I-IV assignment (15 pts)
5. Structure Identification - identification of infiltrated structures (10 pts)
6. Markups Created - at least 3 ruler measurements exist (10 pts)
7. Report Completeness - all required fields present (10 pts)

Pass threshold: 60 points with infiltration index accuracy achieved
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


def verify_tumor_infiltration_pattern(traj, env_info, task_info):
    """
    Verify tumor infiltration pattern assessment task completion.

    Scoring (100 points total):
    - Infiltration index accuracy: 20 points (within 30% of ground truth)
    - Max infiltration radius: 20 points (within 5mm)
    - Border characterization: 15 points (correct classification)
    - Infiltration grade: 15 points (within 1 of expected)
    - Structure identification: 10 points (>=50% structures identified)
    - Markups created: 10 points (>=3 measurements)
    - Report completeness: 10 points (all required fields)
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

    index_error_max_pct = thresholds.get('infiltration_index_error_percent', 30)
    radius_error_max_mm = thresholds.get('infiltration_radius_error_mm', 5.0)
    grade_tolerance = thresholds.get('grade_tolerance', 1)

    w_index = weights.get('infiltration_index_accuracy', 20)
    w_radius = weights.get('max_infiltration_radius', 20)
    w_border = weights.get('border_characterization', 15)
    w_grade = weights.get('infiltration_grade', 15)
    w_structures = weights.get('structure_identification', 10)
    w_markups = weights.get('markups_created', 10)
    w_report = weights.get('report_completeness', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/infiltration_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/infiltration_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_index = gt_data.get('infiltration_index', 0)
    gt_radius = gt_data.get('max_infiltration_radius_mm', 0)
    gt_border = gt_data.get('border_characterization', '')
    gt_grade = gt_data.get('expected_infiltration_grade', 0)
    gt_structures = set(gt_data.get('infiltrated_structures', []))

    details['gt_infiltration_index'] = gt_index
    details['gt_max_radius_mm'] = gt_radius
    details['gt_border'] = gt_border
    details['gt_grade'] = gt_grade
    details['gt_structures'] = list(gt_structures)

    # ============================================================
    # CRITERION 1: INFILTRATION INDEX ACCURACY (20 points)
    # ============================================================
    agent_index = 0.0
    reported_index_str = result.get('reported_infiltration_index', '')
    
    if reported_index_str:
        try:
            agent_index = float(reported_index_str)
        except (ValueError, TypeError):
            pass

    details['agent_infiltration_index'] = agent_index
    index_accurate = False

    if agent_index > 0 and gt_index > 0:
        index_error_pct = abs(agent_index - gt_index) / gt_index * 100
        details['index_error_percent'] = round(index_error_pct, 1)
        
        if index_error_pct <= index_error_max_pct:
            score += w_index
            index_accurate = True
            feedback_parts.append(f"Infiltration index accurate ({agent_index:.2f} vs {gt_index:.2f}, {index_error_pct:.1f}% error)")
        elif index_error_pct <= index_error_max_pct * 1.5:
            score += int(w_index * 0.5)
            feedback_parts.append(f"Infiltration index partially accurate ({agent_index:.2f} vs {gt_index:.2f}, {index_error_pct:.1f}% error)")
        else:
            feedback_parts.append(f"Infiltration index inaccurate ({agent_index:.2f} vs {gt_index:.2f}, {index_error_pct:.1f}% error)")
    elif agent_index >= 1.0:
        # Index reported but no ground truth to compare
        score += int(w_index * 0.3)
        feedback_parts.append(f"Infiltration index reported ({agent_index:.2f}) but couldn't verify")
    else:
        feedback_parts.append("Infiltration index not reported or invalid (must be >= 1.0)")

    # ============================================================
    # CRITERION 2: MAX INFILTRATION RADIUS (20 points)
    # ============================================================
    agent_radius = 0.0
    
    # Try from report first
    reported_radius_str = result.get('reported_max_radius_mm', '')
    if reported_radius_str:
        try:
            agent_radius = float(reported_radius_str)
        except (ValueError, TypeError):
            pass
    
    # Also check from markups
    max_measurement_str = result.get('max_measurement_mm', '')
    if max_measurement_str:
        try:
            markup_max = float(max_measurement_str)
            if markup_max > agent_radius:
                agent_radius = markup_max
        except (ValueError, TypeError):
            pass

    details['agent_max_radius_mm'] = agent_radius
    radius_accurate = False

    if agent_radius > 0 and gt_radius > 0:
        radius_error = abs(agent_radius - gt_radius)
        details['radius_error_mm'] = round(radius_error, 1)
        
        if radius_error <= radius_error_max_mm:
            score += w_radius
            radius_accurate = True
            feedback_parts.append(f"Max radius accurate ({agent_radius:.1f}mm vs {gt_radius:.1f}mm, {radius_error:.1f}mm error)")
        elif radius_error <= radius_error_max_mm * 2:
            score += int(w_radius * 0.5)
            feedback_parts.append(f"Max radius partially accurate ({agent_radius:.1f}mm vs {gt_radius:.1f}mm, {radius_error:.1f}mm error)")
        else:
            feedback_parts.append(f"Max radius inaccurate ({agent_radius:.1f}mm vs {gt_radius:.1f}mm, {radius_error:.1f}mm error)")
    elif agent_radius > 0:
        score += int(w_radius * 0.3)
        feedback_parts.append(f"Max radius reported ({agent_radius:.1f}mm) but couldn't verify")
    else:
        feedback_parts.append("Max infiltration radius not measured")

    # ============================================================
    # CRITERION 3: BORDER CHARACTERIZATION (15 points)
    # ============================================================
    agent_border = result.get('reported_border', '').lower().strip()
    details['agent_border'] = agent_border

    valid_borders = ['sharp', 'intermediate', 'infiltrative']
    
    if agent_border in valid_borders:
        if agent_border == gt_border.lower():
            score += w_border
            feedback_parts.append(f"Border characterization correct: {agent_border}")
        elif (agent_border in ['sharp', 'intermediate'] and gt_border.lower() in ['sharp', 'intermediate']) or \
             (agent_border in ['intermediate', 'infiltrative'] and gt_border.lower() in ['intermediate', 'infiltrative']):
            # Adjacent categories - partial credit
            score += int(w_border * 0.6)
            feedback_parts.append(f"Border characterization close ({agent_border} vs {gt_border})")
        else:
            feedback_parts.append(f"Border characterization incorrect ({agent_border} vs {gt_border})")
    else:
        feedback_parts.append(f"Border characterization missing or invalid (got: '{agent_border}')")

    # ============================================================
    # CRITERION 4: INFILTRATION GRADE (15 points)
    # ============================================================
    agent_grade = 0
    reported_grade_str = result.get('reported_grade', '')
    
    if reported_grade_str:
        try:
            agent_grade = int(reported_grade_str)
        except (ValueError, TypeError):
            pass

    details['agent_grade'] = agent_grade

    if 1 <= agent_grade <= 4:
        grade_diff = abs(agent_grade - gt_grade)
        
        if grade_diff == 0:
            score += w_grade
            feedback_parts.append(f"Infiltration grade correct: Grade {agent_grade}")
        elif grade_diff <= grade_tolerance:
            score += int(w_grade * 0.7)
            feedback_parts.append(f"Infiltration grade close (Grade {agent_grade} vs Grade {gt_grade})")
        else:
            feedback_parts.append(f"Infiltration grade incorrect (Grade {agent_grade} vs Grade {gt_grade})")
    else:
        feedback_parts.append("Infiltration grade not reported or invalid (must be 1-4)")

    # ============================================================
    # CRITERION 5: STRUCTURE IDENTIFICATION (10 points)
    # ============================================================
    agent_structures_str = result.get('reported_structures', '')
    agent_structures = set()
    
    if agent_structures_str:
        # Parse comma-separated list
        for s in agent_structures_str.split(','):
            s = s.strip().lower().replace(' ', '_')
            if s:
                agent_structures.add(s)

    details['agent_structures'] = list(agent_structures)

    if len(gt_structures) > 0 and len(agent_structures) > 0:
        # Normalize structure names for comparison
        gt_normalized = {s.lower().replace(' ', '_') for s in gt_structures}
        agent_normalized = {s.lower().replace(' ', '_') for s in agent_structures}
        
        correct_structures = gt_normalized & agent_normalized
        pct_correct = len(correct_structures) / len(gt_normalized) * 100 if len(gt_normalized) > 0 else 0
        
        details['structures_correct_pct'] = round(pct_correct, 1)
        
        if pct_correct >= 50:
            score += w_structures
            feedback_parts.append(f"Structure identification good ({len(correct_structures)}/{len(gt_normalized)} correct)")
        elif pct_correct >= 25:
            score += int(w_structures * 0.5)
            feedback_parts.append(f"Structure identification partial ({len(correct_structures)}/{len(gt_normalized)} correct)")
        else:
            feedback_parts.append(f"Structure identification poor ({len(correct_structures)}/{len(gt_normalized)} correct)")
    elif len(agent_structures) > 0:
        score += int(w_structures * 0.3)
        feedback_parts.append(f"Structures identified ({len(agent_structures)}) but couldn't verify")
    else:
        feedback_parts.append("No infiltrated structures identified")

    # ============================================================
    # CRITERION 6: MARKUPS CREATED (10 points)
    # ============================================================
    markups_exists = result.get('markups_exists', False)
    markups_created_during_task = result.get('markups_created_during_task', False)
    measurement_count = result.get('measurement_count', 0)

    details['markups_exists'] = markups_exists
    details['measurement_count'] = measurement_count

    if markups_exists and measurement_count >= 3:
        if markups_created_during_task:
            score += w_markups
            feedback_parts.append(f"Markups created: {measurement_count} measurements")
        else:
            score += int(w_markups * 0.5)
            feedback_parts.append(f"Markups found but may predate task ({measurement_count} measurements)")
    elif markups_exists and measurement_count >= 1:
        score += int(w_markups * 0.5)
        feedback_parts.append(f"Fewer than 3 measurements ({measurement_count} found, need 3+)")
    else:
        feedback_parts.append("No measurement markups found")

    # ============================================================
    # CRITERION 7: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_complete = result.get('report_complete', False)
    report_created_during_task = result.get('report_created_during_task', False)

    details['report_exists'] = report_exists
    details['report_complete'] = report_complete

    if report_exists and report_complete:
        if report_created_during_task:
            score += w_report
            feedback_parts.append("Report complete with all required fields")
        else:
            score += int(w_report * 0.7)
            feedback_parts.append("Report complete but may predate task")
    elif report_exists:
        score += int(w_report * 0.4)
        feedback_parts.append("Report exists but missing required fields")
    else:
        feedback_parts.append("No report file found")

    # ============================================================
    # VLM VERIFICATION (bonus/confirmation)
    # ============================================================
    query_vlm = env_info.get('query_vlm')
    vlm_bonus = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if frames or final_screenshot:
                images = (frames or []) + ([final_screenshot] if final_screenshot else [])
                
                vlm_prompt = """You are verifying a brain tumor infiltration pattern assessment task in 3D Slicer.

The agent should have:
1. Viewed brain MRI scans (FLAIR and T1_Contrast sequences)
2. Used ruler/measurement tools to measure from tumor edge to FLAIR edge
3. Created a report about infiltration pattern

Looking at these screenshots, answer:
1. Is this 3D Slicer showing brain MRI images?
2. Are there any ruler/line measurements visible?
3. Does it appear the agent was measuring around a tumor region?

Respond in JSON:
{
    "is_slicer_brain_mri": true/false,
    "measurements_visible": true/false,
    "tumor_region_examined": true/false,
    "confidence": "low"/"medium"/"high"
}
"""
                vlm_result = query_vlm(prompt=vlm_prompt, images=images)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    if (parsed.get('is_slicer_brain_mri') and 
                        parsed.get('measurements_visible') and 
                        parsed.get('confidence') in ['medium', 'high']):
                        vlm_bonus = 5
                        feedback_parts.append("VLM confirmed measurement workflow (+5 bonus)")
                    elif parsed.get('is_slicer_brain_mri'):
                        feedback_parts.append("VLM confirmed brain MRI viewing")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)

    score = min(100, score + vlm_bonus)

    # ============================================================
    # FINAL ASSESSMENT
    # ============================================================
    # Key criteria: infiltration index must be reasonably accurate
    key_criteria_met = (index_accurate or (agent_index >= 1.0 and score >= 50))
    passed = score >= 60 and key_criteria_met

    details = to_python_type(details)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": to_python_type({
            "infiltration_index_accuracy": w_index if index_accurate else 0,
            "max_infiltration_radius": w_radius if radius_accurate else 0,
            "border_characterization": w_border if agent_border == gt_border.lower() else 0,
            "infiltration_grade": w_grade if agent_grade == gt_grade else 0,
            "structure_identification": w_structures if len(agent_structures) > 0 else 0,
            "markups_created": w_markups if measurement_count >= 3 else 0,
            "report_completeness": w_report if report_complete else 0,
            "vlm_bonus": vlm_bonus
        })
    }