#!/usr/bin/env python3
"""
Verifier for configure_volume_overlay task.

VERIFICATION STRATEGY (Multi-Signal):

Programmatic checks (90 points):
1. Both volumes loaded (15 pts) - FLAIR and T1ce exist in scene
2. Background configured (20 pts) - FLAIR set as background in at least one slice view
3. Foreground configured (20 pts) - T1ce set as foreground in at least one slice view
4. Opacity correct (20 pts) - Foreground opacity between 0.4-0.6
5. Screenshot saved (15 pts) - Valid screenshot at expected path, created during task

VLM verification (10 points):
6. Visual verification (10 pts) - Trajectory frames show overlay configuration workflow

Pass threshold: 75 points with Background AND Foreground correctly configured
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_volume_overlay(traj, env_info, task_info):
    """
    Verify that the volume overlay was configured correctly.
    
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
    expected_opacity_min = metadata.get('expected_opacity_min', 0.4)
    expected_opacity_max = metadata.get('expected_opacity_max', 0.6)
    
    weights = metadata.get('scoring_weights', {})
    w_volumes = weights.get('volumes_loaded', 15)
    w_background = weights.get('background_configured', 20)
    w_foreground = weights.get('foreground_configured', 20)
    w_opacity = weights.get('opacity_correct', 20)
    w_screenshot = weights.get('screenshot_saved', 15)
    w_vlm = weights.get('vlm_verification', 10)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/overlay_task_result.json", temp_result.name)
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

    details['raw_result'] = result

    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ================================================================
    # CRITERION 1: Both volumes loaded (15 points)
    # ================================================================
    flair_loaded = result.get('flair_loaded', False)
    t1ce_loaded = result.get('t1ce_loaded', False)
    volumes_loaded = result.get('volumes_loaded', 0)

    if flair_loaded and t1ce_loaded:
        score += w_volumes
        feedback_parts.append(f"Both volumes loaded ({volumes_loaded} total)")
        details['volumes_criterion'] = 'full'
    elif flair_loaded or t1ce_loaded:
        score += w_volumes // 2
        missing = "T1ce" if flair_loaded else "FLAIR"
        feedback_parts.append(f"Only one volume loaded (missing {missing})")
        details['volumes_criterion'] = 'partial'
    else:
        feedback_parts.append("Required volumes not loaded")
        details['volumes_criterion'] = 'failed'

    # ================================================================
    # CRITERION 2: Background configured to FLAIR (20 points)
    # ================================================================
    correct_overlay = result.get('correct_overlay_configured', False)
    any_overlay = result.get('any_overlay_configured', False)

    # Try to get more detailed info from slicer state
    temp_state = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    slicer_state = {}
    try:
        copy_from_env("/tmp/slicer_overlay_state.json", temp_state.name)
        with open(temp_state.name, 'r') as f:
            slicer_state = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load detailed slicer state: {e}")
    finally:
        if os.path.exists(temp_state.name):
            os.unlink(temp_state.name)

    background_configured = False
    foreground_configured = False
    actual_opacity = result.get('best_opacity', 0)

    # Check composite configurations
    configs = slicer_state.get('composite_configurations', [])
    for cfg in configs:
        bg_name = cfg.get('background_name', '').lower()
        fg_name = cfg.get('foreground_name', '').lower()
        fg_opacity = cfg.get('foreground_opacity', 0)
        
        # Check if FLAIR is background
        if 'flair' in bg_name:
            background_configured = True
        
        # Check if T1ce is foreground
        if 't1ce' in fg_name or 't1_ce' in fg_name or 't1-ce' in fg_name:
            foreground_configured = True
            actual_opacity = fg_opacity

    # Use result flags as fallback
    if correct_overlay:
        background_configured = True
        foreground_configured = True

    if background_configured:
        score += w_background
        feedback_parts.append("Background configured (FLAIR)")
        details['background_criterion'] = 'passed'
    elif any_overlay:
        score += w_background // 2
        feedback_parts.append("Background set but not FLAIR")
        details['background_criterion'] = 'partial'
    else:
        feedback_parts.append("Background not configured")
        details['background_criterion'] = 'failed'

    # ================================================================
    # CRITERION 3: Foreground configured to T1ce (20 points)
    # ================================================================
    if foreground_configured:
        score += w_foreground
        feedback_parts.append("Foreground configured (T1ce)")
        details['foreground_criterion'] = 'passed'
    elif any_overlay:
        score += w_foreground // 2
        feedback_parts.append("Foreground set but not T1ce")
        details['foreground_criterion'] = 'partial'
    else:
        feedback_parts.append("Foreground not configured")
        details['foreground_criterion'] = 'failed'

    # ================================================================
    # CRITERION 4: Opacity correct (20 points)
    # ================================================================
    opacity_correct = result.get('opacity_correct', False)
    
    if not actual_opacity:
        actual_opacity = result.get('best_opacity', 0)
    
    details['actual_opacity'] = actual_opacity
    details['expected_opacity_range'] = f"{expected_opacity_min}-{expected_opacity_max}"

    if opacity_correct or (expected_opacity_min <= actual_opacity <= expected_opacity_max):
        score += w_opacity
        feedback_parts.append(f"Opacity correct ({actual_opacity:.0%})")
        details['opacity_criterion'] = 'passed'
    elif 0.3 <= actual_opacity <= 0.7:
        # Close but not exact
        score += w_opacity // 2
        feedback_parts.append(f"Opacity close ({actual_opacity:.0%}, expected 40-60%)")
        details['opacity_criterion'] = 'partial'
    elif actual_opacity > 0:
        score += w_opacity // 4
        feedback_parts.append(f"Opacity set ({actual_opacity:.0%}) but outside range")
        details['opacity_criterion'] = 'wrong_value'
    else:
        feedback_parts.append("Opacity not adjusted (0%)")
        details['opacity_criterion'] = 'failed'

    # ================================================================
    # CRITERION 5: Screenshot saved (15 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_kb', 0)
    screenshot_created = result.get('screenshot_created_during_task', False)

    if screenshot_exists and screenshot_created and screenshot_size > 50:
        score += w_screenshot
        feedback_parts.append(f"Screenshot saved ({screenshot_size}KB)")
        details['screenshot_criterion'] = 'passed'
    elif screenshot_exists and screenshot_size > 50:
        score += w_screenshot * 2 // 3
        feedback_parts.append(f"Screenshot exists but may be pre-existing ({screenshot_size}KB)")
        details['screenshot_criterion'] = 'partial_timing'
    elif screenshot_exists:
        score += w_screenshot // 3
        feedback_parts.append(f"Screenshot too small ({screenshot_size}KB)")
        details['screenshot_criterion'] = 'partial_size'
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_criterion'] = 'failed'

    # ================================================================
    # CRITERION 6: VLM verification using trajectory frames (10 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = "VLM not available"

    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample trajectory frames (not just final screenshot)
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) > 0:
            vlm_prompt = """You are verifying a 3D Slicer medical imaging task.

The agent was asked to configure a volume overlay with:
- FLAIR MRI as background
- T1ce (post-contrast) as foreground
- ~50% opacity for blending

Analyze these trajectory screenshots and assess:
1. OVERLAY_VISIBLE: Is there evidence of a blended/overlaid display showing two MRI sequences simultaneously?
2. SLICE_VIEW_INTERACTION: Did the agent interact with slice view controls (pin icon, layer dropdowns)?
3. MEANINGFUL_WORK: Do the frames show progression of configuring the overlay?

Respond in JSON format:
{
    "overlay_visible": true/false,
    "slice_view_interaction": true/false,
    "meaningful_work": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_response'] = parsed
                
                overlay_visible = parsed.get('overlay_visible', False)
                interaction = parsed.get('slice_view_interaction', False)
                meaningful = parsed.get('meaningful_work', False)
                confidence = parsed.get('confidence', 'low')
                
                if overlay_visible and meaningful:
                    vlm_score = w_vlm
                    vlm_feedback = f"VLM confirms overlay configured (confidence: {confidence})"
                elif overlay_visible or meaningful:
                    vlm_score = w_vlm // 2
                    vlm_feedback = f"VLM partial confirmation (confidence: {confidence})"
                else:
                    vlm_feedback = f"VLM did not confirm overlay (confidence: {confidence})"
            else:
                vlm_feedback = "VLM query failed"
        else:
            vlm_feedback = "No trajectory frames available"
            
    except ImportError:
        vlm_feedback = "VLM module not available"
        logger.info("VLM verification skipped - module not available")
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)}"
        logger.warning(f"VLM verification failed: {e}")

    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ================================================================
    # Calculate final result
    # ================================================================
    max_score = w_volumes + w_background + w_foreground + w_opacity + w_screenshot + w_vlm
    
    # Key criteria: background AND foreground must be configured
    key_criteria_met = background_configured and foreground_configured
    
    # Pass if score >= 75% AND key criteria met
    passed = (score >= 75) and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    details['score_breakdown'] = {
        'volumes_loaded': w_volumes if (flair_loaded and t1ce_loaded) else 0,
        'background_configured': w_background if background_configured else 0,
        'foreground_configured': w_foreground if foreground_configured else 0,
        'opacity_correct': details.get('opacity_criterion', 'failed'),
        'screenshot_saved': details.get('screenshot_criterion', 'failed'),
        'vlm_verification': vlm_score,
        'max_score': max_score
    }
    details['key_criteria_met'] = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }