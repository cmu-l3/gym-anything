#!/usr/bin/env python3
"""
Verifier for particle_snow_overlay task.

Verifies that:
1. Valid output frames were generated (>= 24 frames).
2. Frames were created during the task (anti-gaming).
3. The scene file was modified (implies FX node added).
4. VLM Verification: The output contains visible particle/snow effects.
"""

import json
import os
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_particle_snow_overlay(traj, env_info, task_info):
    """
    Verify the OpenToonz particle task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frames', 24)
    
    # Load JSON result from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Extract Metrics
    frame_count = result.get('frame_count', 0)
    new_files_count = result.get('new_files_count', 0)
    total_size = result.get('total_size_bytes', 0)
    scene_modified = result.get('scene_modified', False)
    rendered_sample_exists = result.get('rendered_sample_exists', False)

    score = 0
    feedback = []

    # 3. Criterion 1: Output Generation (40 points)
    if frame_count >= min_frames:
        score += 20
        feedback.append(f"✓ Rendered {frame_count} frames (>= {min_frames})")
    elif frame_count > 0:
        score += 10
        feedback.append(f"⚠ Rendered only {frame_count} frames (expected {min_frames})")
    else:
        feedback.append("✗ No output frames found")

    if new_files_count >= min_frames:
        score += 20
        feedback.append("✓ Files created during task session")
    elif new_files_count > 0:
        score += 10
        feedback.append("⚠ Some files are old or pre-existing")
    else:
        feedback.append("✗ No new files created")

    # 4. Criterion 2: Scene Modification (15 points)
    # Adding FX node modifies the .tnz XML
    if scene_modified:
        score += 15
        feedback.append("✓ Scene file modified (FX likely added)")
    else:
        feedback.append("✗ Scene file not modified (did you add the FX node?)")

    # 5. Criterion 3: File Size Sanity Check (5 points)
    if total_size > 200 * 1024:  # > 200KB
        score += 5
        feedback.append("✓ Output size reasonable")
    else:
        feedback.append("⚠ Output size suspiciously small")

    # 6. Criterion 4: VLM Visual Verification (40 points)
    # We analyze the actual rendered frame, not just the UI screenshot
    vlm_score = 0
    vlm_feedback = "VLM verification skipped"
    
    if rendered_sample_exists and copy_from_env:
        try:
            # Copy the sample frame from container
            local_sample = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
            copy_from_env("/tmp/rendered_sample.png", local_sample)
            
            # VLM Query
            from gym_anything.vlm import query_vlm
            
            prompt = (
                "This is a frame from a 2D animation. "
                "I am looking for a 'particle' or 'snow' effect overlaid on the character. "
                "Look for white dots, sparkles, snowflakes, or textured noise that looks like weather/magic. "
                "1. Do you see a character? "
                "2. Do you see any particle/snow/sparkle effects overlaid on top? "
                "Return JSON: {\"has_character\": bool, \"has_particles\": bool, \"description\": string}"
            )
            
            vlm_response = query_vlm(prompt=prompt, image=local_sample)
            
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                has_particles = parsed.get('has_particles', False)
                
                if has_particles:
                    vlm_score = 40
                    vlm_feedback = "✓ VLM detected particle effects in output"
                else:
                    vlm_score = 0
                    vlm_feedback = f"✗ VLM did NOT detect particles in output: {parsed.get('description', 'No description')}"
            
            # Cleanup
            if os.path.exists(local_sample):
                os.unlink(local_sample)
                
        except Exception as e:
            vlm_feedback = f"⚠ VLM verification failed: {str(e)}"
    else:
        vlm_feedback = "✗ No rendered sample available for visual verification"

    score += vlm_score
    feedback.append(vlm_feedback)

    # 7. Final Scoring
    passed = (score >= 60) and (frame_count >= 1) and (vlm_score > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }