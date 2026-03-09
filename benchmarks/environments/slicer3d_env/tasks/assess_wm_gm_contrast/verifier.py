#!/usr/bin/env python3
"""
Verifier for WM/GM Contrast Assessment task.

VERIFICATION CRITERIA:
1. Output file exists (15 points) - JSON file at expected path
2. Valid JSON structure (10 points) - contains required fields
3. WM > GM intensity (20 points) - physiologically correct for T1
4. Ratio in plausible range (20 points) - between 1.0 and 2.0
5. Reasonable intensity values (15 points) - not zero, not saturated
6. Markup nodes created (10 points) - fiducials placed in Slicer
7. VLM anatomical plausibility (10 points) - samples in appropriate regions

Pass threshold: 70 points with "WM > GM" criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_wm_gm_contrast(traj, env_info, task_info):
    """
    Verify WM/GM contrast assessment task completion.
    
    Uses multi-criteria scoring with physiological plausibility checks.
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
    ratio_range = metadata.get('physiological_ratio_range', {"min": 1.0, "max": 2.0})
    good_contrast = metadata.get('good_contrast_range', {"min": 1.1, "max": 1.5})
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_file_exists', 15)
    w_json_valid = weights.get('valid_json_structure', 10)
    w_wm_gt_gm = weights.get('wm_greater_than_gm', 20)
    w_ratio_range = weights.get('ratio_in_range', 20)
    w_reasonable = weights.get('reasonable_intensities', 15)
    w_markups = weights.get('markup_nodes_created', 10)
    w_vlm = weights.get('vlm_anatomically_plausible', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/wm_gm_task_result.json", temp_result.name)
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
    
    # Also try to load reference data
    temp_ref = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ref_data = {}
    try:
        copy_from_env("/tmp/wm_gm_reference.json", temp_ref.name)
        with open(temp_ref.name, 'r') as f:
            ref_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load reference data: {e}")
    finally:
        if os.path.exists(temp_ref.name):
            os.unlink(temp_ref.name)
    
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
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += w_output_exists
        feedback_parts.append("Output file created during task")
    elif output_exists:
        score += w_output_exists * 0.5
        feedback_parts.append("Output file exists (pre-existing)")
    else:
        feedback_parts.append("Output file NOT found")
    
    details['output_exists'] = output_exists
    details['file_created_during_task'] = file_created_during_task
    
    # ================================================================
    # CRITERION 2: Valid JSON structure (10 points)
    # ================================================================
    json_valid = result.get('json_valid', False)
    
    if json_valid:
        score += w_json_valid
        feedback_parts.append("Valid JSON structure")
    else:
        feedback_parts.append("Invalid or missing JSON")
    
    details['json_valid'] = json_valid
    
    # ================================================================
    # GET INTENSITY VALUES (from user report or extracted fiducials)
    # ================================================================
    wm_intensity = 0.0
    gm_intensity = 0.0
    wm_gm_ratio = 0.0
    
    # Try user's reported values first
    try:
        reported_wm = result.get('reported_wm_intensity', '')
        if reported_wm:
            wm_intensity = float(reported_wm)
    except (ValueError, TypeError):
        pass
    
    try:
        reported_gm = result.get('reported_gm_intensity', '')
        if reported_gm:
            gm_intensity = float(reported_gm)
    except (ValueError, TypeError):
        pass
    
    try:
        reported_ratio = result.get('reported_wm_gm_ratio', '')
        if reported_ratio:
            wm_gm_ratio = float(reported_ratio)
    except (ValueError, TypeError):
        pass
    
    # Fall back to extracted values from Slicer fiducials
    if wm_intensity == 0:
        try:
            extracted_wm = result.get('extracted_wm_intensity', '')
            if extracted_wm:
                wm_intensity = float(extracted_wm)
        except (ValueError, TypeError):
            pass
    
    if gm_intensity == 0:
        try:
            extracted_gm = result.get('extracted_gm_intensity', '')
            if extracted_gm:
                gm_intensity = float(extracted_gm)
        except (ValueError, TypeError):
            pass
    
    # Calculate ratio if not provided
    if wm_gm_ratio == 0 and gm_intensity > 0:
        wm_gm_ratio = wm_intensity / gm_intensity
    
    details['wm_intensity'] = wm_intensity
    details['gm_intensity'] = gm_intensity
    details['wm_gm_ratio'] = wm_gm_ratio
    
    # Get reference values for comparison
    ref_wm = 0.0
    ref_gm = 0.0
    ref_ratio = 0.0
    
    try:
        ref_wm = float(result.get('reference_wm_intensity', 0) or 0)
        ref_gm = float(result.get('reference_gm_intensity', 0) or 0)
        ref_ratio = float(result.get('reference_ratio', 0) or 0)
    except (ValueError, TypeError):
        pass
    
    details['ref_wm'] = ref_wm
    details['ref_gm'] = ref_gm
    details['ref_ratio'] = ref_ratio
    
    # ================================================================
    # CRITERION 3: WM > GM intensity (20 points) - CRITICAL
    # ================================================================
    wm_greater_than_gm = False
    
    if wm_intensity > 0 and gm_intensity > 0:
        if wm_intensity > gm_intensity:
            wm_greater_than_gm = True
            score += w_wm_gt_gm
            feedback_parts.append(f"WM ({wm_intensity:.0f}) > GM ({gm_intensity:.0f}) ✓")
        else:
            # Wrong! GM should not be brighter than WM on T1
            feedback_parts.append(f"ERROR: WM ({wm_intensity:.0f}) <= GM ({gm_intensity:.0f})")
    else:
        feedback_parts.append("Missing intensity values")
    
    details['wm_greater_than_gm'] = wm_greater_than_gm
    
    # ================================================================
    # CRITERION 4: Ratio in physiological range (20 points)
    # ================================================================
    ratio_valid = False
    ratio_min = ratio_range.get('min', 1.0)
    ratio_max = ratio_range.get('max', 2.0)
    good_min = good_contrast.get('min', 1.1)
    good_max = good_contrast.get('max', 1.5)
    
    if wm_gm_ratio > 0:
        if good_min <= wm_gm_ratio <= good_max:
            # Excellent - in the good contrast range
            ratio_valid = True
            score += w_ratio_range
            feedback_parts.append(f"Ratio {wm_gm_ratio:.2f} in good range")
        elif ratio_min <= wm_gm_ratio <= ratio_max:
            # Acceptable - physiologically plausible
            ratio_valid = True
            score += w_ratio_range * 0.7
            feedback_parts.append(f"Ratio {wm_gm_ratio:.2f} plausible")
        else:
            feedback_parts.append(f"Ratio {wm_gm_ratio:.2f} out of range")
    else:
        feedback_parts.append("No ratio calculated")
    
    details['ratio_valid'] = ratio_valid
    
    # ================================================================
    # CRITERION 5: Reasonable intensity values (15 points)
    # ================================================================
    intensities_reasonable = False
    
    if wm_intensity > 0 and gm_intensity > 0:
        # Check that values are not obviously wrong
        # MRI intensities should be positive and not extremely large
        if wm_intensity > 10 and gm_intensity > 10:
            if wm_intensity < 100000 and gm_intensity < 100000:
                intensities_reasonable = True
                score += w_reasonable
                feedback_parts.append("Intensities reasonable")
            else:
                feedback_parts.append("Intensities seem too large")
        else:
            feedback_parts.append("Intensities too small")
    
    details['intensities_reasonable'] = intensities_reasonable
    
    # ================================================================
    # CRITERION 6: Markup nodes created (10 points)
    # ================================================================
    fiducials_found = result.get('fiducials_found', 0)
    
    if fiducials_found >= 2:
        score += w_markups
        feedback_parts.append(f"{fiducials_found} fiducials placed")
    elif fiducials_found == 1:
        score += w_markups * 0.5
        feedback_parts.append("Only 1 fiducial placed")
    else:
        # Check if output file has positions (agent might have measured differently)
        if output_exists and json_valid:
            score += w_markups * 0.3
            feedback_parts.append("Measurements in file (no Slicer fiducials)")
        else:
            feedback_parts.append("No fiducials/measurements")
    
    details['fiducials_found'] = fiducials_found
    
    # ================================================================
    # CRITERION 7: VLM Anatomical Plausibility (10 points)
    # ================================================================
    # Use trajectory to verify agent actually navigated brain slices
    # and placed measurements in appropriate regions
    
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        
        # Sample trajectory frames
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if frames or final:
            all_images = (frames or []) + ([final] if final else [])
            
            vlm_prompt = """Analyze these screenshots from a 3D Slicer brain MRI analysis session.

The user was asked to measure white matter (WM) and gray matter (GM) intensity in a T1-weighted brain MRI.

Looking at the progression of screenshots:
1. Is a brain MRI visible in the slice views?
2. Are there any fiducial markers/points placed on the brain?
3. If markers are visible, do they appear to be placed appropriately:
   - One in bright central brain tissue (white matter/centrum semiovale)
   - One in darker cortical tissue (gray matter at brain surface)

Respond in JSON:
{
    "brain_mri_visible": true/false,
    "fiducials_visible": true/false,
    "placement_appears_correct": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
            
            vlm_result = query_vlm(images=all_images, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                brain_visible = parsed.get('brain_mri_visible', False)
                fiducials_visible = parsed.get('fiducials_visible', False)
                placement_correct = parsed.get('placement_appears_correct', False)
                confidence = parsed.get('confidence', 'low')
                
                details['vlm_brain_visible'] = brain_visible
                details['vlm_fiducials_visible'] = fiducials_visible
                details['vlm_placement_correct'] = placement_correct
                
                if brain_visible and fiducials_visible and placement_correct:
                    score += w_vlm
                    feedback_parts.append("VLM: Correct anatomy sampling")
                elif brain_visible and fiducials_visible:
                    score += w_vlm * 0.6
                    feedback_parts.append("VLM: Fiducials placed")
                elif brain_visible:
                    score += w_vlm * 0.3
                    feedback_parts.append("VLM: Brain visible")
    except ImportError:
        logger.warning("VLM module not available, skipping visual verification")
        # Give partial credit if other criteria are met
        if wm_greater_than_gm and ratio_valid:
            score += w_vlm * 0.5
            feedback_parts.append("VLM unavailable (partial credit)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_output_exists + w_json_valid + w_wm_gt_gm + w_ratio_range + w_reasonable + w_markups + w_vlm
    
    # Key criterion: WM > GM must be satisfied
    key_criteria_met = wm_greater_than_gm
    
    # Pass if score >= 70 and key criteria met
    passed = (score >= 70) and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        if score >= 90:
            feedback = f"EXCELLENT: {feedback}"
        else:
            feedback = f"PASSED: {feedback}"
    else:
        if not key_criteria_met:
            feedback = f"FAILED (WM must be > GM on T1): {feedback}"
        else:
            feedback = f"FAILED (score {score}/100): {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }