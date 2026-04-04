#!/usr/bin/env python3
"""
Verifier for EEVEE Real-Time Render Migration task.
Scores based on:
1. Engine change (Cycles -> EEVEE)
2. Quality settings (Samples, AO, Raytracing)
3. Output settings (Resolution)
4. File artifacts (Render png, Blend file)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_eevee_migration(traj, env_info, task_info):
    """
    Verify EEVEE migration task.
    
    Scoring Breakdown (100 pts total):
    - Engine is EEVEE: 20 pts
    - Render Samples (64): 10 pts
    - Viewport Samples (32): 5 pts
    - Ambient Occlusion (On, Dist~1.0): 15 pts
    - RayTracing/SSR (On): 10 pts
    - Resolution (1080p @ 100%): 10 pts
    - Valid Render Output: 15 pts
    - Valid Blend Saved: 15 pts
    """
    
    # 1. Retrieve Result JSON from Environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    scene = result.get('scene_settings', {})
    render_file = result.get('render', {})
    blend_file = result.get('blend', {})

    score = 0
    feedback = []

    # Criterion 1: Render Engine (20 pts)
    # EEVEE can be 'BLENDER_EEVEE' or 'BLENDER_EEVEE_NEXT' depending on version
    engine = scene.get('engine', '')
    if 'EEVEE' in engine:
        score += 20
        feedback.append("✅ Engine switched to EEVEE")
    else:
        feedback.append(f"❌ Engine is {engine} (expected EEVEE)")

    # Criterion 2: Samples (15 pts total)
    r_samples = scene.get('render_samples', 0)
    v_samples = scene.get('viewport_samples', 0)
    
    if r_samples == 64:
        score += 10
        feedback.append("✅ Render samples set to 64")
    else:
        feedback.append(f"❌ Render samples: {r_samples} (expected 64)")
        
    if v_samples == 32:
        score += 5
        feedback.append("✅ Viewport samples set to 32")
    else:
        feedback.append(f"❌ Viewport samples: {v_samples} (expected 32)")

    # Criterion 3: Ambient Occlusion (15 pts total)
    ao_on = scene.get('use_ao', False)
    ao_dist = scene.get('ao_distance', 0.0)
    
    if ao_on:
        score += 10
        feedback.append("✅ Ambient Occlusion enabled")
        # Check distance (allow slight float tolerance)
        if 0.9 <= ao_dist <= 1.1:
            score += 5
            feedback.append("✅ AO Distance correct (~1.0m)")
        else:
            feedback.append(f"⚠️ AO Distance {ao_dist}m (expected 1.0m)")
    else:
        feedback.append("❌ Ambient Occlusion disabled")

    # Criterion 4: Ray Tracing / SSR (10 pts)
    rt_on = scene.get('use_raytracing', False)
    if rt_on:
        score += 10
        feedback.append("✅ Ray Tracing/SSR enabled")
    else:
        feedback.append("❌ Ray Tracing/SSR disabled")

    # Criterion 5: Resolution (10 pts)
    res_x = scene.get('resolution_x', 0)
    res_y = scene.get('resolution_y', 0)
    res_pct = scene.get('resolution_percentage', 0)
    
    if res_x == 1920 and res_y == 1080 and res_pct == 100:
        score += 10
        feedback.append("✅ Resolution 1920x1080 @ 100%")
    else:
        feedback.append(f"❌ Resolution {res_x}x{res_y} @ {res_pct}% (expected 1920x1080 @ 100%)")

    # Criterion 6: Render Output File (15 pts)
    # Must exist, be created during task, and have correct dims
    if render_file.get('exists') and render_file.get('created_during_task'):
        if render_file.get('width') == 1920 and render_file.get('height') == 1080:
            score += 15
            feedback.append("✅ Valid render output file created")
        else:
            score += 10 # Partial credit if file exists but wrong res
            feedback.append("⚠️ Render output created but wrong resolution")
    else:
        feedback.append("❌ No new render output found")

    # Criterion 7: Blend File Saved (15 pts)
    if blend_file.get('exists') and blend_file.get('saved_during_task') and blend_file.get('valid'):
        score += 15
        feedback.append("✅ Project saved successfully")
    else:
        feedback.append("❌ Project file not saved or invalid")

    # 3. Final Determination
    # Threshold 70, but MUST have switched engine and produced at least one file
    critical_gate = ('EEVEE' in engine) and (render_file.get('exists') or blend_file.get('exists'))
    passed = (score >= 70) and critical_gate

    if not critical_gate and score >= 70:
        feedback.insert(0, "FAILED CRITICAL CHECK: Must switch engine and save output.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }