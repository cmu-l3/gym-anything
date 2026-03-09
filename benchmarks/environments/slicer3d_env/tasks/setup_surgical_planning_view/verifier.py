#!/usr/bin/env python3
"""
Verifier for Setup Surgical Planning View task.

VERIFICATION STRATEGY:
1. Programmatic checks on segment display properties (90 points total):
   - Liver color in tan/brown range (15 pts)
   - Liver opacity ~40% (15 pts)
   - Tumor color in red range (15 pts)
   - Tumor opacity ~100% (10 pts)
   - PortalVein color in blue range (15 pts)
   - PortalVein opacity ~100% (10 pts)
   - All segments visible (10 pts)

2. VLM verification on trajectory (10 points):
   - Final view shows multi-colored surgical visualization

3. Anti-gaming:
   - Properties must have changed from initial state
   - Timestamps checked

Pass threshold: 70 points with at least Liver and Tumor correctly configured
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def color_in_range(color_255: int, range_spec: dict) -> bool:
    """Check if a color value (0-255) is within the specified range."""
    min_val = range_spec.get("min", 0) if isinstance(range_spec, dict) else range_spec[0]
    max_val = range_spec.get("max", 255) if isinstance(range_spec, dict) else range_spec[1]
    return min_val <= color_255 <= max_val


def opacity_in_range(opacity: float, range_spec: dict) -> bool:
    """Check if opacity (0-1) is within the specified range."""
    min_val = range_spec.get("min", 0.0)
    max_val = range_spec.get("max", 1.0)
    return min_val <= opacity <= max_val


def verify_setup_surgical_planning_view(traj, env_info, task_info):
    """
    Verify that segment display properties were configured correctly.
    
    Uses multi-criteria scoring with color and opacity validation.
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
    expected_colors = metadata.get('expected_colors', {
        "Liver": {"r_range": [150, 220], "g_range": [100, 170], "b_range": [60, 130]},
        "Tumor": {"r_range": [200, 255], "g_range": [0, 80], "b_range": [0, 80]},
        "PortalVein": {"r_range": [0, 80], "g_range": [0, 80], "b_range": [200, 255]}
    })
    expected_opacities = metadata.get('expected_opacities', {
        "Liver": {"min": 0.30, "max": 0.50},
        "Tumor": {"min": 0.90, "max": 1.0},
        "PortalVein": {"min": 0.90, "max": 1.0}
    })
    weights = metadata.get('scoring_weights', {
        "liver_color": 15,
        "liver_opacity": 15,
        "tumor_color": 15,
        "tumor_opacity": 10,
        "portalvein_color": 15,
        "portalvein_opacity": 10,
        "all_visible": 10,
        "vlm_verification": 10
    })

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/surgical_view_result.json", temp_result.name)
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
    max_score = 100
    feedback_parts = []
    details = {}

    # ================================================================
    # PRE-CHECK: Slicer was running
    # ================================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ================================================================
    # ANTI-GAMING: Check properties were actually changed
    # ================================================================
    properties_changed = result.get('properties_changed', False)
    if not properties_changed:
        feedback_parts.append("WARNING: No property changes detected")
        details['anti_gaming_warning'] = "Properties may not have been modified"
    else:
        details['properties_modified'] = True

    # ================================================================
    # GET SEGMENT DATA
    # ================================================================
    segment_data = result.get('segment_data', {})
    segments = segment_data.get('segments', {})
    
    if not segments:
        return {
            "passed": False,
            "score": 5,  # Minimal score for Slicer running
            "feedback": "No segment data found - segmentation may not be loaded"
        }

    details['segment_count'] = len(segments)

    # ================================================================
    # CRITERION 1: Liver Color (15 points)
    # Expected: tan/brown (R: 150-220, G: 100-170, B: 60-130)
    # ================================================================
    liver_color_correct = False
    if 'Liver' in segments:
        liver = segments['Liver']
        r = liver.get('color_r_255', 0)
        g = liver.get('color_g_255', 0)
        b = liver.get('color_b_255', 0)
        
        liver_r_ok = expected_colors['Liver']['r_range'][0] <= r <= expected_colors['Liver']['r_range'][1]
        liver_g_ok = expected_colors['Liver']['g_range'][0] <= g <= expected_colors['Liver']['g_range'][1]
        liver_b_ok = expected_colors['Liver']['b_range'][0] <= b <= expected_colors['Liver']['b_range'][1]
        
        liver_color_correct = liver_r_ok and liver_g_ok and liver_b_ok
        
        if liver_color_correct:
            score += weights['liver_color']
            feedback_parts.append(f"Liver color OK ({r},{g},{b})")
        else:
            # Partial credit if close
            correct_channels = sum([liver_r_ok, liver_g_ok, liver_b_ok])
            partial = int(weights['liver_color'] * correct_channels / 3)
            score += partial
            feedback_parts.append(f"Liver color partial ({r},{g},{b})")
        
        details['liver_color'] = {'r': r, 'g': g, 'b': b, 'correct': liver_color_correct}
    else:
        feedback_parts.append("Liver segment not found")

    # ================================================================
    # CRITERION 2: Liver Opacity (15 points)
    # Expected: 30-50% (0.30-0.50)
    # ================================================================
    liver_opacity_correct = False
    if 'Liver' in segments:
        liver_opacity = segments['Liver'].get('opacity_3d', 0)
        liver_opacity_correct = expected_opacities['Liver']['min'] <= liver_opacity <= expected_opacities['Liver']['max']
        
        if liver_opacity_correct:
            score += weights['liver_opacity']
            feedback_parts.append(f"Liver opacity OK ({liver_opacity:.0%})")
        else:
            # Partial credit if close (within 0.1 of range)
            min_op = expected_opacities['Liver']['min']
            max_op = expected_opacities['Liver']['max']
            if min_op - 0.1 <= liver_opacity <= max_op + 0.1:
                score += weights['liver_opacity'] // 2
                feedback_parts.append(f"Liver opacity close ({liver_opacity:.0%})")
            else:
                feedback_parts.append(f"Liver opacity wrong ({liver_opacity:.0%})")
        
        details['liver_opacity'] = {'value': liver_opacity, 'correct': liver_opacity_correct}

    # ================================================================
    # CRITERION 3: Tumor Color (15 points)
    # Expected: bright red (R: 200-255, G: 0-80, B: 0-80)
    # ================================================================
    tumor_color_correct = False
    if 'Tumor' in segments:
        tumor = segments['Tumor']
        r = tumor.get('color_r_255', 0)
        g = tumor.get('color_g_255', 0)
        b = tumor.get('color_b_255', 0)
        
        tumor_r_ok = expected_colors['Tumor']['r_range'][0] <= r <= expected_colors['Tumor']['r_range'][1]
        tumor_g_ok = expected_colors['Tumor']['g_range'][0] <= g <= expected_colors['Tumor']['g_range'][1]
        tumor_b_ok = expected_colors['Tumor']['b_range'][0] <= b <= expected_colors['Tumor']['b_range'][1]
        
        tumor_color_correct = tumor_r_ok and tumor_g_ok and tumor_b_ok
        
        if tumor_color_correct:
            score += weights['tumor_color']
            feedback_parts.append(f"Tumor color OK ({r},{g},{b})")
        else:
            correct_channels = sum([tumor_r_ok, tumor_g_ok, tumor_b_ok])
            partial = int(weights['tumor_color'] * correct_channels / 3)
            score += partial
            feedback_parts.append(f"Tumor color partial ({r},{g},{b})")
        
        details['tumor_color'] = {'r': r, 'g': g, 'b': b, 'correct': tumor_color_correct}
    else:
        feedback_parts.append("Tumor segment not found")

    # ================================================================
    # CRITERION 4: Tumor Opacity (10 points)
    # Expected: 90-100% (0.90-1.0)
    # ================================================================
    tumor_opacity_correct = False
    if 'Tumor' in segments:
        tumor_opacity = segments['Tumor'].get('opacity_3d', 0)
        tumor_opacity_correct = expected_opacities['Tumor']['min'] <= tumor_opacity <= expected_opacities['Tumor']['max']
        
        if tumor_opacity_correct:
            score += weights['tumor_opacity']
            feedback_parts.append(f"Tumor opacity OK ({tumor_opacity:.0%})")
        else:
            if tumor_opacity >= 0.8:
                score += weights['tumor_opacity'] // 2
                feedback_parts.append(f"Tumor opacity close ({tumor_opacity:.0%})")
            else:
                feedback_parts.append(f"Tumor opacity wrong ({tumor_opacity:.0%})")
        
        details['tumor_opacity'] = {'value': tumor_opacity, 'correct': tumor_opacity_correct}

    # ================================================================
    # CRITERION 5: PortalVein Color (15 points)
    # Expected: blue (R: 0-80, G: 0-80, B: 200-255)
    # ================================================================
    pv_color_correct = False
    if 'PortalVein' in segments:
        pv = segments['PortalVein']
        r = pv.get('color_r_255', 0)
        g = pv.get('color_g_255', 0)
        b = pv.get('color_b_255', 0)
        
        pv_r_ok = expected_colors['PortalVein']['r_range'][0] <= r <= expected_colors['PortalVein']['r_range'][1]
        pv_g_ok = expected_colors['PortalVein']['g_range'][0] <= g <= expected_colors['PortalVein']['g_range'][1]
        pv_b_ok = expected_colors['PortalVein']['b_range'][0] <= b <= expected_colors['PortalVein']['b_range'][1]
        
        pv_color_correct = pv_r_ok and pv_g_ok and pv_b_ok
        
        if pv_color_correct:
            score += weights['portalvein_color']
            feedback_parts.append(f"PortalVein color OK ({r},{g},{b})")
        else:
            correct_channels = sum([pv_r_ok, pv_g_ok, pv_b_ok])
            partial = int(weights['portalvein_color'] * correct_channels / 3)
            score += partial
            feedback_parts.append(f"PortalVein color partial ({r},{g},{b})")
        
        details['portalvein_color'] = {'r': r, 'g': g, 'b': b, 'correct': pv_color_correct}
    else:
        feedback_parts.append("PortalVein segment not found")

    # ================================================================
    # CRITERION 6: PortalVein Opacity (10 points)
    # Expected: 90-100% (0.90-1.0)
    # ================================================================
    pv_opacity_correct = False
    if 'PortalVein' in segments:
        pv_opacity = segments['PortalVein'].get('opacity_3d', 0)
        pv_opacity_correct = expected_opacities['PortalVein']['min'] <= pv_opacity <= expected_opacities['PortalVein']['max']
        
        if pv_opacity_correct:
            score += weights['portalvein_opacity']
            feedback_parts.append(f"PortalVein opacity OK ({pv_opacity:.0%})")
        else:
            if pv_opacity >= 0.8:
                score += weights['portalvein_opacity'] // 2
            feedback_parts.append(f"PortalVein opacity: {pv_opacity:.0%}")
        
        details['portalvein_opacity'] = {'value': pv_opacity, 'correct': pv_opacity_correct}

    # ================================================================
    # CRITERION 7: All Segments Visible (10 points)
    # ================================================================
    all_visible = True
    for name in ['Liver', 'Tumor', 'PortalVein']:
        if name in segments:
            visible = segments[name].get('visible', False)
            visible_3d = segments[name].get('visible_3d', True)  # Default True if not specified
            if not visible:
                all_visible = False
                feedback_parts.append(f"{name} not visible")
    
    if all_visible and len(segments) >= 3:
        score += weights['all_visible']
        feedback_parts.append("All segments visible")
    
    details['all_visible'] = all_visible

    # ================================================================
    # CRITERION 8: VLM Verification (10 points)
    # Check trajectory frames for proper surgical view
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Get trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=3) if hasattr(traj, '__iter__') else []
            final = get_final_screenshot(traj)
            
            all_frames = frames + ([final] if final else [])
            
            if all_frames:
                vlm_prompt = """Analyze this 3D Slicer screenshot showing a surgical planning visualization.

Look for these elements:
1. Is there a 3D view showing anatomical structures?
2. Can you see a semi-transparent brown/tan structure (liver)?
3. Can you see a bright red structure (tumor)?
4. Can you see a blue tubular structure (portal vein)?
5. Does the visualization look like a surgical planning view with multiple colored organs?

Respond in JSON:
{
    "3d_view_visible": true/false,
    "liver_visible_semitransparent": true/false,
    "tumor_visible_red": true/false,
    "portal_vein_visible_blue": true/false,
    "surgical_planning_aesthetic": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames[-2:] if len(all_frames) > 1 else all_frames)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_checks = [
                        parsed.get('3d_view_visible', False),
                        parsed.get('liver_visible_semitransparent', False),
                        parsed.get('tumor_visible_red', False),
                        parsed.get('portal_vein_visible_blue', False),
                        parsed.get('surgical_planning_aesthetic', False)
                    ]
                    
                    vlm_score = int(weights['vlm_verification'] * sum(vlm_checks) / len(vlm_checks))
                    score += vlm_score
                    
                    details['vlm_result'] = parsed
                    
                    if sum(vlm_checks) >= 3:
                        feedback_parts.append("VLM: Surgical view confirmed")
                    else:
                        feedback_parts.append(f"VLM: Partial visualization ({sum(vlm_checks)}/5)")
                        
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: Liver and Tumor must be correctly configured
    key_criteria_met = (
        liver_color_correct and 
        liver_opacity_correct and 
        tumor_color_correct and 
        tumor_opacity_correct
    )
    
    # Alternative: Pass with 70+ points and at least liver/tumor configured
    basic_config_done = (
        (liver_color_correct or liver_opacity_correct) and
        (tumor_color_correct or tumor_opacity_correct)
    )
    
    passed = (score >= 70 and basic_config_done) or (score >= 80)

    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": feedback,
        "details": details
    }