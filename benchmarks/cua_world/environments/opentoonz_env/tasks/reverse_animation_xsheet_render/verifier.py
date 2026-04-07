#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_reverse_animation(traj, env_info, task_info):
    """
    Verifies the reverse animation task.
    
    Scoring Criteria:
    1. Output Generation (30 pts):
       - At least 10 PNG files created.
       - Files created during task (timestamp check).
       - Reasonable file size (>100KB total).
       
    2. Visual Verification (70 pts):
       - Uses VLM to check if the animation sequence appears to be running backwards.
       - Checks if the character is walking backwards compared to standard walk cycles.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Extract metrics
    file_count = result_data.get("file_count", 0)
    new_files_count = result_data.get("new_files_count", 0)
    total_size_bytes = result_data.get("total_size_bytes", 0)
    frames_list_str = result_data.get("frames_list", "")
    
    score = 0
    feedback = []
    
    # 2. Validate Output Files (30 pts)
    min_frames = task_info.get("metadata", {}).get("min_frame_count", 10)
    min_size = task_info.get("metadata", {}).get("min_total_size_kb", 100) * 1024
    
    if file_count >= min_frames:
        score += 10
        feedback.append(f"✓ Frame count sufficient ({file_count} >= {min_frames})")
    else:
        feedback.append(f"✗ Frame count insufficient ({file_count} < {min_frames})")
        
    if new_files_count >= min_frames:
        score += 10
        feedback.append("✓ Files created during task session")
    elif new_files_count > 0:
        score += 5
        feedback.append(f"⚠ Only {new_files_count} files created during session")
    else:
        feedback.append("✗ No new files created")
        
    if total_size_bytes >= min_size:
        score += 10
        feedback.append(f"✓ Output size valid ({total_size_bytes/1024:.1f} KB)")
    else:
        feedback.append(f"✗ Output size too small ({total_size_bytes/1024:.1f} KB)")

    # Stop if basic criteria failed (prevents wasting VLM calls)
    if score < 15:
        return {
            "passed": False,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    # 3. VLM Visual Verification (70 pts)
    # We need to sample frames to detect motion
    frame_paths = frames_list_str.split(',') if frames_list_str else []
    
    if len(frame_paths) < 3:
        feedback.append("✗ Not enough frames for motion analysis")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Pick 3 frames: Start, Middle, End
    sample_indices = [0, len(frame_paths)//2, len(frame_paths)-1]
    sample_remote_paths = [frame_paths[i] for i in sample_indices]
    
    # Download sampled frames
    local_frames = []
    for remote_path in sample_remote_paths:
        if not remote_path: continue
        ext = os.path.splitext(remote_path)[1]
        t = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
        t.close()
        try:
            copy_from_env(remote_path, t.name)
            local_frames.append(t.name)
        except Exception as e:
            logger.warning(f"Failed to copy frame {remote_path}: {e}")

    if len(local_frames) < 3:
        feedback.append("✗ Failed to retrieve frames for verification")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # VLM Query
    # We pass the images and ask specifically about the walk direction
    from gym_anything.vlm import query_vlm
    
    prompt = (
        "These are three frames (Start, Middle, End) from an animation sequence. "
        "The goal was to reverse a standard walk cycle so the character walks BACKWARDS. "
        "1. Does the character appear to be the same in all frames (consistency)? "
        "2. Does the sequence of poses suggest a BACKWARD movement (e.g. feet moving in reverse of a normal walk)? "
        "Provide a JSON response with keys: 'consistent_character' (bool), 'appears_reversed' (bool), 'confidence' (float 0-1)."
    )
    
    try:
        # Note: gym_anything.vlm.query_vlm usually takes a list of image paths
        vlm_resp = query_vlm(prompt=prompt, images=local_frames)
        
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            
            is_reversed = parsed.get('appears_reversed', False)
            is_consistent = parsed.get('consistent_character', False)
            
            if is_consistent:
                score += 20
                feedback.append("✓ Character consistency verified")
            else:
                feedback.append("✗ Character consistency check failed")
                
            if is_reversed:
                score += 50
                feedback.append("✓ Animation reversal verified (Walks Backwards)")
            else:
                feedback.append("✗ Animation does not appear to be reversed")
        else:
            feedback.append("⚠ Visual verification failed (VLM error)")
            # Fallback scoring if VLM fails but files exist? 
            # We'll grant partial credit for file existence which we already did.
            
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback.append(f"⚠ Verification error: {e}")
    finally:
        # Cleanup local images
        for f in local_frames:
            if os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "\n".join(feedback)
    }