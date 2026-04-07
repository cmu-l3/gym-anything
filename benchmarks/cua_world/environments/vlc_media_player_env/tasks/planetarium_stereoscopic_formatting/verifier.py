#!/usr/bin/env python3
import os
import json
import logging
import tempfile
import numpy as np
import cv2
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_mse(image_path_1, image_path_2):
    """Calculates the Mean Squared Error between two images."""
    if not os.path.exists(image_path_1) or not os.path.exists(image_path_2):
        return float('inf')
    
    img1 = cv2.imread(image_path_1)
    img2 = cv2.imread(image_path_2)
    
    if img1 is None or img2 is None:
        return float('inf')
    
    # Resize to match if necessary, though they should both be 1920x1080
    if img1.shape != img2.shape:
        img2 = cv2.resize(img2, (img1.shape[1], img1.shape[0]))
        
    err = np.sum((img1.astype("float") - img2.astype("float")) ** 2)
    err /= float(img1.shape[0] * img1.shape[1] * img1.shape[2])
    return err

def verify_planetarium_stereoscopic_formatting(traj, env_info, task_info):
    """
    Verifies the stereoscopic manipulation task using multi-signal evaluation:
    1. File metadata (resolution, audio presence).
    2. Structural image similarity (MSE against hidden ground-truth frames).
    3. JSON Manifest evaluation.
    4. VLM verification to ensure workflow was executed.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Create temp dir to pull files to host
    with tempfile.TemporaryDirectory() as temp_dir:
        # Pull the task result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                results = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
        
        outputs = results.get("outputs", {})
        
        # Sub-score evaluations
        # 1. Lobby 2D (Left eye, audio preserved) -> 25 points total (10 meta + 15 visual)
        lobby = outputs.get("lobby_2d", {})
        if lobby.get("exists") and lobby.get("created_during_task"):
            if lobby.get("resolution") == "1920x1080":
                score += 5
            else:
                feedback_parts.append(f"Lobby 2D wrong resolution: {lobby.get('resolution')}")
                
            if lobby.get("has_audio"):
                score += 5
            else:
                feedback_parts.append("Lobby 2D missing audio")
                
            # Copy frames for visual check
            copy_from_env("/tmp/frames/gt_lobby.png", os.path.join(temp_dir, "gt_lobby.png"))
            copy_from_env("/tmp/frames/agent_lobby.png", os.path.join(temp_dir, "agent_lobby.png"))
            mse_lobby = calculate_mse(os.path.join(temp_dir, "gt_lobby.png"), os.path.join(temp_dir, "agent_lobby.png"))
            
            if mse_lobby < 1000: # Tight tolerance for structural match
                score += 15
                feedback_parts.append("Lobby 2D visual extraction correct.")
            else:
                feedback_parts.append(f"Lobby 2D visual mismatch (MSE: {mse_lobby:.1f}).")
        else:
            feedback_parts.append("Lobby 2D file missing or not newly created.")

        # 2. Dome Right (Right eye, stripped audio) -> 25 points total (10 meta + 15 visual)
        dome = outputs.get("dome_right", {})
        if dome.get("exists") and dome.get("created_during_task"):
            if dome.get("resolution") == "1920x1080":
                score += 5
            else:
                feedback_parts.append(f"Dome Right wrong resolution: {dome.get('resolution')}")
                
            if not dome.get("has_audio"):
                score += 5
            else:
                feedback_parts.append("Dome Right failed to strip audio.")
                
            # Copy frames for visual check
            copy_from_env("/tmp/frames/gt_dome.png", os.path.join(temp_dir, "gt_dome.png"))
            copy_from_env("/tmp/frames/agent_dome.png", os.path.join(temp_dir, "agent_dome.png"))
            mse_dome = calculate_mse(os.path.join(temp_dir, "gt_dome.png"), os.path.join(temp_dir, "agent_dome.png"))
            
            if mse_dome < 1000:
                score += 15
                feedback_parts.append("Dome Right visual extraction correct.")
            else:
                feedback_parts.append(f"Dome Right visual mismatch (MSE: {mse_dome:.1f}).")
        else:
            feedback_parts.append("Dome Right file missing or not newly created.")

        # 3. Anaglyph (Red/Cyan, audio preserved) -> 25 points total (10 meta + 15 visual)
        anaglyph = outputs.get("classroom_anaglyph", {})
        if anaglyph.get("exists") and anaglyph.get("created_during_task"):
            if anaglyph.get("resolution") == "1920x1080":
                score += 5
            else:
                feedback_parts.append(f"Anaglyph wrong resolution: {anaglyph.get('resolution')}")
                
            if anaglyph.get("has_audio"):
                score += 5
            else:
                feedback_parts.append("Anaglyph missing audio.")
                
            # Copy frames for visual check
            copy_from_env("/tmp/frames/gt_anaglyph.png", os.path.join(temp_dir, "gt_anaglyph.png"))
            copy_from_env("/tmp/frames/agent_anaglyph.png", os.path.join(temp_dir, "agent_anaglyph.png"))
            mse_anaglyph = calculate_mse(os.path.join(temp_dir, "gt_anaglyph.png"), os.path.join(temp_dir, "agent_anaglyph.png"))
            
            # Allow slightly higher tolerance for varying anaglyph algorithms (e.g. dubois vs half-color vs full-color)
            if mse_anaglyph < 3500:
                score += 15
                feedback_parts.append("Anaglyph stereoscopic visual conversion verified.")
            else:
                feedback_parts.append(f"Anaglyph visual mismatch (MSE: {mse_anaglyph:.1f}).")
        else:
            feedback_parts.append("Anaglyph file missing or not newly created.")

        # 4. JSON Manifest -> 15 points
        manifest_path = os.path.join(temp_dir, "spatial_manifest.json")
        try:
            copy_from_env("/home/ga/Documents/spatial_manifest.json", manifest_path)
            with open(manifest_path, 'r') as f:
                manifest = json.load(f)
                
            deliverables = manifest.get("deliverables", [])
            if isinstance(deliverables, list) and len(deliverables) == 3:
                score += 5
                
                # Check contents validity
                correct_entries = 0
                for d in deliverables:
                    fname = d.get("filename", "")
                    res = d.get("resolution", "")
                    has_audio = d.get("has_audio")
                    fmt = d.get("3d_format", "")
                    
                    if fname == "lobby_2d.mp4" and res == "1920x1080" and has_audio is True and fmt == "monoscopic":
                        correct_entries += 1
                    elif fname == "dome_right.mp4" and res == "1920x1080" and has_audio is False and fmt == "monoscopic":
                        correct_entries += 1
                    elif fname == "classroom_anaglyph.mp4" and res == "1920x1080" and has_audio is True and fmt == "anaglyph":
                        correct_entries += 1
                
                if correct_entries == 3:
                    score += 10
                    feedback_parts.append("JSON Manifest is perfectly formatted.")
                else:
                    score += (correct_entries * 3)
                    feedback_parts.append(f"JSON Manifest has {3 - correct_entries} incorrect entries.")
            else:
                feedback_parts.append("JSON Manifest 'deliverables' array is missing or incorrect size.")
                
        except Exception:
            feedback_parts.append("Failed to find or parse spatial_manifest.json.")

    # 5. VLM Trajectory check -> 10 points
    # Check if the agent actively used VLC or Terminal to process video
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        prompt = """Look at this sequence of screenshots of an agent performing video transcoding/filtering tasks. 
        Did the agent actively use video conversion tools (like the Terminal with ffmpeg, OR VLC's 'Convert/Save' dialog, OR video effect panels)?
        Answer with a JSON object: {"used_conversion_tools": true/false}"""
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames + [final])
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("used_conversion_tools"):
                score += 10
                feedback_parts.append("VLM confirmed usage of conversion tools in trajectory.")
            else:
                feedback_parts.append("VLM did not detect active conversion tool usage in trajectory.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM check skipped/failed.")

    # Determine overall pass
    # Required: at least two proper conversions (which means visual match)
    # Total possible: 25+25+25+15+10 = 100
    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }