#!/usr/bin/env python3
"""
Verifier for Save Scene Bundle task.

VERIFICATION CRITERIA:
1. MRB file exists (15 points) - File at correct path
2. Valid archive (15 points) - MRB can be extracted as ZIP
3. Contains MRML scene (15 points) - Scene definition file present
4. Volume data bundled (20 points) - Actual volume data in archive
5. Two fiducials present (15 points) - At least 2 markup fiducial points exist
6. Correct fiducial labels (10 points) - Fiducials named "Landmark_A" and "Landmark_B"
7. Distinct coordinates (10 points) - Fiducials at different, non-zero positions

Pass threshold: 70 points with MRB exists and contains MRML scene
"""

import json
import os
import tempfile
import logging
import math
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_save_scene_bundle(traj, env_info, task_info):
    """
    Verify that a scene bundle was saved correctly with fiducials.
    
    Uses multi-criteria scoring with archive content analysis.
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
    expected_labels = metadata.get('expected_fiducial_labels', ['Landmark_A', 'Landmark_B'])
    min_mrb_size = metadata.get('min_mrb_size_bytes', 1000000)
    min_separation = metadata.get('min_fiducial_separation_mm', 5.0)
    
    weights = metadata.get('scoring_weights', {})
    w_mrb_exists = weights.get('mrb_file_exists', 15)
    w_valid_archive = weights.get('valid_archive', 15)
    w_contains_mrml = weights.get('contains_mrml_scene', 15)
    w_volume_bundled = weights.get('volume_data_bundled', 20)
    w_two_fiducials = weights.get('two_fiducials_present', 15)
    w_correct_labels = weights.get('correct_fiducial_labels', 10)
    w_distinct_coords = weights.get('distinct_coordinates', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
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
    
    # ================================================================
    # CRITERION 1: MRB File Exists (15 points)
    # ================================================================
    mrb_exists = result.get('mrb_exists', False)
    mrb_size = result.get('mrb_size_bytes', 0)
    
    details['mrb_exists'] = mrb_exists
    details['mrb_size_bytes'] = mrb_size
    
    if mrb_exists:
        score += w_mrb_exists
        feedback_parts.append(f"MRB file exists ({mrb_size/1024:.1f}KB)")
    else:
        feedback_parts.append("MRB file NOT found at expected path")
        # Early exit - nothing else to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # ANTI-GAMING CHECK: File created during task
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    details['file_created_during_task'] = file_created_during_task
    
    if not file_created_during_task:
        feedback_parts.append("WARNING: File may have existed before task")
        # Penalize but don't fail completely
        score -= 5
    
    # ================================================================
    # CRITERION 2: Valid Archive (15 points)
    # ================================================================
    is_valid_zip = result.get('is_valid_zip', False)
    details['is_valid_zip'] = is_valid_zip
    
    if is_valid_zip:
        score += w_valid_archive
        feedback_parts.append("Valid ZIP archive")
    else:
        feedback_parts.append("Invalid archive (not a ZIP)")
    
    # ================================================================
    # CRITERION 3: Contains MRML Scene (15 points)
    # ================================================================
    contains_mrml = result.get('contains_mrml', False)
    mrml_filename = result.get('mrml_filename', '')
    
    details['contains_mrml'] = contains_mrml
    details['mrml_filename'] = mrml_filename
    
    if contains_mrml:
        score += w_contains_mrml
        feedback_parts.append(f"Contains MRML scene: {mrml_filename}")
    else:
        feedback_parts.append("No MRML scene file found")
    
    # ================================================================
    # CRITERION 4: Volume Data Bundled (20 points)
    # ================================================================
    volume_bundled = result.get('volume_data_bundled', False)
    details['volume_data_bundled'] = volume_bundled
    
    # Additional check: file size indicates real data
    size_indicates_data = mrb_size >= min_mrb_size
    
    if volume_bundled:
        score += w_volume_bundled
        feedback_parts.append("Volume data bundled")
    elif size_indicates_data:
        # Give partial credit if file is large enough
        score += int(w_volume_bundled * 0.5)
        feedback_parts.append(f"Large file size ({mrb_size/1024/1024:.1f}MB) suggests data present")
    else:
        feedback_parts.append("Volume data NOT bundled (or file too small)")
    
    # ================================================================
    # CRITERION 5: Two Fiducials Present (15 points)
    # ================================================================
    num_fiducials = result.get('num_fiducials', 0)
    details['num_fiducials'] = num_fiducials
    
    if num_fiducials >= 2:
        score += w_two_fiducials
        feedback_parts.append(f"{num_fiducials} fiducial(s) present")
    elif num_fiducials == 1:
        score += int(w_two_fiducials * 0.5)
        feedback_parts.append("Only 1 fiducial found (expected 2)")
    else:
        feedback_parts.append("No fiducials found")
    
    # ================================================================
    # CRITERION 6: Correct Fiducial Labels (10 points)
    # ================================================================
    fiducial_labels = result.get('fiducial_labels', [])
    details['fiducial_labels'] = fiducial_labels
    
    # Check for expected labels (case-sensitive)
    has_landmark_a = any(label == 'Landmark_A' for label in fiducial_labels)
    has_landmark_b = any(label == 'Landmark_B' for label in fiducial_labels)
    
    # Also check case-insensitive as partial credit
    has_landmark_a_ci = any('landmark_a' in label.lower() for label in fiducial_labels)
    has_landmark_b_ci = any('landmark_b' in label.lower() for label in fiducial_labels)
    
    details['has_landmark_a'] = has_landmark_a
    details['has_landmark_b'] = has_landmark_b
    
    if has_landmark_a and has_landmark_b:
        score += w_correct_labels
        feedback_parts.append("Correct fiducial labels (Landmark_A, Landmark_B)")
    elif has_landmark_a_ci and has_landmark_b_ci:
        score += int(w_correct_labels * 0.7)
        feedback_parts.append("Fiducial labels present (case mismatch)")
    elif has_landmark_a or has_landmark_b:
        score += int(w_correct_labels * 0.5)
        feedback_parts.append("Only one expected label found")
    elif len(fiducial_labels) >= 2:
        score += int(w_correct_labels * 0.3)
        feedback_parts.append(f"Fiducials have custom names: {fiducial_labels}")
    else:
        feedback_parts.append("Fiducial labels missing or incorrect")
    
    # ================================================================
    # CRITERION 7: Distinct Coordinates (10 points)
    # ================================================================
    fiducial_coords = result.get('fiducial_coordinates', [])
    details['fiducial_coordinates'] = fiducial_coords
    
    coords_valid = False
    coords_distinct = False
    
    if len(fiducial_coords) >= 2:
        # Check that coordinates are non-zero
        non_zero_coords = []
        for coord in fiducial_coords:
            if isinstance(coord, list) and len(coord) >= 3:
                if any(abs(c) > 0.1 for c in coord[:3]):
                    non_zero_coords.append(coord)
        
        if len(non_zero_coords) >= 2:
            coords_valid = True
            
            # Calculate distance between first two non-zero coordinates
            c1, c2 = non_zero_coords[0], non_zero_coords[1]
            distance = math.sqrt(sum((a - b) ** 2 for a, b in zip(c1[:3], c2[:3])))
            details['fiducial_distance_mm'] = distance
            
            if distance >= min_separation:
                coords_distinct = True
    
    if coords_distinct:
        score += w_distinct_coords
        feedback_parts.append(f"Fiducials at distinct locations ({details.get('fiducial_distance_mm', 0):.1f}mm apart)")
    elif coords_valid:
        score += int(w_distinct_coords * 0.5)
        feedback_parts.append("Fiducials have coordinates but may be too close")
    elif num_fiducials >= 2:
        # Give partial credit if fiducials exist but coords couldn't be parsed
        score += int(w_distinct_coords * 0.3)
        feedback_parts.append("Fiducial coordinates could not be verified")
    else:
        feedback_parts.append("Fiducial coordinates missing or invalid")
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: MRB exists AND contains MRML scene
    key_criteria_met = mrb_exists and contains_mrml
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    details['key_criteria_met'] = key_criteria_met
    details['total_score'] = score
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }