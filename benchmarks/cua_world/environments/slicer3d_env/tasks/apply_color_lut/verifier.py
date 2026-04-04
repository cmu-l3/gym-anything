#!/usr/bin/env python3
"""
Verifier for apply_color_lut task.

VERIFICATION STRATEGY (Multi-Signal):
1. Volume loaded (15 points) - Data was loaded into Slicer
2. Display node exists (15 points) - Volume has display settings
3. Colormap changed from initial (35 points) - THE KEY CHECK
4. Valid color LUT applied (20 points) - Not a grayscale variant
5. VLM visual verification (15 points) - Screenshot shows colored brain

Anti-gaming measures:
- Compare initial vs final colormap
- Check for known grayscale names
- VLM trajectory verification to ensure work was done
- Screenshot color analysis

Pass threshold: 60 points with colormap_changed criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Known grayscale colormap names (should NOT be selected)
GRAYSCALE_COLORMAPS = [
    "Grey", "Gray", "Grayscale", "Greyscale", 
    "White", "Black", "GrayWhite", "WhiteGray"
]

# Known valid color LUT names
VALID_COLOR_LUTS = [
    "Ocean", "Cool", "Warm", "Hot", "Cold",
    "Rainbow", "fMRI", "fMRIPA", "Spectrum",
    "Red", "Green", "Blue", "Yellow", "Cyan", "Magenta",
    "PET-Heat", "PET-Rainbow", "Labels", "FreeSurfer",
    "Muscles", "Bones", "Skin", "Tissue"
]


def is_grayscale_colormap(colormap_name):
    """Check if a colormap name is a grayscale variant."""
    if not colormap_name:
        return True
    name_lower = colormap_name.lower()
    for gs in GRAYSCALE_COLORMAPS:
        if gs.lower() in name_lower or name_lower in gs.lower():
            return True
    return False


def is_valid_color_lut(colormap_name):
    """Check if a colormap name is a known valid color LUT."""
    if not colormap_name:
        return False
    name_lower = colormap_name.lower()
    for lut in VALID_COLOR_LUTS:
        if lut.lower() in name_lower:
            return True
    # If it's not grayscale, consider it potentially valid
    return not is_grayscale_colormap(colormap_name)


def verify_apply_color_lut(traj, env_info, task_info):
    """
    Verify that a color lookup table was applied to the volume.
    
    Uses multi-criteria scoring with anti-gaming measures.
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
    weights = metadata.get('scoring_weights', {})
    w_volume = weights.get('volume_loaded', 15)
    w_display = weights.get('display_node_exists', 15)
    w_changed = weights.get('colormap_changed', 35)
    w_valid = weights.get('valid_color_lut', 20)
    w_vlm = weights.get('vlm_color_visible', 15)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/color_lut_task_result.json", temp_result.name)
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
    slicer_running = result.get('slicer_was_running', False)
    if not slicer_running:
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task completion"
        }

    # ============================================================
    # CRITERION 1: Volume loaded (15 points)
    # ============================================================
    volume_loaded = result.get('volume_loaded', False)
    if volume_loaded:
        score += w_volume
        feedback_parts.append("Volume loaded")
        details['volume_loaded'] = True
    else:
        feedback_parts.append("Volume NOT loaded")
        details['volume_loaded'] = False

    # ============================================================
    # CRITERION 2: Display node exists (15 points)
    # ============================================================
    display_node_exists = result.get('display_node_exists', False)
    if display_node_exists:
        score += w_display
        feedback_parts.append("Display node exists")
        details['display_node_exists'] = True
    else:
        feedback_parts.append("Display node NOT found")
        details['display_node_exists'] = False

    # ============================================================
    # CRITERION 3: Colormap changed from initial (35 points)
    # This is the KEY criterion
    # ============================================================
    initial_colormap = result.get('initial_colormap', 'Grey')
    current_colormap = result.get('current_colormap', '')
    colormap_changed = result.get('colormap_changed', False)
    
    details['initial_colormap'] = initial_colormap
    details['current_colormap'] = current_colormap

    # Double-check: verify colormap actually changed
    if current_colormap and current_colormap != initial_colormap:
        colormap_changed = True
    
    if colormap_changed and current_colormap:
        score += w_changed
        feedback_parts.append(f"Colormap changed: '{initial_colormap}' → '{current_colormap}'")
        details['colormap_changed'] = True
    else:
        feedback_parts.append(f"Colormap NOT changed (still '{initial_colormap}')")
        details['colormap_changed'] = False

    # ============================================================
    # CRITERION 4: Valid color LUT applied (20 points)
    # Must be a color LUT, not grayscale
    # ============================================================
    is_grayscale = result.get('is_grayscale', True)
    valid_color = result.get('valid_color_lut', False)
    
    # Re-verify using our logic
    if current_colormap:
        is_grayscale = is_grayscale_colormap(current_colormap)
        valid_color = is_valid_color_lut(current_colormap)

    details['is_grayscale'] = is_grayscale
    details['valid_color_lut'] = valid_color

    if valid_color and not is_grayscale:
        score += w_valid
        feedback_parts.append(f"Valid color LUT: '{current_colormap}'")
    elif colormap_changed and not is_grayscale:
        # Partial credit if changed but not a known LUT
        score += w_valid // 2
        feedback_parts.append(f"Unknown but non-grayscale LUT: '{current_colormap}'")
    else:
        feedback_parts.append("Still using grayscale colormap")

    # ============================================================
    # CRITERION 5: VLM / Screenshot verification (15 points)
    # Check if the screenshot shows colored content
    # ============================================================
    screenshot_has_color = result.get('screenshot_has_color', False)
    screenshot_exists = result.get('screenshot_exists', False)
    
    # Also try VLM verification if available
    vlm_verified = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames to verify workflow
            frames = sample_trajectory_frames(traj, n=3)
            final_screenshot = get_final_screenshot(traj)
            
            if final_screenshot:
                vlm_prompt = """Analyze this screenshot from 3D Slicer medical imaging software.

Look at the brain MRI scan displayed in the slice views (axial, sagittal, coronal panels).

Determine:
1. Is the brain image displayed in COLORS (blues, oranges, reds, rainbows, etc.)?
2. Or is it displayed in GRAYSCALE (only black, white, and gray shades)?

A color lookup table would show the brain in various colors based on intensity values.
Grayscale would show only shades of gray.

Respond in JSON format:
{
    "is_colored": true/false,
    "observed_colors": "list colors you see in the brain image",
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""
                vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('is_colored', False):
                        vlm_verified = True
                        details['vlm_colors'] = parsed.get('observed_colors', '')
                        logger.info(f"VLM verified colored display: {parsed}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    details['screenshot_has_color'] = screenshot_has_color
    details['vlm_verified'] = vlm_verified

    if vlm_verified:
        score += w_vlm
        feedback_parts.append("VLM confirms colored display")
    elif screenshot_has_color:
        score += w_vlm
        feedback_parts.append("Screenshot analysis confirms colors")
    elif screenshot_exists:
        # Partial credit for having a screenshot
        score += w_vlm // 3
        feedback_parts.append("Screenshot captured (color unconfirmed)")
    else:
        feedback_parts.append("No visual verification")

    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Must have colormap changed AND not be grayscale
    key_criteria_met = colormap_changed and not is_grayscale
    passed = score >= 60 and key_criteria_met

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }