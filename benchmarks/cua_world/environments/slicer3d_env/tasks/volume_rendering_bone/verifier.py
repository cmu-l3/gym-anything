#!/usr/bin/env python3
"""
Verifier for Volume Rendering Bone task in 3D Slicer.

VERIFICATION STRATEGY:
1. Screenshot exists at expected path (20 points)
2. Screenshot has valid size (10 points) - prevents empty/corrupt files
3. Screenshot was created during task (10 points) - anti-gaming timestamp check
4. Volume rendering node active in Slicer (15 points)
5. Preset was applied (10 points)
6. VLM: Bones visible in screenshot (20 points) - trajectory-based
7. VLM: Spine clearly shown (15 points) - trajectory-based

Pass threshold: 65 points with (screenshot exists AND (VR active OR bones visible))
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_volume_rendering_bone(traj, env_info, task_info):
    """
    Verify that bone volume rendering was applied and screenshot captured.
    
    Uses multiple independent signals to prevent gaming:
    - File-based checks (existence, size, timestamp)
    - Slicer state checks (VR node, preset)
    - VLM visual verification (trajectory frames, not just final)
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
    expected_screenshot = metadata.get('expected_screenshot_path', 
                                       '/home/ga/Documents/SlicerData/Screenshots/bone_rendering.png')
    min_size_kb = metadata.get('min_screenshot_size_kb', 50)
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('screenshot_exists', 20)
    w_valid_size = weights.get('screenshot_valid_size', 10)
    w_recent = weights.get('screenshot_recent', 10)
    w_vr_active = weights.get('vr_node_active', 15)
    w_preset = weights.get('preset_applied', 10)
    w_bones_vlm = weights.get('bones_visible_vlm', 20)
    w_spine_vlm = weights.get('spine_clear_vlm', 15)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
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
    
    details['export_result'] = result
    
    # ================================================================
    # CRITERION 1: Screenshot Exists (20 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    
    if screenshot_exists:
        score += w_exists
        feedback_parts.append("Screenshot exists")
        details['screenshot_exists'] = True
    else:
        feedback_parts.append("Screenshot NOT found at expected path")
        details['screenshot_exists'] = False
        # Early return - nothing else to verify without screenshot
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Screenshot Valid Size (10 points)
    # ================================================================
    screenshot_size_kb = result.get('screenshot_size_kb', 0)
    details['screenshot_size_kb'] = screenshot_size_kb
    
    if screenshot_size_kb >= min_size_kb:
        score += w_valid_size
        feedback_parts.append(f"Valid size ({screenshot_size_kb}KB)")
    elif screenshot_size_kb >= min_size_kb / 2:
        score += w_valid_size // 2
        feedback_parts.append(f"Small size ({screenshot_size_kb}KB)")
    else:
        feedback_parts.append(f"Screenshot too small ({screenshot_size_kb}KB)")
    
    # ================================================================
    # CRITERION 3: Screenshot Created During Task (10 points)
    # Anti-gaming: verify file wasn't pre-existing
    # ================================================================
    created_during_task = result.get('screenshot_created_during_task', False)
    details['created_during_task'] = created_during_task
    
    if created_during_task:
        score += w_recent
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("WARNING: Screenshot may be pre-existing")
    
    # ================================================================
    # CRITERION 4: Volume Rendering Active (15 points)
    # ================================================================
    vr_active = result.get('volume_rendering_active', False)
    details['volume_rendering_active'] = vr_active
    
    if vr_active:
        score += w_vr_active
        feedback_parts.append("Volume rendering active")
    else:
        # Partial credit if Slicer was running
        if result.get('slicer_was_running', False):
            score += w_vr_active // 3
            feedback_parts.append("Slicer running (VR state unknown)")
        else:
            feedback_parts.append("Volume rendering not detected")
    
    # ================================================================
    # CRITERION 5: Preset Applied (10 points)
    # ================================================================
    preset_name = result.get('preset_name', 'none')
    details['preset_name'] = preset_name
    
    # Check if a bone-related preset was used
    bone_presets = ['ct-bone', 'ct-bones', 'bone', 'ct-cardiac', 'ct-aaa', 'ct-fat']
    preset_lower = preset_name.lower() if preset_name else ''
    
    if preset_name and preset_name != 'none':
        if any(bp in preset_lower for bp in bone_presets):
            score += w_preset
            feedback_parts.append(f"Bone preset: {preset_name}")
        else:
            score += w_preset // 2
            feedback_parts.append(f"Preset applied: {preset_name}")
    else:
        feedback_parts.append("No preset detected")
    
    # ================================================================
    # CRITERION 6 & 7: VLM Verification (35 points total)
    # Uses TRAJECTORY frames, not just final screenshot
    # ================================================================
    vlm_score = 0
    vlm_feedback = []
    
    try:
        # Import VLM utilities from framework
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Sample trajectory frames for process verification
        trajectory_frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        # Also try to get the user's saved screenshot
        temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        user_screenshot = None
        try:
            copy_from_env("/tmp/bone_rendering_output.png", temp_output.name)
            if os.path.exists(temp_output.name) and os.path.getsize(temp_output.name) > 1000:
                user_screenshot = temp_output.name
        except Exception:
            pass
        
        # VLM Query 1: Check trajectory for volume rendering workflow
        if trajectory_frames:
            process_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.
