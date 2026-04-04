#!/usr/bin/env python3
"""
Verifier for clip_3d_rendering task.

VERIFICATION STRATEGY (Multi-Signal):

Programmatic checks (85 points):
1. Volume loaded (15 pts) - A volume node exists in the scene
2. Volume rendering active (20 pts) - VR display node visible
3. ROI node exists (15 pts) - An ROI is present for clipping
4. Clipping enabled (20 pts) - Crop/clipping is turned on
5. Meaningful clip (15 pts) - ROI bounds differ from volume bounds

File/Screenshot checks (10 points):
6. Screenshot saved (10 pts) - Output file exists and created during task

VLM verification (5 points):
7. Cutaway visible (5 pts) - Trajectory frames show 3D cutaway effect

Pass threshold: 70 points with volume_rendering_active AND clipping_enabled
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_clip_3d_rendering(traj, env_info, task_info):
    """
    Verify that a clipping plane was configured for 3D volume rendering.
    
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
    min_screenshot_size_kb = metadata.get('min_screenshot_size_kb', 100)
    
    weights = metadata.get('scoring_weights', {})
    w_volume = weights.get('volume_loaded', 15)
    w_vr_active = weights.get('volume_rendering_active', 20)
    w_roi_exists = weights.get('roi_node_exists', 15)
    w_clipping = weights.get('clipping_enabled', 20)
    w_meaningful = weights.get('meaningful_clip', 15)
    w_screenshot = weights.get('screenshot_saved', 10)
    w_vlm = weights.get('vlm_cutaway_visible', 5)

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
        copy_from_env("/tmp/clip_task_result.json", temp_result.name)
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

    # ================================================================
    # CRITERION 1: Volume loaded (15 points)
    # ================================================================
    volume_count = result.get('volume_count', 0)
    
    if volume_count > 0:
        score += w_volume
        feedback_parts.append(f"Volume loaded ({volume_count} node(s))")
        details['volume_loaded'] = True
    else:
        feedback_parts.append("No volume loaded")
        details['volume_loaded'] = False

    # ================================================================
    # CRITERION 2: Volume rendering active (20 points)
    # ================================================================
    vr_active = result.get('volume_rendering_active', False)
    
    if vr_active:
        score += w_vr_active
        feedback_parts.append("Volume rendering active")
        details['vr_active'] = True
    else:
        feedback_parts.append("Volume rendering NOT active")
        details['vr_active'] = False

    # ================================================================
    # CRITERION 3: ROI node exists (15 points)
    # ================================================================
    roi_count = result.get('roi_count', 0)
    
    if roi_count > 0:
        score += w_roi_exists
        feedback_parts.append(f"ROI node exists ({roi_count})")
        details['roi_exists'] = True
    else:
        feedback_parts.append("No ROI node found")
        details['roi_exists'] = False

    # ================================================================
    # CRITERION 4: Clipping enabled (20 points)
    # ================================================================
    clipping_enabled = result.get('clipping_enabled', False)
    
    if clipping_enabled:
        score += w_clipping
        feedback_parts.append("Clipping/cropping enabled")
        details['clipping_enabled'] = True
    else:
        feedback_parts.append("Clipping NOT enabled")
        details['clipping_enabled'] = False

    # ================================================================
    # CRITERION 5: Meaningful clip (15 points)
    # ROI bounds should differ from volume bounds (actual clipping done)
    # ================================================================
    roi_differs = result.get('roi_differs_from_volume', False)
    roi_ratio = result.get('roi_volume_ratio', 1.0)
    
    if roi_differs:
        score += w_meaningful
        feedback_parts.append(f"Meaningful clip (ROI ratio: {roi_ratio:.2f})")
        details['meaningful_clip'] = True
    elif roi_count > 0 and 0.4 < roi_ratio < 0.98:
        # Partial credit if ratio suggests some clipping
        score += int(w_meaningful * 0.7)
        feedback_parts.append(f"Partial clip detected (ratio: {roi_ratio:.2f})")
        details['meaningful_clip'] = 'partial'
    else:
        feedback_parts.append("No meaningful clip (ROI = full volume)")
        details['meaningful_clip'] = False

    # ================================================================
    # CRITERION 6: Screenshot saved (10 points)
    # Must be created DURING task (anti-gaming)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_bytes', 0)
    screenshot_created = result.get('screenshot_created_during_task', False)
    
    screenshot_size_kb = screenshot_size / 1024 if screenshot_size else 0
    
    if screenshot_exists and screenshot_created:
        if screenshot_size_kb >= min_screenshot_size_kb:
            score += w_screenshot
            feedback_parts.append(f"Screenshot saved ({screenshot_size_kb:.1f}KB)")
            details['screenshot_valid'] = True
        else:
            score += int(w_screenshot * 0.5)
            feedback_parts.append(f"Screenshot small ({screenshot_size_kb:.1f}KB)")
            details['screenshot_valid'] = 'small'
    elif screenshot_exists:
        # File exists but wasn't created during task - suspicious
        score += int(w_screenshot * 0.3)
        feedback_parts.append("Screenshot exists (may be pre-existing)")
        details['screenshot_valid'] = 'pre-existing'
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_valid'] = False

    # ================================================================
    # CRITERION 7: VLM verification of cutaway effect (5 points)
    # Uses trajectory frames to verify actual work was done
    # ================================================================
    vlm_score = 0
    vlm_feedback = "VLM check skipped"
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory (captures workflow progression)
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames and len(frames) >= 2:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.

The task was to create a clipped/cutaway 3D volume rendering of a brain MRI.

Look for evidence of:
1. A 3D volume rendering visible (volumetric brain with depth/shading)
2. A clipping plane or cutaway effect (part of the brain surface removed to show internal structures)
3. The progression shows the user actually performing the clipping operation

Respond in JSON:
{
    "volume_rendering_visible": true/false,
    "clipping_cutaway_visible": true/false,
    "shows_internal_structures": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                vr_visible = parsed.get('volume_rendering_visible', False)
                cutaway_visible = parsed.get('clipping_cutaway_visible', False)
                internal_visible = parsed.get('shows_internal_structures', False)
                confidence = parsed.get('confidence', 'low')
                
                # Award points based on VLM findings
                if cutaway_visible and internal_visible:
                    vlm_score = w_vlm
                    vlm_feedback = f"VLM confirms cutaway ({confidence} confidence)"
                elif vr_visible and cutaway_visible:
                    vlm_score = int(w_vlm * 0.8)
                    vlm_feedback = f"VLM sees VR with possible clip ({confidence})"
                elif vr_visible:
                    vlm_score = int(w_vlm * 0.4)
                    vlm_feedback = "VLM sees volume rendering (no clear cutaway)"
                else:
                    vlm_feedback = "VLM could not confirm 3D rendering"
            else:
                vlm_feedback = "VLM query failed"
                
    except ImportError:
        vlm_feedback = "VLM utilities not available"
        details['vlm_error'] = "import_error"
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        details['vlm_error'] = str(e)
    
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: must have volume rendering AND clipping enabled
    key_criteria_met = vr_active and clipping_enabled
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # If high score but missing key criteria, reduce confidence
    if score >= 70 and not key_criteria_met:
        feedback_parts.append("High score but missing key criteria (VR + clipping)")
    
    # Final feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary to details
    details['key_criteria_met'] = key_criteria_met
    details['final_score'] = score
    details['pass_threshold'] = 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }