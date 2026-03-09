#!/usr/bin/env python3
"""
Verifier for Calculate SNR Metric task.

VERIFICATION STRATEGY (Multi-criteria with anti-gaming):

1. JSON File Exists (15 pts) - Output file was created at correct path
2. Valid JSON Format (10 pts) - File parses correctly with required fields
3. Signal Mean Plausible (15 pts) - Value in range 200-1500 (tissue intensity)
4. Noise Std Plausible (15 pts) - Value in range 5-80 (background noise level)
5. SNR Mathematically Correct (20 pts) - Reported SNR = signal_mean / noise_std ± 1%
6. SNR in Expected Range (10 pts) - SNR between 10 and 60
7. Segments Exist (10 pts) - At least 2 segments in scene
8. Visual Confirmation (5 pts) - VLM confirms proper segment placement

ANTI-GAMING:
- File must be created DURING task (timestamp check)
- SNR must be mathematically consistent with inputs
- Values must be in physiologically plausible ranges

Pass threshold: 70 points, with JSON exists AND SNR mathematically correct
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_snr_metric(traj, env_info, task_info):
    """
    Verify SNR calculation task completion.
    
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
    signal_range = metadata.get('expected_signal_mean_range', {"min": 200, "max": 1500})
    noise_range = metadata.get('expected_noise_std_range', {"min": 5, "max": 80})
    snr_range = metadata.get('expected_snr_range', {"min": 10, "max": 60})
    snr_tolerance = metadata.get('snr_calculation_tolerance', 0.01)
    
    weights = metadata.get('scoring_weights', {})
    w_json_exists = weights.get('json_exists', 15)
    w_json_valid = weights.get('json_valid_format', 10)
    w_signal_plausible = weights.get('signal_mean_plausible', 15)
    w_noise_plausible = weights.get('noise_std_plausible', 15)
    w_snr_correct = weights.get('snr_mathematically_correct', 20)
    w_snr_range = weights.get('snr_in_expected_range', 10)
    w_segments = weights.get('segments_exist', 10)
    w_vlm = weights.get('vlm_visual_confirmation', 5)

    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Copy export result from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/snr_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info(f"Loaded export result: {result}")
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
            "feedback": f"Invalid JSON in export result: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read export result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ================================================================
    # Also try to copy the actual output JSON directly
    # ================================================================
    output_data = None
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/snr_output_copy.json", temp_output.name)
        with open(temp_output.name, 'r') as f:
            output_data = json.load(f)
        logger.info(f"Loaded output JSON directly: {output_data}")
    except Exception as e:
        logger.warning(f"Could not load output JSON copy: {e}")
        # Fall back to values from export result
        pass
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # ================================================================
    # CRITERION 1: JSON File Exists (15 pts)
    # ================================================================
    json_exists = result.get('output_json_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if json_exists:
        if file_created_during_task:
            score += w_json_exists
            feedback_parts.append("Output JSON created during task")
            details['json_exists'] = True
            details['created_during_task'] = True
        else:
            score += w_json_exists // 2
            feedback_parts.append("Output JSON exists (but not confirmed created during task)")
            details['json_exists'] = True
            details['created_during_task'] = False
    else:
        feedback_parts.append("Output JSON NOT found")
        details['json_exists'] = False
        # Early return if no output
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Valid JSON Format (10 pts)
    # ================================================================
    json_valid = result.get('output_json_valid', False)
    
    # Get values either from direct copy or from export result
    signal_mean = None
    noise_std = None
    snr_value = None
    
    if output_data:
        signal_mean = output_data.get('signal_mean')
        noise_std = output_data.get('noise_std')
        snr_value = output_data.get('snr')
    else:
        # Parse from export result strings
        try:
            sm = result.get('signal_mean', '')
            if sm:
                signal_mean = float(sm)
        except (ValueError, TypeError):
            pass
        try:
            ns = result.get('noise_std', '')
            if ns:
                noise_std = float(ns)
        except (ValueError, TypeError):
            pass
        try:
            sv = result.get('snr_value', '')
            if sv:
                snr_value = float(sv)
        except (ValueError, TypeError):
            pass

    # Check all required fields are present and numeric
    all_fields_valid = (
        signal_mean is not None and 
        noise_std is not None and 
        snr_value is not None and
        isinstance(signal_mean, (int, float)) and
        isinstance(noise_std, (int, float)) and
        isinstance(snr_value, (int, float))
    )
    
    if all_fields_valid:
        score += w_json_valid
        feedback_parts.append("JSON format valid with all required fields")
        details['json_valid'] = True
    else:
        feedback_parts.append("JSON missing or invalid fields")
        details['json_valid'] = False
        details['signal_mean'] = signal_mean
        details['noise_std'] = noise_std
        details['snr_value'] = snr_value

    details['extracted_signal_mean'] = signal_mean
    details['extracted_noise_std'] = noise_std
    details['extracted_snr'] = snr_value

    # ================================================================
    # CRITERION 3: Signal Mean Plausible (15 pts)
    # ================================================================
    signal_plausible = False
    if signal_mean is not None:
        if signal_range['min'] <= signal_mean <= signal_range['max']:
            score += w_signal_plausible
            feedback_parts.append(f"Signal mean plausible ({signal_mean:.1f})")
            signal_plausible = True
        elif signal_mean > 0:
            # Partial credit for positive but out-of-range value
            score += w_signal_plausible // 3
            feedback_parts.append(f"Signal mean out of typical range ({signal_mean:.1f})")
        else:
            feedback_parts.append(f"Signal mean invalid ({signal_mean})")
    else:
        feedback_parts.append("Signal mean missing")
    
    details['signal_plausible'] = signal_plausible

    # ================================================================
    # CRITERION 4: Noise Std Plausible (15 pts)
    # ================================================================
    noise_plausible = False
    if noise_std is not None:
        if noise_range['min'] <= noise_std <= noise_range['max']:
            score += w_noise_plausible
            feedback_parts.append(f"Noise std plausible ({noise_std:.1f})")
            noise_plausible = True
        elif noise_std > 0:
            score += w_noise_plausible // 3
            feedback_parts.append(f"Noise std out of typical range ({noise_std:.1f})")
        else:
            feedback_parts.append(f"Noise std invalid ({noise_std})")
    else:
        feedback_parts.append("Noise std missing")
    
    details['noise_plausible'] = noise_plausible

    # ================================================================
    # CRITERION 5: SNR Mathematically Correct (20 pts) - KEY CRITERION
    # ================================================================
    snr_correct = False
    if signal_mean is not None and noise_std is not None and snr_value is not None:
        if noise_std > 0:
            expected_snr = signal_mean / noise_std
            # Allow 1% relative tolerance or 0.1 absolute tolerance
            absolute_diff = abs(snr_value - expected_snr)
            relative_diff = absolute_diff / expected_snr if expected_snr > 0 else float('inf')
            
            if relative_diff <= snr_tolerance or absolute_diff <= 0.1:
                score += w_snr_correct
                feedback_parts.append(f"SNR calculation correct ({snr_value:.2f} ≈ {expected_snr:.2f})")
                snr_correct = True
            else:
                feedback_parts.append(f"SNR calculation INCORRECT: reported {snr_value:.2f} vs expected {expected_snr:.2f}")
            
            details['expected_snr'] = expected_snr
            details['snr_difference'] = absolute_diff
        else:
            feedback_parts.append("Cannot verify SNR: noise_std is zero or negative")
    else:
        feedback_parts.append("Cannot verify SNR calculation: missing values")
    
    details['snr_correct'] = snr_correct

    # ================================================================
    # CRITERION 6: SNR in Expected Range (10 pts)
    # ================================================================
    snr_in_range = False
    if snr_value is not None:
        if snr_range['min'] <= snr_value <= snr_range['max']:
            score += w_snr_range
            feedback_parts.append(f"SNR in expected range ({snr_value:.2f})")
            snr_in_range = True
        elif snr_value > 0:
            score += w_snr_range // 2
            feedback_parts.append(f"SNR outside typical range ({snr_value:.2f})")
        else:
            feedback_parts.append(f"SNR invalid ({snr_value})")
    
    details['snr_in_range'] = snr_in_range

    # ================================================================
    # CRITERION 7: Segments Exist (10 pts)
    # ================================================================
    segmentation_exists = result.get('segmentation_exists', False)
    num_segments = result.get('num_segments', 0)
    has_signal = result.get('has_signal_segment', False)
    has_noise = result.get('has_noise_segment', False)
    
    if segmentation_exists and num_segments >= 2:
        if has_signal and has_noise:
            score += w_segments
            feedback_parts.append(f"Segments exist: Signal and Noise found ({num_segments} total)")
        else:
            score += w_segments * 2 // 3
            segment_names = result.get('segment_names', '')
            feedback_parts.append(f"Segments exist ({num_segments}): {segment_names}")
    elif num_segments >= 1:
        score += w_segments // 3
        feedback_parts.append(f"Only {num_segments} segment(s) found (expected 2+)")
    else:
        feedback_parts.append("No segmentation found in scene")
    
    details['segmentation_exists'] = segmentation_exists
    details['num_segments'] = num_segments
    details['has_signal_segment'] = has_signal
    details['has_noise_segment'] = has_noise

    # ================================================================
    # CRITERION 8: VLM Visual Confirmation (5 pts)
    # ================================================================
    # Use trajectory frames to verify segments were actually created
    query_vlm = env_info.get('query_vlm')
    vlm_confirmed = False
    
    if query_vlm and traj:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            images = frames + ([final] if final else [])
            
            if images:
                vlm_prompt = """Analyze these screenshots from 3D Slicer performing SNR measurement.

Look for evidence of:
1. Segment Editor being used (segmentation panel visible)
2. Colored segment overlays on the brain MRI
3. One segment in brain tissue (typically central bright area)
4. One segment in background air (dark corners)
5. Segment Statistics module being used

Respond in JSON:
{
    "segment_editor_used": true/false,
    "segments_visible": true/false,
    "signal_region_in_brain": true/false,
    "noise_region_in_background": true/false,
    "workflow_appears_correct": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=images)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('workflow_appears_correct') or (
                        parsed.get('segments_visible') and 
                        parsed.get('segment_editor_used')
                    ):
                        score += w_vlm
                        vlm_confirmed = True
                        feedback_parts.append("VLM confirmed segmentation workflow")
                    else:
                        feedback_parts.append("VLM could not confirm proper workflow")
                    
                    details['vlm_result'] = parsed
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"VLM check skipped: {e}")
    else:
        # Award partial points if no VLM but other criteria met
        if segmentation_exists and snr_correct:
            score += w_vlm // 2
            feedback_parts.append("VLM check skipped (no VLM available)")
    
    details['vlm_confirmed'] = vlm_confirmed

    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria for passing: JSON exists AND SNR calculation correct
    key_criteria_met = json_exists and snr_correct
    
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }