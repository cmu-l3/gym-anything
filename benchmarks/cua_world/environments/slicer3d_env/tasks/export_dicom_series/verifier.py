#!/usr/bin/env python3
"""
Verifier for Export Volume to DICOM Series task.

MULTI-CRITERIA SCORING:
1. Export Directory Has Files (15 pts) - At least 1 file exists in export directory
2. Sufficient File Count (20 pts) - At least 50 DICOM files present
3. Files Are Valid DICOM (20 pts) - Files successfully parse with pydicom
4. Slice Count Matches (10 pts) - Number of files within expected range
5. Patient Name Correct (15 pts) - DICOM PatientName contains "SlicerExportTest"
6. Study Description Present (10 pts) - StudyDescription contains expected text
7. Files Created Recently (10 pts) - File timestamps within task window

Pass threshold: 55 points with key criteria (files exist + valid DICOM + patient name)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_dicom_series(traj, env_info, task_info):
    """
    Verify that DICOM export was completed successfully.
    
    Uses multiple independent signals to prevent gaming:
    - File existence and count
    - DICOM format validation
    - Metadata verification
    - Timestamp checking (anti-gaming)
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
    expected_patient_name = metadata.get('expected_patient_name', 'SlicerExportTest')
    expected_study_desc = metadata.get('expected_study_description', 'Brain MRI Export')
    min_slice_count = metadata.get('expected_slice_count_min', 50)
    max_slice_count = metadata.get('expected_slice_count_max', 200)
    min_file_size = metadata.get('min_file_size_bytes', 1000000)
    
    weights = metadata.get('scoring_weights', {})
    w_dir_has_files = weights.get('export_dir_has_files', 15)
    w_sufficient_count = weights.get('sufficient_file_count', 20)
    w_valid_dicom = weights.get('files_valid_dicom', 20)
    w_slice_count = weights.get('slice_count_matches', 10)
    w_patient_name = weights.get('patient_name_correct', 15)
    w_study_desc = weights.get('study_description_present', 10)
    w_recent_files = weights.get('files_created_recently', 10)

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
    # Check if Slicer was running
    # ================================================================
    slicer_running = result.get('slicer_was_running', False)
    if not slicer_running:
        feedback_parts.append("WARNING: Slicer not running at end")
    
    # ================================================================
    # CRITERION 1: Export Directory Has Files (15 pts)
    # ================================================================
    dicom_count = result.get('dicom_file_count', 0)
    export_dir_exists = result.get('export_dir_exists', False)
    
    if dicom_count > 0:
        score += w_dir_has_files
        feedback_parts.append(f"Export dir has {dicom_count} files")
        details['has_files'] = True
    elif export_dir_exists:
        feedback_parts.append("Export directory exists but empty")
        details['has_files'] = False
    else:
        feedback_parts.append("Export directory not found")
        details['has_files'] = False
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Sufficient File Count (20 pts)
    # MRHead has ~130 slices, so we expect roughly that many files
    # ================================================================
    if dicom_count >= min_slice_count:
        score += w_sufficient_count
        feedback_parts.append(f"File count OK ({dicom_count} >= {min_slice_count})")
        details['sufficient_count'] = True
    elif dicom_count >= min_slice_count // 2:
        # Partial credit for fewer files
        partial = int(w_sufficient_count * (dicom_count / min_slice_count))
        score += partial
        feedback_parts.append(f"Partial file count ({dicom_count}, expected {min_slice_count}+)")
        details['sufficient_count'] = False
    else:
        feedback_parts.append(f"Low file count ({dicom_count} < {min_slice_count})")
        details['sufficient_count'] = False

    # ================================================================
    # CRITERION 3: Files Are Valid DICOM (20 pts)
    # ================================================================
    valid_dicom_count = result.get('valid_dicom_count', 0)
    has_pixel_data = result.get('has_pixel_data', False)
    
    if valid_dicom_count > 0 and has_pixel_data:
        score += w_valid_dicom
        feedback_parts.append(f"Valid DICOM with pixel data ({valid_dicom_count} files)")
        details['valid_dicom'] = True
    elif valid_dicom_count > 0:
        score += int(w_valid_dicom * 0.7)
        feedback_parts.append(f"Valid DICOM ({valid_dicom_count} files, no pixel data confirmed)")
        details['valid_dicom'] = True
    else:
        feedback_parts.append("Files are not valid DICOM format")
        details['valid_dicom'] = False

    # ================================================================
    # CRITERION 4: Slice Count Matches Expected Range (10 pts)
    # ================================================================
    if min_slice_count <= dicom_count <= max_slice_count:
        score += w_slice_count
        feedback_parts.append(f"Slice count in range ({dicom_count})")
        details['slice_count_ok'] = True
    elif dicom_count > max_slice_count:
        # Too many files - might still be valid
        score += int(w_slice_count * 0.5)
        feedback_parts.append(f"More files than expected ({dicom_count} > {max_slice_count})")
        details['slice_count_ok'] = False
    else:
        feedback_parts.append(f"Fewer files than expected ({dicom_count})")
        details['slice_count_ok'] = False

    # ================================================================
    # CRITERION 5: Patient Name Correct (15 pts)
    # ================================================================
    patient_name = result.get('patient_name', '')
    patient_name_matches = result.get('patient_name_matches', False)
    
    if patient_name_matches:
        score += w_patient_name
        feedback_parts.append(f"Patient name correct: {patient_name}")
        details['patient_name_ok'] = True
    elif patient_name and expected_patient_name.lower() in patient_name.lower():
        score += w_patient_name
        feedback_parts.append(f"Patient name matches: {patient_name}")
        details['patient_name_ok'] = True
    elif patient_name:
        # Partial credit if some patient name was set
        score += int(w_patient_name * 0.3)
        feedback_parts.append(f"Patient name set but incorrect: {patient_name}")
        details['patient_name_ok'] = False
    else:
        feedback_parts.append("No patient name in DICOM headers")
        details['patient_name_ok'] = False

    # ================================================================
    # CRITERION 6: Study Description Present (10 pts)
    # ================================================================
    study_description = result.get('study_description', '')
    study_desc_matches = result.get('study_description_matches', False)
    
    if study_desc_matches:
        score += w_study_desc
        feedback_parts.append(f"Study description OK: {study_description}")
        details['study_desc_ok'] = True
    elif study_description:
        # Check for partial match
        if any(term in study_description.lower() for term in ['brain', 'mri', 'export', 'task']):
            score += w_study_desc
            feedback_parts.append(f"Study description acceptable: {study_description}")
            details['study_desc_ok'] = True
        else:
            score += int(w_study_desc * 0.5)
            feedback_parts.append(f"Study description set: {study_description}")
            details['study_desc_ok'] = False
    else:
        feedback_parts.append("No study description set")
        details['study_desc_ok'] = False

    # ================================================================
    # CRITERION 7: Files Created Recently (10 pts) - Anti-gaming
    # ================================================================
    files_created_during_task = result.get('files_created_during_task', False)
    task_start = result.get('task_start_time', 0)
    newest_file_time = result.get('newest_file_timestamp', 0)
    new_files_count = result.get('new_files_count', 0)
    
    if files_created_during_task and new_files_count > 0:
        score += w_recent_files
        feedback_parts.append(f"Files created during task ({new_files_count} new)")
        details['recent_files'] = True
    elif newest_file_time > task_start:
        score += int(w_recent_files * 0.7)
        feedback_parts.append("Files modified during task window")
        details['recent_files'] = True
    else:
        feedback_parts.append("Files may have existed before task")
        details['recent_files'] = False

    # ================================================================
    # Calculate final result
    # ================================================================
    max_score = 100
    
    # Key criteria for pass: files exist AND valid DICOM AND (patient name or study desc)
    key_criteria_met = (
        details.get('has_files', False) and
        details.get('valid_dicom', False) and
        (details.get('patient_name_ok', False) or details.get('study_desc_ok', False))
    )
    
    # Pass threshold: 55 points with key criteria
    passed = score >= 55 and key_criteria_met
    
    # Compile feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        feedback = f"PASSED ({score}/100): " + feedback
    else:
        reasons = []
        if not details.get('has_files', False):
            reasons.append("no files exported")
        if not details.get('valid_dicom', False):
            reasons.append("invalid DICOM format")
        if not details.get('patient_name_ok', False) and not details.get('study_desc_ok', False):
            reasons.append("missing required metadata")
        if score < 55:
            reasons.append(f"score {score} < 55")
        feedback = f"FAILED ({score}/100, reasons: {', '.join(reasons)}): " + feedback

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            **details,
            "dicom_count": dicom_count,
            "valid_dicom_count": valid_dicom_count,
            "patient_name": patient_name,
            "study_description": study_description,
            "total_size_bytes": result.get('total_size_bytes', 0),
            "slicer_running": slicer_running
        }
    }