The user should have:
1. Navigated to Volume Rendering module
2. Enabled 3D volume rendering
3. Applied a bone visualization preset
4. Captured a screenshot of 3D bone rendering

Look for:
- Volume Rendering module panel visible at any point
- 3D view showing volumetric rendering (not just 2D slices)
- Bone/skeletal structures visible in 3D
- Evidence of preset selection or rendering controls

Respond in JSON:
{
    "vr_module_accessed": true/false,
    "3d_rendering_visible": true/false,
    "bones_visible": true/false,
    "workflow_evidence": "brief description",
    "confidence": "low/medium/high"
}"""
            
            process_result = query_vlm(
                prompt=process_prompt,
                images=trajectory_frames
            )
            
            if process_result and process_result.get('success'):
                parsed = process_result.get('parsed', {})
                details['vlm_process'] = parsed
                
                if parsed.get('bones_visible', False):
                    vlm_score += w_bones_vlm
                    vlm_feedback.append("VLM: Bones visible in trajectory")
                elif parsed.get('3d_rendering_visible', False):
                    vlm_score += w_bones_vlm // 2
                    vlm_feedback.append("VLM: 3D rendering visible")
        
        # VLM Query 2: Analyze the saved screenshot specifically
        screenshot_to_check = user_screenshot or (final_screenshot if final_screenshot else None)
        
        if screenshot_to_check:
            content_prompt = """Analyze this screenshot from 3D Slicer.

Determine if this shows a bone volume rendering:
1. Is this a 3D volumetric rendering (not 2D slices)?
2. Are skeletal structures (bones, spine, vertebrae) visible?
3. Is the spine clearly shown and recognizable?
4. Does it use bone-appropriate coloring (bright/white bones against dark)?

Respond in JSON:
{
    "is_volume_rendering": true/false,
    "bones_visible": true/false,
    "spine_recognizable": true/false,
    "bone_coloring": true/false,
    "description": "what you see",
    "confidence": "low/medium/high"
}"""
            
            content_result = query_vlm(
                prompt=content_prompt,
                image=screenshot_to_check
            )
            
            if content_result and content_result.get('success'):
                parsed = content_result.get('parsed', {})
                details['vlm_content'] = parsed
                
                # Award points for spine visibility
                if parsed.get('spine_recognizable', False):
                    vlm_score += w_spine_vlm
                    vlm_feedback.append("VLM: Spine clearly visible")
                elif parsed.get('bones_visible', False) and vlm_score < w_bones_vlm:
                    vlm_score += w_bones_vlm // 2
                    vlm_feedback.append("VLM: Some bone structures visible")
        
        # Clean up temp file
        if user_screenshot and os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
            
    except ImportError:
        vlm_feedback.append("VLM not available")
        details['vlm_error'] = "VLM module not available"
        # Give partial credit based on other evidence
        if screenshot_size_kb > 100 and created_during_task:
            vlm_score += (w_bones_vlm + w_spine_vlm) // 3
            vlm_feedback.append("Heuristic: Large screenshot suggests content")
    except Exception as e:
        vlm_feedback.append(f"VLM error: {str(e)[:50]}")
        details['vlm_error'] = str(e)
    
    score += vlm_score
    feedback_parts.extend(vlm_feedback)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_exists + w_valid_size + w_recent + w_vr_active + w_preset + w_bones_vlm + w_spine_vlm
    
    # Pass criteria: 65% AND (screenshot exists AND (VR active OR bones visible via VLM))
    key_criteria_met = (
        screenshot_exists and 
        created_during_task and
        (vr_active or vlm_score >= w_bones_vlm)
    )
    
    passed = score >= 65 and key_criteria_met
    
    details['score_breakdown'] = {
        'screenshot_exists': w_exists if screenshot_exists else 0,
        'valid_size': w_valid_size if screenshot_size_kb >= min_size_kb else 0,
        'recent': w_recent if created_during_task else 0,
        'vr_active': w_vr_active if vr_active else 0,
        'preset': w_preset if preset_name and preset_name != 'none' else 0,
        'vlm_total': vlm_score
    }
    details['max_score'] = max_score
    details['key_criteria_met'] = key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }