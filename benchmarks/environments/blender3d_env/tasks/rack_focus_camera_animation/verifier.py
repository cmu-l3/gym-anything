#!/usr/bin/env python3
"""
Verifier for Rack Focus Camera Animation task.

SCORING CRITERIA:
1. Blend file saved & modified (10 pts)
2. DOF Enabled on Camera (10 pts)
3. Shallow F-Stop (1.0 - 2.8) (10 pts)
4. Animation: Keyframe at Frame 1 (~4m) (15 pts)
5. Animation: Keyframe at Frame 60 (~12m) (15 pts)
6. Frame Range 1-60 set (10 pts)
7. Render Frame 1 exists & created during task (10 pts)
8. Render Frame 60 exists & created during task (10 pts)
9. VLM: Visual confirmation of focus shift (10 pts)

Pass Threshold: 70/100
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rack_focus(traj, env_info, task_info):
    """
    Verify the rack focus task using programmatic checks and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    focus_near = metadata.get('focus_near', 4.0)
    focus_far = metadata.get('focus_far', 12.0)
    
    # 1. Fetch Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Parse Data
    blend_info = result_data.get('blend_file', {})
    scene_data = result_data.get('scene_analysis', {})
    cam_data = scene_data.get('camera', {})
    frame01_info = result_data.get('frame01', {})
    frame60_info = result_data.get('frame60', {})
    
    # CRITERION 1: Blend File Saved (10 pts)
    if blend_info.get('exists') and blend_info.get('created_during_task'):
        score += 10
        feedback.append("✅ Blend file saved")
    elif blend_info.get('exists'):
        score += 5
        feedback.append("⚠️ Blend file exists but old timestamp")
    else:
        feedback.append("❌ Blend file not saved")

    # CRITERION 2: DOF Enabled (10 pts)
    if cam_data.get('found') and cam_data.get('dof_enabled'):
        score += 10
        feedback.append("✅ DOF Enabled")
    else:
        feedback.append("❌ DOF Not Enabled")

    # CRITERION 3: Shallow F-Stop (10 pts)
    fstop = cam_data.get('fstop', 100.0)
    if 0.5 <= fstop <= 3.5: # Loose tolerance around 1.0-2.8
        score += 10
        feedback.append(f"✅ F-Stop shallow ({fstop:.1f})")
    else:
        feedback.append(f"❌ F-Stop too high or invalid ({fstop:.1f})")

    # CRITERION 4 & 5: Animation Keyframes (30 pts total)
    keyframes = cam_data.get('keyframes', [])
    focus_at_1 = cam_data.get('focus_at_1', -1)
    focus_at_60 = cam_data.get('focus_at_60', -1)
    
    # Check Frame 1 Focus (Near ~4m)
    near_ok = abs(focus_at_1 - focus_near) < 3.0
    if near_ok:
        score += 15
        feedback.append(f"✅ Frame 1 Focus Correct ({focus_at_1:.2f}m)")
    else:
        feedback.append(f"❌ Frame 1 Focus Incorrect ({focus_at_1:.2f}m, expected ~{focus_near}m)")

    # Check Frame 60 Focus (Far ~12m)
    far_ok = abs(focus_at_60 - focus_far) < 3.0
    if far_ok:
        score += 15
        feedback.append(f"✅ Frame 60 Focus Correct ({focus_at_60:.2f}m)")
    else:
        feedback.append(f"❌ Frame 60 Focus Incorrect ({focus_at_60:.2f}m, expected ~{focus_far}m)")
    
    # Check keyframe existence
    has_keys = len(keyframes) >= 2
    if not has_keys:
        feedback.append("⚠️ Missing explicit keyframes in analysis")

    # CRITERION 6: Frame Range (10 pts)
    start = scene_data.get('frame_start')
    end = scene_data.get('frame_end')
    if start == 1 and end == 60:
        score += 10
        feedback.append("✅ Frame range 1-60 set")
    else:
        feedback.append(f"❌ Frame range incorrect ({start}-{end})")

    # CRITERION 7 & 8: Renders Exist (20 pts)
    renders_ok = False
    if frame01_info.get('exists') and frame01_info.get('size_bytes', 0) > 1000:
        score += 10
        feedback.append("✅ Frame 01 Rendered")
        renders_ok = True
    else:
        feedback.append("❌ Frame 01 missing")
        
    if frame60_info.get('exists') and frame60_info.get('size_bytes', 0) > 1000:
        score += 10
        feedback.append("✅ Frame 60 Rendered")
        renders_ok = renders_ok and True
    else:
        feedback.append("❌ Frame 60 missing")
        renders_ok = False

    # CRITERION 9: VLM Verification (10 pts)
    # Only run if renders exist and we have the tool
    if renders_ok and query_vlm:
        # Fetch images
        try:
            temp_img1 = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
            temp_img2 = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
            
            copy_from_env("/home/ga/BlenderProjects/rack_focus_frame01.png", temp_img1)
            copy_from_env("/home/ga/BlenderProjects/rack_focus_frame60.png", temp_img2)
            
            prompt = """
            Compare these two rendered frames from a rack focus animation.
            Image 1 (First): Should have the FOREGROUND object (Red Cone) in sharp focus and background blurry.
            Image 2 (Second): Should have the BACKGROUND object (Blue Torus) in sharp focus and foreground blurry.
            
            Does the focus shift visibly between these two images as described?
            Answer JSON: {"focus_shift_visible": true/false}
            """
            
            vlm_res = query_vlm(prompt=prompt, images=[temp_img1, temp_img2])
            
            # Clean up images
            if os.path.exists(temp_img1): os.unlink(temp_img1)
            if os.path.exists(temp_img2): os.unlink(temp_img2)
            
            if vlm_res.get('parsed', {}).get('focus_shift_visible'):
                score += 10
                feedback.append("✅ VLM Confirms focus shift")
            else:
                feedback.append("⚠️ VLM could not confirm visual focus shift")
                
        except Exception as e:
            feedback.append(f"⚠️ VLM check failed: {e}")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }