#!/usr/bin/env python3
"""
Verifier for Adjust Lung Window task.

VERIFICATION STRATEGY:
This task verifies that the agent correctly adjusted CT window/level settings
from soft tissue window (W:400, L:40) to lung window (W:~1500, L:~-600).

CRITERIA:
1. Window in acceptable range (35 points) - W between 1200-1800 HU
2. Level in acceptable range (35 points) - L between -700 to -500 HU
3. Values actually changed (10 points) - Not still at initial values
4. VLM verification (15 points) - Lung parenchyma visible in trajectory
5. Optimal range bonus (5 points) - Values within ±100 of ideal

ANTI-GAMING:
- Checks values changed from initial state
- Uses trajectory frames (not just final) for VLM verification
- Verifies Slicer was running and data was loaded

Pass threshold: 70 points with both Window and Level in acceptable ranges
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adjust_lung_window(traj, env_info, task_info):
    """
    Verify that CT window/level was adjusted to lung window settings.
    
    Uses multi-criteria scoring with programmatic checks and VLM trajectory analysis.
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
    
    # Target ranges
    window_range = metadata.get('window_acceptable_range', {"min": 1200, "max": 1800})
    level_range = metadata.get('level_acceptable_range', {"min": -700, "max": -500})
    optimal_window = metadata.get('optimal_window_range', {"min": 1400, "max": 1600})
    optimal_level = metadata.get('optimal_level_range', {"min": -650, "max": -550})
    
    # Initial values (what we set during setup)
    initial_window = metadata.get('initial_window', 400)
    initial_level = metadata.get('initial_level', 40)
    
    # Scoring weights
    weights = metadata.get('scoring_weights', {})
    w_window = weights.get('window_in_range', 35)
    w_level = weights.get('level_in_range', 35)
    w_changed = weights.get('values_changed', 10)
    w_vlm = weights.get('vlm_lung_visible', 15)
    w_optimal = weights.get('optimal_bonus', 5)

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lung_window_result.json", temp_result.name)
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

    # ================================================================
    # Initialize scoring
    # ================================================================
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Basic checks: Slicer running, data loaded
    # ================================================================
    slicer_running = result.get('slicer_was_running', False)
    data_loaded = result.get('data_loaded', False)
    
    if not slicer_running:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task"
        }
    
    if not data_loaded:
        feedback_parts.append("Warning: Data may not be loaded")
        details['data_loaded'] = False

    # ================================================================
    # Extract current W/L values
    # ================================================================
    current_window = result.get('current_window')
    current_level = result.get('current_level')
    
    details['initial_window'] = initial_window
    details['initial_level'] = initial_level
    details['current_window'] = current_window
    details['current_level'] = current_level

    if current_window is None or current_level is None:
        return {
            "passed": False,
            "score": 5 if slicer_running else 0,
            "feedback": "Could not extract current window/level values from Slicer",
            "details": details
        }

    try:
        current_window = float(current_window)
        current_level = float(current_level)
    except (ValueError, TypeError) as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"Invalid window/level values: {e}",
            "details": details
        }

    # ================================================================
    # CRITERION 1: Window in acceptable range (35 points)
    # ================================================================
    window_min = window_range.get('min', 1200)
    window_max = window_range.get('max', 1800)
    
    window_in_range = window_min <= current_window <= window_max
    
    if window_in_range:
        score += w_window
        feedback_parts.append(f"Window OK ({current_window:.0f} HU)")
    else:
        # Partial credit if close
        if current_window > initial_window * 1.5:  # At least moved in right direction
            partial = w_window * 0.3
            score += partial
            feedback_parts.append(f"Window partially adjusted ({current_window:.0f} HU, target: {window_min}-{window_max})")
        else:
            feedback_parts.append(f"Window NOT in range ({current_window:.0f} HU, need {window_min}-{window_max})")
    
    details['window_in_range'] = window_in_range

    # ================================================================
    # CRITERION 2: Level in acceptable range (35 points)
    # ================================================================
    level_min = level_range.get('min', -700)
    level_max = level_range.get('max', -500)
    
    level_in_range = level_min <= current_level <= level_max
    
    if level_in_range:
        score += w_level
        feedback_parts.append(f"Level OK ({current_level:.0f} HU)")
    else:
        # Partial credit if close
        if current_level < initial_level - 200:  # At least moved in right direction (negative)
            partial = w_level * 0.3
            score += partial
            feedback_parts.append(f"Level partially adjusted ({current_level:.0f} HU, target: {level_min} to {level_max})")
        else:
            feedback_parts.append(f"Level NOT in range ({current_level:.0f} HU, need {level_min} to {level_max})")
    
    details['level_in_range'] = level_in_range

    # ================================================================
    # CRITERION 3: Values changed from initial (10 points)
    # ================================================================
    values_changed = result.get('values_changed', False)
    
    # Double-check programmatically
    window_changed = abs(current_window - initial_window) > 50
    level_changed = abs(current_level - initial_level) > 50
    
    if window_changed and level_changed:
        score += w_changed
        feedback_parts.append("Values changed from initial")
        details['values_changed'] = True
    elif window_changed or level_changed:
        score += w_changed * 0.5
        feedback_parts.append("Partial value change")
        details['values_changed'] = "partial"
    else:
        feedback_parts.append("Values not changed from initial!")
        details['values_changed'] = False

    # ================================================================
    # CRITERION 4: VLM Trajectory Verification (15 points)
    # Check if lung parenchyma is visible in the trajectory
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample trajectory frames (not just final screenshot)
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.
            
The task was to adjust CT window/level settings to "lung window" for a chest CT scan.

With LUNG WINDOW settings (Window ~1500, Level ~-600):
- Lung parenchyma appears DARK (black/dark gray)
- You can see internal lung structures (airways, vessels)
- Bones appear very bright/white

With SOFT TISSUE WINDOW settings (Window ~400, Level ~40):
- Lungs appear WHITE/washed out (no detail visible)
- Soft tissues are more visible
- Less contrast overall

Looking at the progression of screenshots:

1. Can you see CT scan slice views (axial/coronal/sagittal views of chest)?
2. In the LATER frames, do the lungs appear DARK (indicating lung window was applied)?
3. Can you see lung internal structures (airways, vessels) in the dark lung tissue?

Respond in JSON format:
{
    "ct_scan_visible": true/false,
    "lungs_appear_dark": true/false,
    "lung_structures_visible": true/false,
    "appears_to_be_lung_window": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                ct_visible = parsed.get('ct_scan_visible', False)
                lungs_dark = parsed.get('lungs_appear_dark', False)
                lung_structures = parsed.get('lung_structures_visible', False)
                is_lung_window = parsed.get('appears_to_be_lung_window', False)
                confidence = parsed.get('confidence', 'low')
                
                details['vlm_ct_visible'] = ct_visible
                details['vlm_lungs_dark'] = lungs_dark
                details['vlm_lung_structures'] = lung_structures
                details['vlm_is_lung_window'] = is_lung_window
                details['vlm_confidence'] = confidence
                
                # Score based on VLM findings
                if is_lung_window and confidence in ['medium', 'high']:
                    vlm_score = w_vlm
                    vlm_feedback = "VLM confirms lung window visible"
                elif lungs_dark and lung_structures:
                    vlm_score = w_vlm * 0.8
                    vlm_feedback = "VLM: Dark lungs with structures"
                elif lungs_dark or is_lung_window:
                    vlm_score = w_vlm * 0.5
                    vlm_feedback = "VLM: Partial lung window evidence"
                elif ct_visible:
                    vlm_score = w_vlm * 0.2
                    vlm_feedback = "VLM: CT visible but lung window unclear"
                else:
                    vlm_feedback = "VLM: Could not confirm lung window"
            else:
                vlm_feedback = "VLM query failed"
                details['vlm_error'] = vlm_result.get('error', 'unknown') if vlm_result else 'no response'
        else:
            vlm_feedback = "No trajectory frames available"
            
    except ImportError:
        vlm_feedback = "VLM not available"
        details['vlm_available'] = False
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        details['vlm_error'] = str(e)
    
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ================================================================
    # CRITERION 5: Optimal range bonus (5 points)
    # ================================================================
    opt_window_min = optimal_window.get('min', 1400)
    opt_window_max = optimal_window.get('max', 1600)
    opt_level_min = optimal_level.get('min', -650)
    opt_level_max = optimal_level.get('max', -550)
    
    window_optimal = opt_window_min <= current_window <= opt_window_max
    level_optimal = opt_level_min <= current_level <= opt_level_max
    
    if window_optimal and level_optimal:
        score += w_optimal
        feedback_parts.append("Optimal values!")
        details['optimal_values'] = True
    elif window_optimal or level_optimal:
        score += w_optimal * 0.5
        details['optimal_values'] = "partial"

    # ================================================================
    # Final scoring
    # ================================================================
    
    # Key criteria for passing
    key_criteria_met = window_in_range and level_in_range
    
    # Determine pass/fail
    passed = score >= 70 and key_criteria_met
    
    # Alternative pass: both values in range even without full score
    if key_criteria_met and score >= 60:
        passed = True
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": feedback,
        "details": details
    }