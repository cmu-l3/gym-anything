#!/usr/bin/env python3
"""
Verifier for Export Fiducial Landmarks to CSV task.

VERIFICATION CRITERIA:
1. CSV file exists at expected path (25 points)
2. Four landmarks present in file (25 points)
3. Valid coordinate bounds (20 points)
4. Correct CSV format with header (15 points)
5. Fiducials evidence in scene or markup files (15 points)

ANTI-GAMING CHECKS:
- CSV file must be created/modified during task (timestamp check)
- All four points must be at distinct locations (>5mm apart)
- Coordinates must be within brain volume bounds

Pass threshold: 70 points with CSV file exists and at least 3 landmarks
"""

import json
import os
import tempfile
import logging
import math
from typing import Dict, Any, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_landmarks_csv(traj, env_info, task_info):
    """
    Verify that fiducial landmarks were placed and exported to CSV.
    
    Uses multi-criteria scoring with anatomical plausibility checks.
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
    expected_path = metadata.get('output_csv_path', '/home/ga/Documents/SlicerData/Exports/landmarks.csv')
    expected_landmarks = metadata.get('expected_landmarks', ['AC', 'PC', 'CC_Superior', 'Frontal_Apex'])
    num_expected = metadata.get('num_landmarks', 4)
    coord_bounds = metadata.get('coordinate_bounds', {
        'R': {'min': -100, 'max': 100},
        'A': {'min': -150, 'max': 100},
        'S': {'min': -80, 'max': 100}
    })
    min_separation = metadata.get('min_point_separation_mm', 5.0)
    
    weights = metadata.get('scoring_weights', {})
    w_csv_exists = weights.get('csv_file_exists', 25)
    w_four_landmarks = weights.get('four_landmarks', 25)
    w_valid_coords = weights.get('valid_coordinates', 20)
    w_correct_format = weights.get('correct_format', 15)
    w_fiducials_scene = weights.get('fiducials_in_scene', 15)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/landmarks_task_result.json", temp_result.name)
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
    slicer_running = result.get('slicer_was_running', False)
    details['slicer_was_running'] = slicer_running
    
    # ============================================================
    # CRITERION 1: CSV File Exists (25 points)
    # ============================================================
    csv_exists = result.get('csv_exists', False)
    csv_created_during_task = result.get('csv_created_during_task', False)
    
    details['csv_exists'] = csv_exists
    details['csv_created_during_task'] = csv_created_during_task
    
    if csv_exists:
        if csv_created_during_task:
            score += w_csv_exists
            feedback_parts.append("CSV file created during task")
        else:
            # File existed before - reduced credit
            score += w_csv_exists * 0.3
            feedback_parts.append("CSV file exists but not created during task (pre-existing?)")
    else:
        feedback_parts.append("CSV file NOT found at expected path")
        # Check if any CSV was created elsewhere
        mrk_files = result.get('mrk_files_created', 0)
        fcsv_files = result.get('fcsv_files_created', 0)
        if mrk_files > 0 or fcsv_files > 0:
            feedback_parts.append(f"Found {mrk_files + fcsv_files} markup file(s) elsewhere")
    
    # ============================================================
    # CRITERION 2: Four Landmarks Present (25 points)
    # ============================================================
    landmark_count = result.get('csv_landmark_count', 0)
    landmarks_found = result.get('landmarks_found', [])
    
    details['landmark_count'] = landmark_count
    details['landmarks_found'] = landmarks_found
    
    if landmark_count >= num_expected:
        score += w_four_landmarks
        feedback_parts.append(f"All {num_expected} landmarks present")
    elif landmark_count >= 3:
        score += int(w_four_landmarks * 0.75)
        feedback_parts.append(f"{landmark_count}/4 landmarks found")
    elif landmark_count >= 2:
        score += int(w_four_landmarks * 0.5)
        feedback_parts.append(f"Only {landmark_count}/4 landmarks found")
    elif landmark_count >= 1:
        score += int(w_four_landmarks * 0.25)
        feedback_parts.append(f"Only {landmark_count}/4 landmarks found")
    else:
        feedback_parts.append("No landmarks found in CSV")
    
    # Check for expected landmark names (partial credit for correct naming)
    if landmarks_found:
        found_names = [lm.get('label', '').upper() for lm in landmarks_found]
        expected_upper = [name.upper() for name in expected_landmarks]
        
        matched_names = 0
        for expected_name in expected_upper:
            for found_name in found_names:
                # Partial matching (AC matches AC, Frontal matches Frontal_Apex)
                if expected_name in found_name or found_name in expected_name:
                    matched_names += 1
                    break
        
        details['matched_landmark_names'] = matched_names
        if matched_names == num_expected:
            feedback_parts.append("All landmark names correct")
        elif matched_names > 0:
            feedback_parts.append(f"{matched_names}/{num_expected} landmark names recognized")
    
    # ============================================================
    # CRITERION 3: Valid Coordinate Bounds (20 points)
    # ============================================================
    coordinates_valid = result.get('coordinates_valid', False)
    all_distinct = result.get('all_distinct', False)
    
    details['coordinates_valid'] = coordinates_valid
    details['all_distinct'] = all_distinct
    
    if coordinates_valid and all_distinct:
        score += w_valid_coords
        feedback_parts.append("Coordinates valid and distinct")
    elif coordinates_valid:
        score += int(w_valid_coords * 0.7)
        feedback_parts.append("Coordinates in valid range (but some may overlap)")
    elif landmarks_found:
        # Manual check of coordinates
        valid_count = 0
        for lm in landmarks_found:
            r = lm.get('r', 0)
            a = lm.get('a', 0)
            s = lm.get('s', 0)
            
            r_valid = coord_bounds['R']['min'] <= r <= coord_bounds['R']['max']
            a_valid = coord_bounds['A']['min'] <= a <= coord_bounds['A']['max']
            s_valid = coord_bounds['S']['min'] <= s <= coord_bounds['S']['max']
            
            if r_valid and a_valid and s_valid:
                valid_count += 1
        
        if valid_count > 0:
            score += int(w_valid_coords * (valid_count / max(len(landmarks_found), 1)))
            feedback_parts.append(f"{valid_count}/{len(landmarks_found)} coordinates in valid brain bounds")
        else:
            feedback_parts.append("Coordinates outside expected brain bounds")
    else:
        feedback_parts.append("No coordinates to validate")
    
    # ============================================================
    # CRITERION 4: Correct CSV Format (15 points)
    # ============================================================
    csv_has_header = result.get('csv_has_header', False)
    csv_line_count = result.get('csv_line_count', 0)
    
    details['csv_has_header'] = csv_has_header
    details['csv_line_count'] = csv_line_count
    
    if csv_exists:
        format_score = 0
        
        # Header present
        if csv_has_header:
            format_score += w_correct_format * 0.5
            feedback_parts.append("CSV has header row")
        
        # Correct number of lines (header + data)
        expected_lines = num_expected + (1 if csv_has_header else 0)
        if csv_line_count >= expected_lines:
            format_score += w_correct_format * 0.5
        elif csv_line_count > 0:
            format_score += w_correct_format * 0.25
        
        score += int(format_score)
    
    # ============================================================
    # CRITERION 5: Fiducials in Scene Evidence (15 points)
    # ============================================================
    fiducials_in_scene = result.get('fiducials_in_scene', 0)
    mrk_files = result.get('mrk_files_created', 0)
    fcsv_files = result.get('fcsv_files_created', 0)
    
    details['fiducials_in_scene'] = fiducials_in_scene
    details['mrk_files_created'] = mrk_files
    details['fcsv_files_created'] = fcsv_files
    
    # Evidence from markup files or scene
    if fiducials_in_scene >= num_expected:
        score += w_fiducials_scene
        feedback_parts.append(f"{fiducials_in_scene} fiducials in Slicer scene")
    elif mrk_files > 0 or fcsv_files > 0:
        score += int(w_fiducials_scene * 0.7)
        feedback_parts.append(f"Markup files found ({mrk_files} .mrk.json, {fcsv_files} .fcsv)")
    elif csv_exists and landmark_count > 0:
        # CSV with landmarks is indirect evidence
        score += int(w_fiducials_scene * 0.5)
        feedback_parts.append("Fiducials inferred from CSV content")
    else:
        feedback_parts.append("No fiducial evidence in scene")
    
    # ============================================================
    # VLM VERIFICATION (Trajectory-based)
    # ============================================================
    try:
        # Import VLM utilities if available
        vlm_result = _verify_with_vlm(traj, env_info)
        if vlm_result:
            details['vlm_verification'] = vlm_result
            
            # Bonus points for VLM confirmation
            if vlm_result.get('fiducials_visible', False):
                bonus = 5
                score += bonus
                feedback_parts.append(f"VLM confirms fiducials visible (+{bonus})")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Cap score at 100
    score = min(score, 100)
    
    # Determine pass/fail
    # Must have: CSV exists AND at least 3 landmarks
    key_criteria_met = csv_exists and landmark_count >= 3
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def _verify_with_vlm(traj, env_info) -> Dict[str, Any]:
    """
    Use VLM to verify fiducial placement from trajectory screenshots.
    
    Returns dict with verification results or None if VLM unavailable.
    """
    try:
        # Try to import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
    except ImportError:
        logger.info("VLM utilities not available, skipping visual verification")
        return None
    
    # Sample frames from trajectory
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if not frames:
            return None
    except Exception:
        return None
    
    # VLM prompt for fiducial verification
    prompt = """You are analyzing screenshots from a 3D Slicer medical imaging session.
    
The task was to place fiducial (point) markers on anatomical landmarks in a brain MRI and export them.

Looking at these trajectory screenshots (from earliest to latest), assess:

1. FIDUCIALS_VISIBLE: Are there visible fiducial markers (small colored dots/spheres) placed on the brain images?

2. MARKUPS_MODULE: Does any screenshot show the Markups module interface or fiducial list panel?

3. BRAIN_VISIBLE: Is brain MRI data clearly visible in the slice views?

4. WORKFLOW_PROGRESSION: Do the screenshots show a logical progression of placing markers?

5. EXPORT_EVIDENCE: Is there any evidence of file export (save dialog, file menu)?

Respond in JSON format:
{
    "fiducials_visible": true/false,
    "markups_module_shown": true/false,
    "brain_visible": true/false,
    "workflow_progression": true/false,
    "export_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
    
    try:
        result = query_vlm(images=frames, prompt=prompt)
        if result and result.get('success'):
            return result.get('parsed', {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
    
    return None