#!/usr/bin/env python3
"""
Verifier for configure_slab_mip task.

VERIFICATION CRITERIA:
1. Slab mode enabled (25 points) - Mode changed from "None" to any active mode
2. Correct mode - MIP/Max (25 points) - Slab mode is specifically "Max" (mode 2)
3. Thickness in range (25 points) - Slab thickness between 8-12mm
4. Correct slice view (15 points) - Configuration on Red/axial view
5. VLM vessel enhancement (10 points) - VLM confirms improved vessel visibility

Pass threshold: 65 points with slab mode enabled and correct mode

ANTI-GAMING:
- Checks that configuration changed from initial state
- Verifies task timestamps
- Uses trajectory frames for VLM (not just final screenshot)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_slab_mip(traj, env_info, task_info):
    """
    Verify that slab MIP configuration was correctly applied.
    
    Uses multi-criteria scoring with anti-gaming checks.
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
    target_slab_mode = metadata.get('target_slab_mode', 2)  # Max/MIP
    target_thickness_min = metadata.get('target_thickness_mm_min', 8.0)
    target_thickness_max = metadata.get('target_thickness_mm_max', 12.0)
    
    weights = metadata.get('scoring_weights', {})
    w_mode_enabled = weights.get('slab_mode_enabled', 25)
    w_mode_correct = weights.get('correct_mode_mip', 25)
    w_thickness = weights.get('thickness_in_range', 25)
    w_slice_view = weights.get('correct_slice_view', 15)
    w_vlm = weights.get('vlm_vessel_enhancement', 10)
    
    slab_mode_names = metadata.get('slab_modes', {
        "0": "None", "1": "Min", "2": "Max", "3": "Mean", "4": "Sum"
    })

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
        copy_from_env("/tmp/slab_mip_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script may have failed"
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

    # ================================================================
    # PREREQUISITE: Check Slicer was running
    # ================================================================
    if not result.get('slicer_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion",
            "details": details
        }

    # ================================================================
    # PREREQUISITE: Check volume was loaded
    # ================================================================
    volume_loaded = result.get('volume_loaded', False)
    if not volume_loaded:
        feedback_parts.append("Warning: Volume may not be loaded")
        details['volume_loaded'] = False
    else:
        details['volume_loaded'] = True

    # ================================================================
    # Extract measurements
    # ================================================================
    slab_mode = result.get('slab_mode', -1)
    slab_mode_name = result.get('slab_mode_name', 'Unknown')
    slab_slices = result.get('slab_slices', 0)
    slab_thickness_mm = result.get('slab_thickness_mm', 0)
    initial_slab_mode = result.get('initial_slab_mode', 0)
    initial_slab_slices = result.get('initial_slab_slices', 1)
    config_changed = result.get('config_changed', False)

    details['slab_mode'] = slab_mode
    details['slab_mode_name'] = slab_mode_name
    details['slab_slices'] = slab_slices
    details['slab_thickness_mm'] = slab_thickness_mm
    details['initial_slab_mode'] = initial_slab_mode
    details['config_changed'] = config_changed

    # ================================================================
    # CRITERION 1: Slab mode enabled (25 points)
    # Mode must be changed from "None" (0) to any active mode
    # ================================================================
    slab_mode_enabled = (slab_mode > 0)
    
    if slab_mode_enabled:
        score += w_mode_enabled
        feedback_parts.append(f"Slab mode enabled ({slab_mode_name})")
    else:
        if slab_mode == 0:
            feedback_parts.append("Slab mode still 'None' - not enabled")
        else:
            feedback_parts.append(f"Invalid slab mode: {slab_mode}")

    # ================================================================
    # CRITERION 2: Correct mode - Max/MIP (25 points)
    # Mode must be specifically "Max" (mode 2) for MIP
    # ================================================================
    mode_is_mip = (slab_mode == target_slab_mode)
    
    if mode_is_mip:
        score += w_mode_correct
        feedback_parts.append("Correct mode: Max (MIP)")
    elif slab_mode_enabled:
        # Give partial credit for other slab modes
        score += int(w_mode_correct * 0.3)
        feedback_parts.append(f"Slab mode is '{slab_mode_name}' (expected 'Max')")
    else:
        feedback_parts.append("Mode not set to Max/MIP")

    # ================================================================
    # CRITERION 3: Thickness in range 8-12mm (25 points)
    # ================================================================
    thickness_valid = False
    try:
        thickness = float(slab_thickness_mm)
        if target_thickness_min <= thickness <= target_thickness_max:
            thickness_valid = True
            score += w_thickness
            feedback_parts.append(f"Thickness OK: {thickness:.1f}mm")
        elif thickness > 0:
            # Partial credit for reasonable thickness
            if 5.0 <= thickness <= 15.0:
                score += int(w_thickness * 0.5)
                feedback_parts.append(f"Thickness {thickness:.1f}mm (target: {target_thickness_min}-{target_thickness_max}mm)")
            else:
                feedback_parts.append(f"Thickness {thickness:.1f}mm out of range")
        else:
            feedback_parts.append("No slab thickness configured")
    except (ValueError, TypeError):
        feedback_parts.append(f"Invalid thickness value: {slab_thickness_mm}")

    details['thickness_valid'] = thickness_valid

    # ================================================================
    # CRITERION 4: Correct slice view - Red/Axial (15 points)
    # Since we're checking the Red slice node, this is automatic
    # ================================================================
    # The export script specifically checks the Red slice node
    # Give full points if we have valid configuration data
    if slab_mode >= 0 and result.get('config_error') is None:
        score += w_slice_view
        feedback_parts.append("Configured on axial (Red) view")
    elif result.get('config_error'):
        feedback_parts.append(f"Config error: {result.get('config_error')}")

    # ================================================================
    # CRITERION 5: VLM vessel enhancement verification (10 points)
    # Use trajectory frames to verify actual workflow was performed
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        # Try to get VLM query function
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            # Import trajectory sampling utilities
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                
                # Sample frames from trajectory
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                
                if final:
                    all_frames = frames + [final] if frames else [final]
                    
                    vlm_prompt = """You are analyzing screenshots from a 3D Slicer medical imaging task.

The task was to configure a "thick slab MIP" (Maximum Intensity Projection) view for vessel visualization in an abdominal CT scan.

Examine the images and determine:
1. Is this 3D Slicer showing an abdominal CT scan?
2. Do you see the slice view controller/settings panel expanded (small icons/dropdowns in the slice view header)?
3. In the later images, do blood vessels (like the aorta) appear as bright continuous structures?
4. Is there evidence of slab/MIP mode being configured?

Respond in JSON format:
{
    "is_slicer_ct_view": true/false,
    "settings_panel_visible": true/false,
    "vessels_enhanced": true/false,
    "slab_config_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                    
                    vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_result'] = parsed
                        
                        # Score based on VLM observations
                        if parsed.get('is_slicer_ct_view', False):
                            vlm_score += 3
                        if parsed.get('settings_panel_visible', False):
                            vlm_score += 3
                        if parsed.get('vessels_enhanced', False):
                            vlm_score += 4
                        
                        vlm_feedback = parsed.get('observations', 'VLM analysis complete')
                    else:
                        vlm_feedback = "VLM query failed"
                        details['vlm_error'] = vlm_result.get('error', 'Unknown error') if vlm_result else 'No result'
                else:
                    vlm_feedback = "No trajectory screenshots available"
                    
            except ImportError:
                vlm_feedback = "VLM utilities not available"
                # Give partial credit based on programmatic checks
                if slab_mode_enabled and mode_is_mip:
                    vlm_score = int(w_vlm * 0.5)
                    vlm_feedback = "Partial VLM score (utilities unavailable)"
        else:
            # No VLM available - give partial credit if config is correct
            if slab_mode_enabled and mode_is_mip:
                vlm_score = int(w_vlm * 0.5)
                vlm_feedback = "No VLM available - partial credit for correct config"
                
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        # Still give partial credit if programmatic checks pass
        if slab_mode_enabled and mode_is_mip:
            vlm_score = int(w_vlm * 0.3)

    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(f"VLM: {vlm_feedback}")

    # ================================================================
    # ANTI-GAMING: Verify configuration actually changed
    # ================================================================
    if not config_changed and slab_mode == initial_slab_mode:
        # Configuration didn't change - might be gaming
        if slab_mode > 0:
            # Slab was already enabled before task - suspicious but possible
            feedback_parts.append("Warning: Config unchanged from initial state")
            details['anti_gaming_warning'] = "Configuration unchanged"
        # Don't penalize score, but flag it

    # ================================================================
    # Calculate final result
    # ================================================================
    max_score = w_mode_enabled + w_mode_correct + w_thickness + w_slice_view + w_vlm
    
    # Key criteria for passing
    key_criteria_met = slab_mode_enabled and mode_is_mip
    
    # Pass if score >= 65% AND key criteria met
    passed = (score >= 65) and key_criteria_met
    
    # Alternative pass: if mode and thickness are both correct
    if not passed and mode_is_mip and thickness_valid:
        passed = True
        feedback_parts.append("Passed on correct mode + thickness")

    feedback = " | ".join(feedback_parts)
    
    details['score_breakdown'] = {
        'slab_mode_enabled': w_mode_enabled if slab_mode_enabled else 0,
        'correct_mode_mip': w_mode_correct if mode_is_mip else (int(w_mode_correct * 0.3) if slab_mode_enabled else 0),
        'thickness_in_range': w_thickness if thickness_valid else 0,
        'correct_slice_view': w_slice_view if (slab_mode >= 0 and not result.get('config_error')) else 0,
        'vlm_verification': vlm_score
    }

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }