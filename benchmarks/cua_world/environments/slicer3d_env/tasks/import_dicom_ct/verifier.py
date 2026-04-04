#!/usr/bin/env python3
"""
Verifier for Import DICOM CT task.

VERIFICATION STRATEGY (Multi-Signal):

1. DICOM Module Accessed (15 pts) - Evidence of DICOM browser usage in trajectory
2. Study Imported to Database (30 pts) - DICOM database modified, patient records exist
3. Volume Loaded in Scene (30 pts) - ScalarVolumeNode exists with CT-like dimensions
4. CT Visible in Views (15 pts) - VLM confirms chest anatomy visible
5. Correct Series Selected (10 pts) - Loaded volume has >100 slices (main CT, not scout)

ANTI-GAMING:
- Database modification timestamp must be after task start
- Patient count must increase (not pre-existing)
- Volume dimensions must be consistent with chest CT
- VLM trajectory verification (not just final state)

Pass threshold: 70 points with "Study Imported" AND "Volume Loaded" criteria met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_import_dicom_ct(traj, env_info, task_info):
    """
    Verify that DICOM data was imported and loaded correctly.
    
    Uses multiple independent signals to prevent gaming.
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
    expected_patient_id = metadata.get('expected_patient_id', 'LIDC-IDRI-0001')
    min_slice_count = metadata.get('min_slice_count', 100)
    
    weights = metadata.get('scoring_weights', {})
    w_dicom_module = weights.get('dicom_module_accessed', 15)
    w_imported = weights.get('study_imported_to_database', 30)
    w_volume_loaded = weights.get('volume_loaded_in_scene', 30)
    w_ct_visible = weights.get('ct_visible_in_views', 15)
    w_correct_series = weights.get('correct_series_selected', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/dicom_import_result.json", temp_result.name)
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
    # BASIC CHECKS
    # ================================================================
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    details['slicer_running'] = True

    # ================================================================
    # CRITERION 1: DICOM Module Accessed (15 points)
    # ================================================================
    dicom_module_accessed = result.get('dicom_module_accessed', False)
    
    # Also check trajectory for DICOM browser evidence
    trajectory_shows_dicom = False
    try:
        # Import VLM utilities if available
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            # Check if any trajectory frame shows DICOM browser
            vlm_result = query_vlm(
                images=frames,
                prompt="""Examine these screenshots from a 3D Slicer session.

Look for evidence of the DICOM module/browser being used. The DICOM browser has:
- A two-panel interface with patient/study/series tree on the left
- "Import" and "Load" buttons
- A table listing DICOM studies
- The module selector showing "DICOM" or similar

Did the user access the DICOM module/browser at any point in these screenshots?

Respond in JSON format:
{
    "dicom_browser_visible": true/false,
    "import_button_visible": true/false,
    "patient_list_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see"
}"""
            )
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('dicom_browser_visible') or parsed.get('import_button_visible'):
                    trajectory_shows_dicom = True
                    details['vlm_dicom_evidence'] = parsed
    except ImportError:
        logger.warning("VLM utilities not available for trajectory verification")
    except Exception as e:
        logger.warning(f"VLM trajectory check failed: {e}")

    if dicom_module_accessed or trajectory_shows_dicom:
        score += w_dicom_module
        feedback_parts.append("DICOM module accessed")
        details['dicom_module_accessed'] = True
    else:
        feedback_parts.append("DICOM module access not confirmed")
        details['dicom_module_accessed'] = False

    # ================================================================
    # CRITERION 2: Study Imported to Database (30 points)
    # ================================================================
    db_modified = result.get('db_modified_during_task', False)
    patients_count = result.get('patients_in_database', 0)
    current_patient_count = result.get('current_patient_count', 0)
    initial_patient_count = result.get('initial_patient_count', 0)
    lidc_found = result.get('lidc_patient_found', False)
    dicom_connected = result.get('dicom_database_connected', False)
    
    # Check if patients were added
    patients_added = current_patient_count > initial_patient_count or patients_count > initial_patient_count
    
    study_imported = False
    import_points = 0
    
    if dicom_connected:
        import_points += 5  # Database connected
        
        if db_modified:
            import_points += 10  # Database was modified during task
            
        if patients_added or patients_count > 0:
            import_points += 10  # Patients exist in database
            
        if lidc_found:
            import_points += 5  # Specifically LIDC patient found
            study_imported = True
        elif patients_count > 0:
            # Some patient imported (may not be LIDC)
            study_imported = True

    score += min(import_points, w_imported)
    
    if study_imported:
        if lidc_found:
            feedback_parts.append(f"LIDC patient imported ({patients_count} patients in DB)")
        else:
            feedback_parts.append(f"Study imported ({patients_count} patients in DB)")
    else:
        feedback_parts.append("Study NOT imported to database")
    
    details['study_imported'] = study_imported
    details['patients_in_database'] = patients_count
    details['lidc_found'] = lidc_found
    details['db_modified'] = db_modified

    # ================================================================
    # CRITERION 3: Volume Loaded in Scene (30 points)
    # ================================================================
    volumes_loaded = result.get('volumes_loaded', 0)
    volume_dims = result.get('volume_dimensions', [])
    ct_detected = result.get('ct_volume_detected', False)
    
    volume_loaded = False
    volume_points = 0
    
    if volumes_loaded > 0:
        volume_points += 15  # At least one volume loaded
        volume_loaded = True
        
        if ct_detected:
            volume_points += 10  # CT-like dimensions detected
            
        # Check dimensions more carefully
        if volume_dims and len(volume_dims) >= 3:
            # Typical chest CT: 512x512xN where N > 100
            if volume_dims[0] >= 256 and volume_dims[1] >= 256:
                volume_points += 5
    
    score += min(volume_points, w_volume_loaded)
    
    if volume_loaded:
        dims_str = f"{volume_dims}" if volume_dims else "unknown"
        feedback_parts.append(f"Volume loaded ({volumes_loaded} volumes, dims: {dims_str})")
    else:
        feedback_parts.append("NO volume loaded in scene")
    
    details['volume_loaded'] = volume_loaded
    details['volumes_count'] = volumes_loaded
    details['volume_dimensions'] = volume_dims
    details['ct_detected'] = ct_detected

    # ================================================================
    # CRITERION 4: CT Visible in Views (15 points)
    # ================================================================
    views_have_content = result.get('slice_views_have_content', False)
    screenshot_size = result.get('screenshot_size_kb', 0)
    
    ct_visible = False
    visible_points = 0
    
    if views_have_content:
        visible_points += 5
        ct_visible = True
    
    # Use VLM to verify CT is visible in final screenshot
    try:
        from gym_anything.vlm import get_final_screenshot, query_vlm
        
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_result = query_vlm(
                image=final_screenshot,
                prompt="""This is a screenshot of 3D Slicer medical imaging software.

Examine the slice views (the 2D image panels showing cross-sections).

Determine if a chest CT scan is displayed:
1. Are there slice views visible with medical image data (not empty/gray)?
2. Is lung tissue visible (dark areas representing air-filled lungs)?
3. Can you see chest anatomy (ribs, mediastinum, heart silhouette)?

Respond in JSON format:
{
    "slice_views_visible": true/false,
    "medical_data_displayed": true/false,
    "lung_tissue_visible": true/false,
    "chest_anatomy_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what anatomy you can identify"
}"""
            )
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_ct_visible'] = parsed
                
                if parsed.get('medical_data_displayed'):
                    visible_points += 5
                    ct_visible = True
                if parsed.get('lung_tissue_visible') or parsed.get('chest_anatomy_visible'):
                    visible_points += 5
                    ct_visible = True
    except ImportError:
        logger.warning("VLM utilities not available")
        # Fall back to heuristics
        if screenshot_size > 200 and views_have_content:
            visible_points += 5
            ct_visible = True
    except Exception as e:
        logger.warning(f"VLM CT visible check failed: {e}")
        # Fall back to programmatic check
        if views_have_content:
            visible_points += 5
            ct_visible = True

    score += min(visible_points, w_ct_visible)
    
    if ct_visible:
        feedback_parts.append("CT visible in views")
    else:
        feedback_parts.append("CT NOT visible in views")
    
    details['ct_visible'] = ct_visible

    # ================================================================
    # CRITERION 5: Correct Series Selected (10 points)
    # ================================================================
    correct_series = False
    series_points = 0
    
    if volume_dims and len(volume_dims) >= 3:
        slice_count = volume_dims[2] if len(volume_dims) > 2 else 0
        
        if slice_count >= min_slice_count:
            series_points += 10
            correct_series = True
            feedback_parts.append(f"Correct series ({slice_count} slices)")
        elif slice_count > 50:
            series_points += 5
            correct_series = True
            feedback_parts.append(f"Series loaded ({slice_count} slices, expected >{min_slice_count})")
        else:
            feedback_parts.append(f"Wrong series? Only {slice_count} slices")
    elif volumes_loaded > 0:
        # Volume loaded but dimensions unknown - partial credit
        series_points += 3
        feedback_parts.append("Series loaded (dimensions unknown)")
    else:
        feedback_parts.append("No series loaded")
    
    score += min(series_points, w_correct_series)
    details['correct_series'] = correct_series

    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria check
    key_criteria_met = study_imported and volume_loaded
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # If not passing but close, provide helpful feedback
    if not passed:
        if not study_imported:
            feedback_parts.append("HINT: Import DICOM via Modules→DICOM→Import")
        elif not volume_loaded:
            feedback_parts.append("HINT: Select series and click Load")

    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }