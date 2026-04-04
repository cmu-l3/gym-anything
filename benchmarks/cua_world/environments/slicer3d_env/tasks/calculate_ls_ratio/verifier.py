#!/usr/bin/env python3
"""
Verifier for calculate_ls_ratio task.

VERIFICATION STRATEGY (Multi-Signal Hybrid):

Programmatic checks (80 points):
1. Output file exists (15 points)
2. Liver HU in valid range (15 points)
3. Spleen HU in valid range (15 points)
4. L/S ratio calculated correctly (20 points)
5. Clinical interpretation correct (15 points)

VLM verification (20 points):
6. ROI placement quality - trajectory frames show proper ROI placement (20 points)

Anti-gaming:
- File must be created during task window (timestamp check)
- HU standard deviations must be plausible (not fabricated)
- Ratio must match actual calculation from HU values

Pass threshold: 70 points with ratio calculation correct
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_calculate_ls_ratio(traj, env_info, task_info):
    """
    Verify liver-to-spleen ratio measurement task completion.
    
    Uses programmatic checks with VLM trajectory verification.
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
    liver_hu_range = metadata.get('liver_hu_range', {"min": 10, "max": 100})
    spleen_hu_range = metadata.get('spleen_hu_range', {"min": 30, "max": 80})
    liver_std_range = metadata.get('liver_std_range', {"min": 3, "max": 30})
    spleen_std_range = metadata.get('spleen_std_range', {"min": 3, "max": 25})
    ratio_tolerance = metadata.get('ratio_calculation_tolerance', 0.02)
    
    weights = metadata.get('scoring_weights', {})
    w_output = weights.get('output_file_exists', 15)
    w_liver = weights.get('liver_hu_valid', 15)
    w_spleen = weights.get('spleen_hu_valid', 15)
    w_ratio = weights.get('ratio_calculated_correctly', 20)
    w_interp = weights.get('interpretation_correct', 15)
    w_roi = weights.get('roi_placement_quality', 20)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/ls_ratio_task_result.json", temp_result.name)
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
    # CRITERION 1: Output file exists (15 points)
    # ============================================================
    output_exists = result.get('output_file_exists', False)
    valid_json = result.get('valid_json', False)
    file_created = result.get('file_created_during_task', False)

    if output_exists and valid_json and file_created:
        score += w_output
        feedback_parts.append("Output file created with valid JSON")
        details['output_status'] = 'created_during_task'
    elif output_exists and valid_json:
        score += w_output * 0.5
        feedback_parts.append("Output file exists (but may predate task)")
        details['output_status'] = 'exists_but_not_new'
    elif output_exists:
        score += w_output * 0.25
        feedback_parts.append("Output file exists but invalid JSON")
        details['output_status'] = 'invalid_json'
    else:
        feedback_parts.append("Output file NOT found")
        details['output_status'] = 'missing'
        # Cannot proceed without output
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ============================================================
    # CRITERION 2: Liver HU in valid range (15 points)
    # ============================================================
    liver_hu_str = result.get('liver_hu_mean', '')
    liver_std_str = result.get('liver_hu_std', '')
    
    liver_hu = None
    liver_std = None
    try:
        liver_hu = float(liver_hu_str) if liver_hu_str else None
        liver_std = float(liver_std_str) if liver_std_str else None
    except (ValueError, TypeError):
        pass

    details['liver_hu_mean'] = liver_hu
    details['liver_hu_std'] = liver_std

    if liver_hu is not None:
        if liver_hu_range['min'] <= liver_hu <= liver_hu_range['max']:
            # Check std is also plausible (anti-gaming)
            if liver_std is not None and liver_std_range['min'] <= liver_std <= liver_std_range['max']:
                score += w_liver
                feedback_parts.append(f"Liver HU valid ({liver_hu:.1f} ± {liver_std:.1f})")
            elif liver_std is not None:
                score += w_liver * 0.7
                feedback_parts.append(f"Liver HU valid ({liver_hu:.1f}), std unusual ({liver_std:.1f})")
            else:
                score += w_liver * 0.6
                feedback_parts.append(f"Liver HU valid ({liver_hu:.1f}), no std reported")
        else:
            score += w_liver * 0.3
            feedback_parts.append(f"Liver HU out of range ({liver_hu:.1f})")
    else:
        feedback_parts.append("Liver HU not measured")

    # ============================================================
    # CRITERION 3: Spleen HU in valid range (15 points)
    # ============================================================
    spleen_hu_str = result.get('spleen_hu_mean', '')
    spleen_std_str = result.get('spleen_hu_std', '')
    
    spleen_hu = None
    spleen_std = None
    try:
        spleen_hu = float(spleen_hu_str) if spleen_hu_str else None
        spleen_std = float(spleen_std_str) if spleen_std_str else None
    except (ValueError, TypeError):
        pass

    details['spleen_hu_mean'] = spleen_hu
    details['spleen_hu_std'] = spleen_std

    if spleen_hu is not None:
        if spleen_hu_range['min'] <= spleen_hu <= spleen_hu_range['max']:
            if spleen_std is not None and spleen_std_range['min'] <= spleen_std <= spleen_std_range['max']:
                score += w_spleen
                feedback_parts.append(f"Spleen HU valid ({spleen_hu:.1f} ± {spleen_std:.1f})")
            elif spleen_std is not None:
                score += w_spleen * 0.7
                feedback_parts.append(f"Spleen HU valid ({spleen_hu:.1f}), std unusual ({spleen_std:.1f})")
            else:
                score += w_spleen * 0.6
                feedback_parts.append(f"Spleen HU valid ({spleen_hu:.1f}), no std reported")
        else:
            score += w_spleen * 0.3
            feedback_parts.append(f"Spleen HU out of range ({spleen_hu:.1f})")
    else:
        feedback_parts.append("Spleen HU not measured")

    # ============================================================
    # CRITERION 4: L/S Ratio calculated correctly (20 points)
    # ============================================================
    ls_ratio_str = result.get('ls_ratio', '')
    ls_ratio = None
    try:
        ls_ratio = float(ls_ratio_str) if ls_ratio_str else None
    except (ValueError, TypeError):
        pass

    details['ls_ratio'] = ls_ratio
    ratio_correct = result.get('ratio_calculation_correct', False)

    if ls_ratio is not None and liver_hu is not None and spleen_hu is not None and spleen_hu > 0:
        expected_ratio = liver_hu / spleen_hu
        ratio_diff = abs(expected_ratio - ls_ratio)
        details['expected_ratio'] = expected_ratio
        details['ratio_diff'] = ratio_diff

        if ratio_diff <= ratio_tolerance:
            score += w_ratio
            feedback_parts.append(f"L/S ratio correct ({ls_ratio:.3f})")
        elif ratio_diff <= ratio_tolerance * 2:
            score += w_ratio * 0.7
            feedback_parts.append(f"L/S ratio close ({ls_ratio:.3f}, expected {expected_ratio:.3f})")
        else:
            score += w_ratio * 0.3
            feedback_parts.append(f"L/S ratio incorrect ({ls_ratio:.3f}, expected {expected_ratio:.3f})")
    elif ls_ratio is not None:
        # Ratio reported but cannot verify calculation
        if 0.5 <= ls_ratio <= 1.5:
            score += w_ratio * 0.5
            feedback_parts.append(f"L/S ratio in plausible range ({ls_ratio:.3f})")
        else:
            score += w_ratio * 0.2
            feedback_parts.append(f"L/S ratio implausible ({ls_ratio:.3f})")
    else:
        feedback_parts.append("L/S ratio not calculated")

    # ============================================================
    # CRITERION 5: Clinical interpretation correct (15 points)
    # ============================================================
    interpretation = result.get('interpretation', '').strip()
    details['interpretation'] = interpretation

    if ls_ratio is not None and interpretation:
        # Determine expected classification
        if ls_ratio >= 1.0:
            expected_class = "Normal"
        elif ls_ratio >= 0.8:
            expected_class = "Borderline"
        else:
            expected_class = "Abnormal"
        
        details['expected_classification'] = expected_class

        if interpretation.lower() == expected_class.lower():
            score += w_interp
            feedback_parts.append(f"Interpretation correct ({interpretation})")
        else:
            score += w_interp * 0.3
            feedback_parts.append(f"Interpretation wrong ('{interpretation}', expected '{expected_class}')")
    elif interpretation:
        # Check if interpretation is at least a valid category
        valid_classes = ["normal", "borderline", "abnormal"]
        if interpretation.lower() in valid_classes:
            score += w_interp * 0.5
            feedback_parts.append(f"Interpretation valid but unverified ({interpretation})")
        else:
            score += w_interp * 0.2
            feedback_parts.append(f"Unknown interpretation: '{interpretation}'")
    else:
        feedback_parts.append("No interpretation provided")

    # ============================================================
    # CRITERION 6: VLM ROI placement quality (20 points)
    # ============================================================
    vlm_score = 0
    vlm_feedback = "VLM verification skipped"
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Get trajectory frames - use multiple frames to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) > 0:
            # Use VLM to check ROI placement quality
            vlm_prompt = """You are verifying a liver-to-spleen ratio measurement task in 3D Slicer medical imaging software.

Look at these screenshots showing the workflow progression and assess:

1. Is abdominal CT data visible? (Look for cross-sectional body images with grayscale)
2. Are ROIs (regions of interest) visible? (Look for circles, ellipses, or highlighted regions)
3. If ROIs are visible, are they appropriately placed?
   - LIVER ROI should be on the RIGHT side of the image (anatomical right, which appears on left of screen in standard radiological orientation)
   - SPLEEN ROI should be on the LEFT side 
   - ROIs should be in parenchyma (solid tissue), NOT in vessels (dark circular areas)
   - ROIs should NOT be on organ edges

4. Does the interface show measurement statistics or values?

Respond in JSON format:
{
    "ct_visible": true/false,
    "rois_visible": true/false,
    "liver_roi_appropriate": true/false/uncertain,
    "spleen_roi_appropriate": true/false/uncertain,
    "measurements_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                ct_visible = parsed.get('ct_visible', False)
                rois_visible = parsed.get('rois_visible', False)
                liver_appropriate = parsed.get('liver_roi_appropriate', False)
                spleen_appropriate = parsed.get('spleen_roi_appropriate', False)
                meas_visible = parsed.get('measurements_visible', False)
                confidence = parsed.get('confidence', 'low')
                
                # Score based on VLM findings
                if ct_visible:
                    vlm_score += 4
                if rois_visible:
                    vlm_score += 4
                if liver_appropriate is True:
                    vlm_score += 4
                elif liver_appropriate == 'uncertain':
                    vlm_score += 2
                if spleen_appropriate is True:
                    vlm_score += 4
                elif spleen_appropriate == 'uncertain':
                    vlm_score += 2
                if meas_visible:
                    vlm_score += 4
                
                # Adjust by confidence
                if confidence == 'low':
                    vlm_score = int(vlm_score * 0.6)
                elif confidence == 'medium':
                    vlm_score = int(vlm_score * 0.8)
                
                vlm_feedback = parsed.get('observations', 'VLM analysis complete')
            else:
                vlm_feedback = "VLM query failed"
                details['vlm_error'] = vlm_result.get('error', 'unknown') if vlm_result else 'no response'
        else:
            vlm_feedback = "No trajectory frames available"
            
    except ImportError:
        vlm_feedback = "VLM utilities not available"
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)}"
        details['vlm_exception'] = str(e)

    score += vlm_score
    feedback_parts.append(f"ROI quality: {vlm_score}/{w_roi} ({vlm_feedback})")
    details['vlm_score'] = vlm_score

    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Determine pass/fail
    # Key criteria: output exists AND ratio calculation is correct or plausible
    key_criteria_met = (
        output_exists and 
        valid_json and
        ls_ratio is not None and
        (ratio_correct or (ls_ratio is not None and 0.5 <= ls_ratio <= 1.5))
    )
    
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),  # Cap at 100
        "feedback": feedback,
        "details": details
    }