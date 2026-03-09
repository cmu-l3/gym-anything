#!/usr/bin/env python3
"""
Verifier for audio_reactive_visualizer task.

Criteria:
1. File saved (10 pts)
2. SpeakerCone object has animation (20 pts)
3. Animation is on Scale Z channel (20 pts)
4. Baked data detected (High keyframe density > 50 keys) (30 pts)
5. Audio reaction detected (Variance > 0.1) (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audio_visualizer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    analysis = result.get("analysis", {})
    output_exists = result.get("output_exists", False)
    
    score = 0
    feedback_parts = []
    
    # Crit 1: File Saved
    if output_exists and analysis.get("valid_file"):
        score += 10
        feedback_parts.append("File saved successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or invalid."}

    # Crit 2: Object Animation
    if analysis.get("animation_found"):
        score += 20
        feedback_parts.append("Animation data found.")
    else:
        feedback_parts.append("No animation data found on SpeakerCone.")
    
    # Crit 3: Correct Channel
    if analysis.get("target_channel_found"):
        score += 20
        feedback_parts.append("Correct Scale Z channel targeted.")
    else:
        feedback_parts.append("Scale Z channel not animated.")
        
    # Crit 4: Baked Data (Keyframe Count)
    # Manual animation usually has < 10 keys. Baked sound has 1 per frame.
    key_count = analysis.get("keyframe_count", 0)
    if key_count > 50:
        score += 30
        feedback_parts.append(f"High keyframe density detected ({key_count} keys).")
    elif key_count > 0:
        score += 10
        feedback_parts.append(f"Low keyframe density ({key_count} keys) - likely not baked.")
    else:
        feedback_parts.append("No keyframes found.")

    # Crit 5: Variance (Did it actually capture sound?)
    variance = analysis.get("variance", 0.0)
    if variance > 0.1:
        score += 20
        feedback_parts.append("Audio reaction detected (amplitude variation).")
    else:
        feedback_parts.append("Animation is flat/static.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }