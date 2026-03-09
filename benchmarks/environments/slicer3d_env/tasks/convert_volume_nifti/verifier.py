#!/usr/bin/env python3
"""
Verifier for convert_volume_nifti task.

VERIFICATION CRITERIA:
1. Source volume loaded (15 points) - Slicer was used and source existed
2. Output file exists (20 points) - NIfTI file created at expected path
3. Valid NIfTI format (15 points) - File can be parsed as valid NIfTI
4. Matching dimensions (20 points) - Image dimensions match source
5. Matching spacing (15 points) - Voxel spacing preserved within tolerance
6. Valid content (15 points) - Mean intensity > 0, file size reasonable

ANTI-GAMING CHECKS:
- File must be created DURING the task (timestamp check)
- File must be valid NIfTI (not renamed NRRD)
- Dimensions/spacing must match (not random data)

Pass threshold: 70 points with output_exists and valid_nifti
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_convert_volume_nifti(traj, env_info, task_info):
    """
    Verify that the NRRD to NIfTI conversion was performed correctly.
    
    Uses multi-criteria scoring with anti-gaming timestamp checks.
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
    expected_output = metadata.get('expected_output_path', 
                                   '/home/ga/Documents/SlicerData/Exports/MRHead_converted.nii.gz')
    min_file_size = metadata.get('min_file_size_bytes', 1000000)
    max_file_size = metadata.get('max_file_size_bytes', 15000000)
    expected_dims = metadata.get('expected_dimensions', [256, 256, 130])
    dim_tolerance = metadata.get('dimension_tolerance', 10)
    spacing_tolerance_pct = metadata.get('spacing_tolerance_percent', 1.0)
    
    weights = metadata.get('scoring_weights', {})
    w_source_loaded = weights.get('source_loaded', 15)
    w_output_exists = weights.get('output_exists', 20)
    w_valid_nifti = weights.get('valid_nifti_format', 15)
    w_dimensions = weights.get('matching_dimensions', 20)
    w_spacing = weights.get('matching_spacing', 15)
    w_content = weights.get('valid_content', 15)

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

    # ============================================================
    # CRITERION 1: Source was loaded / Slicer was used (15 points)
    # ============================================================
    slicer_running = result.get('slicer_was_running', False)
    source_exists = result.get('source_file_exists', False)
    
    if slicer_running and source_exists:
        score += w_source_loaded
        feedback_parts.append("Source file available")
        details['source_loaded'] = True
    elif source_exists:
        score += w_source_loaded // 2
        feedback_parts.append("Source exists (Slicer status unknown)")
        details['source_loaded'] = 'partial'
    else:
        feedback_parts.append("Source file not found")
        details['source_loaded'] = False

    # ============================================================
    # CRITERION 2: Output file exists (20 points)
    # ============================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists:
        if file_created_during_task:
            score += w_output_exists
            feedback_parts.append(f"Output created ({output_size/1024:.1f}KB)")
            details['output_created'] = True
        else:
            # File existed before task - partial credit but suspicious
            score += w_output_exists // 3
            feedback_parts.append("Output exists but not created during task")
            details['output_created'] = 'pre-existing'
    else:
        feedback_parts.append("Output file NOT found")
        details['output_created'] = False
        # Can't verify anything else without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ============================================================
    # CRITERION 3: Valid NIfTI format (15 points)
    # ============================================================
    valid_nifti = result.get('valid_nifti', False)
    affine_valid = result.get('nifti_affine_valid', False)
    
    if valid_nifti:
        if affine_valid:
            score += w_valid_nifti
            feedback_parts.append("Valid NIfTI with proper affine")
            details['valid_format'] = True
        else:
            score += w_valid_nifti * 2 // 3
            feedback_parts.append("Valid NIfTI (affine may be default)")
            details['valid_format'] = 'partial'
    else:
        feedback_parts.append("Invalid NIfTI format")
        details['valid_format'] = False

    # ============================================================
    # CRITERION 4: Matching dimensions (20 points)
    # ============================================================
    nifti_dims = result.get('nifti_dimensions')
    source_dims = result.get('source_dimensions')
    dimensions_match = result.get('dimensions_match', False)
    
    details['nifti_dimensions'] = nifti_dims
    details['source_dimensions'] = source_dims
    
    if dimensions_match:
        score += w_dimensions
        feedback_parts.append(f"Dimensions match: {nifti_dims}")
        details['dimensions_match'] = True
    elif nifti_dims and source_dims:
        # Check manually with tolerance
        try:
            if len(nifti_dims) == len(source_dims):
                all_close = all(abs(n - s) <= dim_tolerance 
                               for n, s in zip(nifti_dims, source_dims))
                if all_close:
                    score += w_dimensions
                    feedback_parts.append(f"Dimensions match (within tolerance): {nifti_dims}")
                    details['dimensions_match'] = True
                else:
                    # Partial match - at least something was converted
                    score += w_dimensions // 3
                    feedback_parts.append(f"Dimensions differ: {nifti_dims} vs {source_dims}")
                    details['dimensions_match'] = False
            else:
                feedback_parts.append(f"Dimension count mismatch")
                details['dimensions_match'] = False
        except (TypeError, ValueError):
            feedback_parts.append("Could not compare dimensions")
            details['dimensions_match'] = 'error'
    elif nifti_dims:
        # Have output dims but not source - check against expected
        try:
            if len(nifti_dims) == len(expected_dims):
                all_close = all(abs(n - e) <= dim_tolerance * 2 
                               for n, e in zip(nifti_dims, expected_dims))
                if all_close:
                    score += w_dimensions * 2 // 3
                    feedback_parts.append(f"Dimensions plausible: {nifti_dims}")
                    details['dimensions_match'] = 'plausible'
        except (TypeError, ValueError):
            pass
    else:
        feedback_parts.append("Could not read dimensions")
        details['dimensions_match'] = 'unknown'

    # ============================================================
    # CRITERION 5: Matching spacing (15 points)
    # ============================================================
    nifti_spacing = result.get('nifti_spacing')
    source_spacing = result.get('source_spacing')
    spacing_match = result.get('spacing_match', False)
    
    details['nifti_spacing'] = nifti_spacing
    details['source_spacing'] = source_spacing
    
    if spacing_match:
        score += w_spacing
        feedback_parts.append(f"Spacing preserved: {nifti_spacing}")
        details['spacing_match'] = True
    elif nifti_spacing and source_spacing:
        # Check manually with tolerance
        try:
            if len(nifti_spacing) == len(source_spacing):
                tolerance = spacing_tolerance_pct / 100.0
                all_close = all(abs(n - s) / max(s, 0.001) <= tolerance 
                               for n, s in zip(nifti_spacing, source_spacing))
                if all_close:
                    score += w_spacing
                    feedback_parts.append(f"Spacing preserved (within tolerance)")
                    details['spacing_match'] = True
                else:
                    score += w_spacing // 3
                    feedback_parts.append(f"Spacing differs slightly")
                    details['spacing_match'] = 'partial'
        except (TypeError, ValueError, ZeroDivisionError):
            feedback_parts.append("Could not compare spacing")
            details['spacing_match'] = 'error'
    elif nifti_spacing:
        # Have spacing but no source reference - check if reasonable
        try:
            # MRI spacing typically 0.5-3mm
            reasonable = all(0.3 <= s <= 5.0 for s in nifti_spacing)
            if reasonable:
                score += w_spacing // 2
                feedback_parts.append(f"Spacing plausible: {nifti_spacing}")
                details['spacing_match'] = 'plausible'
        except (TypeError, ValueError):
            pass
    else:
        feedback_parts.append("Could not read spacing")
        details['spacing_match'] = 'unknown'

    # ============================================================
    # CRITERION 6: Valid content (15 points)
    # ============================================================
    mean_intensity = result.get('nifti_mean_intensity', 0)
    
    # Check file size is reasonable
    size_ok = min_file_size <= output_size <= max_file_size
    
    # Check mean intensity is positive (actual data, not zeros)
    intensity_ok = mean_intensity is not None and mean_intensity > 0
    
    if size_ok and intensity_ok:
        score += w_content
        feedback_parts.append(f"Content valid (mean={mean_intensity:.1f})")
        details['content_valid'] = True
    elif intensity_ok:
        score += w_content * 2 // 3
        feedback_parts.append(f"Content has data (size={output_size/1024:.0f}KB)")
        details['content_valid'] = 'partial'
    elif size_ok:
        score += w_content // 3
        feedback_parts.append("File size OK but intensity unclear")
        details['content_valid'] = 'size_only'
    else:
        feedback_parts.append(f"Content may be invalid (size={output_size})")
        details['content_valid'] = False

    # ============================================================
    # FINAL SCORING
    # ============================================================
    max_score = (w_source_loaded + w_output_exists + w_valid_nifti + 
                 w_dimensions + w_spacing + w_content)
    
    # Key criteria for passing
    key_criteria_met = (
        output_exists and 
        file_created_during_task and 
        valid_nifti
    )
    
    # Pass if score >= 70 AND key criteria met
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }