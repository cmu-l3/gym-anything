#!/usr/bin/env python3
"""
Verifier for DICOM Import and Metadata Verification task.

VERIFICATION STRATEGY:
1. Check if DICOM data was imported (volume exists in scene)
2. Verify agent's extracted metadata against ground truth DICOM headers
3. Check report format and completeness
4. Verify screenshot evidence
5. Anti-gaming: Check file timestamps and trajectory

SCORING (100 points):
- DICOM import success: 15 points (volume loaded)
- Patient ID correct: 10 points
- Modality correct: 5 points
- Slice thickness accurate: 15 points (within 0.1mm)
- Pixel spacing accurate: 15 points (within 0.1mm)
- Dimensions correct: 10 points (rows, cols, slices)
- Manufacturer extracted: 5 points
- Report format valid: 10 points
- Screenshot created: 10 points
- Study date correct: 5 points

Pass threshold: 60 points with DICOM import achieved
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
    """Convert various types to Python native types for JSON serialization."""
    if hasattr(val, 'item'):  # numpy scalar
        return val.item()
    elif hasattr(val, 'tolist'):  # numpy array
        return val.tolist()
    elif isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def parse_float_safe(val, default=0.0):
    """Safely parse a float from various input types."""
    if val is None or val == '':
        return default
    try:
        if isinstance(val, (int, float)):
            return float(val)
        if isinstance(val, str):
            # Remove any units or extra characters
            val = re.sub(r'[^\d.\-]', '', val.strip())
            return float(val) if val else default
    except (ValueError, TypeError):
        pass
    return default


def parse_int_safe(val, default=0):
    """Safely parse an int from various input types."""
    if val is None or val == '':
        return default
    try:
        if isinstance(val, (int, float)):
            return int(val)
        if isinstance(val, str):
            val = re.sub(r'[^\d\-]', '', val.strip())
            return int(val) if val else default
    except (ValueError, TypeError):
        pass
    return default


def verify_dicom_metadata(traj, env_info, task_info):
    """
    Verify DICOM metadata extraction task completion.
    
    Uses copy_from_env to read exported results from the container.
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
    
    slice_tol = thresholds.get('slice_thickness_tolerance_mm', 0.1)
    pixel_tol = thresholds.get('pixel_spacing_tolerance_mm', 0.1)
    min_screenshot_kb = thresholds.get('min_screenshot_size_kb', 100)
    
    w_import = weights.get('dicom_import_success', 15)
    w_patient_id = weights.get('patient_id_correct', 10)
    w_modality = weights.get('modality_correct', 5)
    w_slice = weights.get('slice_thickness_accurate', 15)
    w_pixel = weights.get('pixel_spacing_accurate', 15)
    w_dims = weights.get('dimensions_correct', 10)
    w_manufacturer = weights.get('manufacturer_extracted', 5)
    w_report = weights.get('report_format_valid', 10)
    w_screenshot = weights.get('screenshot_created', 10)
    w_date = weights.get('study_date_correct', 5)
    
    # Load task result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/dicom_task_result.json", temp_result.name)
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
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/dicom_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    if not gt_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Ground truth metadata not available - setup may have failed"
        }
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # CRITERION 1: DICOM Import Success (15 points)
    # ================================================================
    data_loaded = result.get('data_loaded', False)
    volume_count = result.get('volume_count', 0)
    
    if data_loaded and volume_count > 0:
        score += w_import
        feedback_parts.append(f"✅ DICOM imported ({volume_count} volume(s))")
        details['dicom_import'] = True
    else:
        feedback_parts.append("❌ DICOM not imported (no volumes loaded)")
        details['dicom_import'] = False
    
    # ================================================================
    # CRITERION 2: Patient ID Correct (10 points)
    # ================================================================
    agent_values = result.get('agent_values', {})
    gt_patient_id = gt_data.get('patient_id', '')
    agent_patient_id = agent_values.get('patient_id', '')
    
    if agent_patient_id and agent_patient_id.strip().upper() == gt_patient_id.strip().upper():
        score += w_patient_id
        feedback_parts.append(f"✅ Patient ID correct: {agent_patient_id}")
        details['patient_id_correct'] = True
    elif agent_patient_id:
        feedback_parts.append(f"❌ Patient ID mismatch: got '{agent_patient_id}', expected '{gt_patient_id}'")
        details['patient_id_correct'] = False
    else:
        feedback_parts.append("❌ Patient ID not reported")
        details['patient_id_correct'] = False
    
    # ================================================================
    # CRITERION 3: Modality Correct (5 points)
    # ================================================================
    gt_modality = gt_data.get('modality', 'CT')
    agent_modality = agent_values.get('modality', '')
    
    if agent_modality and agent_modality.strip().upper() == gt_modality.strip().upper():
        score += w_modality
        feedback_parts.append(f"✅ Modality correct: {agent_modality}")
        details['modality_correct'] = True
    elif agent_modality:
        feedback_parts.append(f"❌ Modality mismatch: got '{agent_modality}', expected '{gt_modality}'")
        details['modality_correct'] = False
    else:
        feedback_parts.append("❌ Modality not reported")
        details['modality_correct'] = False
    
    # ================================================================
    # CRITERION 4: Slice Thickness Accurate (15 points)
    # ================================================================
    gt_slice_thickness = parse_float_safe(gt_data.get('slice_thickness_mm', 0))
    agent_slice_thickness = parse_float_safe(agent_values.get('slice_thickness_mm', ''))
    
    if gt_slice_thickness > 0 and agent_slice_thickness > 0:
        slice_error = abs(gt_slice_thickness - agent_slice_thickness)
        if slice_error <= slice_tol:
            score += w_slice
            feedback_parts.append(f"✅ Slice thickness correct: {agent_slice_thickness:.2f}mm (error: {slice_error:.3f}mm)")
            details['slice_thickness_correct'] = True
        else:
            # Partial credit for close values
            if slice_error <= slice_tol * 5:
                score += w_slice // 2
            feedback_parts.append(f"❌ Slice thickness inaccurate: {agent_slice_thickness:.2f}mm vs {gt_slice_thickness:.2f}mm (error: {slice_error:.2f}mm)")
            details['slice_thickness_correct'] = False
    else:
        feedback_parts.append("❌ Slice thickness not properly reported")
        details['slice_thickness_correct'] = False
    
    details['gt_slice_thickness'] = gt_slice_thickness
    details['agent_slice_thickness'] = agent_slice_thickness
    
    # ================================================================
    # CRITERION 5: Pixel Spacing Accurate (15 points)
    # ================================================================
    gt_pixel_spacing = gt_data.get('pixel_spacing_mm', [0, 0])
    if isinstance(gt_pixel_spacing, (int, float)):
        gt_pixel_spacing = [gt_pixel_spacing, gt_pixel_spacing]
    
    # Parse agent's pixel spacing (might be "x,y" string or list)
    agent_ps_raw = agent_values.get('pixel_spacing_mm', '')
    agent_pixel_spacing = [0, 0]
    
    if isinstance(agent_ps_raw, list) and len(agent_ps_raw) >= 2:
        agent_pixel_spacing = [parse_float_safe(agent_ps_raw[0]), parse_float_safe(agent_ps_raw[1])]
    elif isinstance(agent_ps_raw, str) and ',' in agent_ps_raw:
        parts = agent_ps_raw.split(',')
        if len(parts) >= 2:
            agent_pixel_spacing = [parse_float_safe(parts[0]), parse_float_safe(parts[1])]
    elif isinstance(agent_ps_raw, (int, float)):
        agent_pixel_spacing = [parse_float_safe(agent_ps_raw), parse_float_safe(agent_ps_raw)]
    
    if gt_pixel_spacing[0] > 0 and agent_pixel_spacing[0] > 0:
        pixel_error_0 = abs(gt_pixel_spacing[0] - agent_pixel_spacing[0])
        pixel_error_1 = abs(gt_pixel_spacing[1] - agent_pixel_spacing[1]) if len(gt_pixel_spacing) > 1 else 0
        max_pixel_error = max(pixel_error_0, pixel_error_1)
        
        if max_pixel_error <= pixel_tol:
            score += w_pixel
            feedback_parts.append(f"✅ Pixel spacing correct: {agent_pixel_spacing}")
            details['pixel_spacing_correct'] = True
        else:
            if max_pixel_error <= pixel_tol * 5:
                score += w_pixel // 2
            feedback_parts.append(f"❌ Pixel spacing inaccurate: {agent_pixel_spacing} vs {gt_pixel_spacing}")
            details['pixel_spacing_correct'] = False
    else:
        feedback_parts.append("❌ Pixel spacing not properly reported")
        details['pixel_spacing_correct'] = False
    
    # ================================================================
    # CRITERION 6: Dimensions Correct (10 points)
    # ================================================================
    gt_rows = parse_int_safe(gt_data.get('rows', 0))
    gt_cols = parse_int_safe(gt_data.get('columns', 0))
    gt_slices = parse_int_safe(gt_data.get('number_of_slices', 0))
    
    agent_rows = parse_int_safe(agent_values.get('rows', ''))
    agent_cols = parse_int_safe(agent_values.get('columns', ''))
    agent_slices = parse_int_safe(agent_values.get('number_of_slices', ''))
    
    dims_correct = 0
    if agent_rows == gt_rows and gt_rows > 0:
        dims_correct += 1
    if agent_cols == gt_cols and gt_cols > 0:
        dims_correct += 1
    if agent_slices > 0 and abs(agent_slices - gt_slices) <= 5:  # Allow small tolerance for slice count
        dims_correct += 1
    
    if dims_correct == 3:
        score += w_dims
        feedback_parts.append(f"✅ Dimensions correct: {agent_rows}x{agent_cols}x{agent_slices}")
        details['dimensions_correct'] = True
    elif dims_correct > 0:
        score += (w_dims * dims_correct) // 3
        feedback_parts.append(f"⚠️ Dimensions partially correct: {agent_rows}x{agent_cols}x{agent_slices} vs {gt_rows}x{gt_cols}x{gt_slices}")
        details['dimensions_correct'] = False
    else:
        feedback_parts.append("❌ Dimensions not properly reported")
        details['dimensions_correct'] = False
    
    # ================================================================
    # CRITERION 7: Manufacturer Extracted (5 points)
    # ================================================================
    gt_manufacturer = gt_data.get('manufacturer', '')
    agent_manufacturer = agent_values.get('manufacturer', '')
    
    if agent_manufacturer and len(agent_manufacturer.strip()) > 0:
        # Check if it matches (case-insensitive partial match)
        if gt_manufacturer.lower() in agent_manufacturer.lower() or agent_manufacturer.lower() in gt_manufacturer.lower():
            score += w_manufacturer
            feedback_parts.append(f"✅ Manufacturer correct: {agent_manufacturer}")
        else:
            score += w_manufacturer // 2  # Partial credit for extraction attempt
            feedback_parts.append(f"⚠️ Manufacturer extracted: {agent_manufacturer} (expected: {gt_manufacturer})")
        details['manufacturer_extracted'] = True
    else:
        feedback_parts.append("❌ Manufacturer not extracted")
        details['manufacturer_extracted'] = False
    
    # ================================================================
    # CRITERION 8: Report Format Valid (10 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    report_valid = result.get('report_valid_json', False)
    report_during_task = result.get('report_created_during_task', False)
    
    if report_exists and report_valid and report_during_task:
        score += w_report
        feedback_parts.append("✅ Report created with valid JSON format")
        details['report_valid'] = True
    elif report_exists and report_valid:
        score += w_report // 2
        feedback_parts.append("⚠️ Report exists but may be pre-existing")
        details['report_valid'] = True
    elif report_exists:
        feedback_parts.append("❌ Report exists but is not valid JSON")
        details['report_valid'] = False
    else:
        feedback_parts.append("❌ No QA report created")
        details['report_valid'] = False
    
    # ================================================================
    # CRITERION 9: Screenshot Created (10 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_kb', 0)
    screenshot_during_task = result.get('screenshot_created_during_task', False)
    
    if screenshot_exists and screenshot_size >= min_screenshot_kb and screenshot_during_task:
        score += w_screenshot
        feedback_parts.append(f"✅ Screenshot created ({screenshot_size}KB)")
        details['screenshot_created'] = True
    elif screenshot_exists and screenshot_size >= min_screenshot_kb:
        score += w_screenshot // 2
        feedback_parts.append(f"⚠️ Screenshot exists but may be pre-existing ({screenshot_size}KB)")
        details['screenshot_created'] = True
    elif screenshot_exists:
        feedback_parts.append(f"❌ Screenshot too small ({screenshot_size}KB < {min_screenshot_kb}KB)")
        details['screenshot_created'] = False
    else:
        feedback_parts.append("❌ No screenshot saved")
        details['screenshot_created'] = False
    
    # ================================================================
    # CRITERION 10: Study Date Correct (5 points)
    # ================================================================
    gt_date = gt_data.get('study_date_formatted', gt_data.get('study_date', ''))
    agent_date = agent_values.get('study_date', '')
    
    # Normalize date formats for comparison
    def normalize_date(d):
        if not d:
            return ''
        d = str(d).strip()
        # Remove separators and compare digits
        return re.sub(r'[^\d]', '', d)
    
    gt_date_norm = normalize_date(gt_date)
    agent_date_norm = normalize_date(agent_date)
    
    if agent_date_norm and gt_date_norm and agent_date_norm == gt_date_norm:
        score += w_date
        feedback_parts.append(f"✅ Study date correct: {agent_date}")
        details['study_date_correct'] = True
    elif agent_date:
        feedback_parts.append(f"❌ Study date mismatch: '{agent_date}' vs '{gt_date}'")
        details['study_date_correct'] = False
    else:
        feedback_parts.append("❌ Study date not reported")
        details['study_date_correct'] = False
    
    # ================================================================
    # VLM Verification (bonus assessment - not required for pass)
    # ================================================================
    vlm_verified = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Try to get trajectory frames for workflow verification
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The task was to import DICOM data and verify metadata.

Look for evidence that:
1. The DICOM module was opened (DICOM browser visible)
2. DICOM data was imported (files listed in browser)
3. CT scan was loaded into the viewer (medical images visible)
4. Metadata was examined (information panel or properties visible)

Respond with JSON:
{
    "dicom_module_used": true/false,
    "data_imported": true/false,
    "ct_visible": true/false,
    "workflow_complete": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                
                images_for_vlm = frames + ([final_frame] if final_frame else [])
                if images_for_vlm:
                    vlm_result = query_vlm(prompt=vlm_prompt, images=images_for_vlm[:6])
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        vlm_verified = parsed.get('workflow_complete', False)
                        details['vlm_verification'] = parsed
                        
                        if vlm_verified:
                            feedback_parts.append("✅ VLM confirmed DICOM workflow")
                        elif parsed.get('dicom_module_used') or parsed.get('ct_visible'):
                            feedback_parts.append("⚠️ VLM detected partial workflow")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # ================================================================
    # Final Assessment
    # ================================================================
    max_score = 100
    
    # Key criteria for passing
    dicom_imported = details.get('dicom_import', False)
    key_criteria_met = dicom_imported and (
        details.get('patient_id_correct', False) or 
        details.get('slice_thickness_correct', False) or 
        details.get('dimensions_correct', False)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Compile final feedback
    feedback = " | ".join(feedback_parts[:8])  # Limit feedback length
    if len(feedback_parts) > 8:
        feedback += f" | +{len(feedback_parts) - 8} more checks"
    
    # Ensure JSON-serializable
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": feedback,
        "details": details,
        "subscores": {
            "dicom_import": w_import if details.get('dicom_import') else 0,
            "patient_id": w_patient_id if details.get('patient_id_correct') else 0,
            "modality": w_modality if details.get('modality_correct') else 0,
            "slice_thickness": w_slice if details.get('slice_thickness_correct') else 0,
            "pixel_spacing": w_pixel if details.get('pixel_spacing_correct') else 0,
            "dimensions": w_dims if details.get('dimensions_correct') else 0,
            "manufacturer": w_manufacturer if details.get('manufacturer_extracted') else 0,
            "report": w_report if details.get('report_valid') else 0,
            "screenshot": w_screenshot if details.get('screenshot_created') else 0,
            "study_date": w_date if details.get('study_date_correct') else 0,
        }
    }