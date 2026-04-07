#!/usr/bin/env python3
"""
Verifier for Fleet Dashcam PiP Synchronization task.
Uses multi-criteria scoring combining ffprobe metadata, pixel-level color analysis of extracted frames, and VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_color_red(r, g, b):
    return r > 150 and g < 100 and b < 100

def is_color_blue(r, g, b):
    return r < 100 and g < 100 and b > 150

def analyze_pixels(image_path):
    """Analyze specific pixel coordinates to verify spatial composition."""
    try:
        from PIL import Image
        img = Image.open(image_path).convert('RGB')
        
        # Dimensions check
        if img.width != 1920 or img.height != 1080:
            logger.warning(f"Image dimensions are {img.width}x{img.height}, expecting 1920x1080. Scaling checks may fail.")
            
        # Coordinates based on 1920x1080, PiP 640x360, margin 20
        # PiP area: X from 1260 to 1900, Y from 700 to 1060
        coords = {
            "main_center": (600, 500),         # Outside PiP (Front camera)
            "pip_center": (1580, 880),         # Inside PiP (Cabin camera)
            "right_margin": (1910, 880),       # To the right of PiP (should be Front)
            "bottom_margin": (1580, 1070),     # Below PiP (should be Front)
            "top_margin": (1580, 690),         # Above PiP (should be Front)
            "left_margin": (1250, 880)         # To the left of PiP (should be Front)
        }
        
        results = {}
        for name, (x, y) in coords.items():
            if x < img.width and y < img.height:
                r, g, b = img.getpixel((x, y))
                is_red = is_color_red(r, g, b)
                is_blue = is_color_blue(r, g, b)
                results[name] = {"red": is_red, "blue": is_blue, "rgb": (r,g,b)}
            else:
                results[name] = {"red": False, "blue": False, "rgb": (0,0,0)}
                
        return results
    except ImportError:
        logger.error("PIL is not available. Cannot perform pixel analysis.")
        return None
    except Exception as e:
        logger.error(f"Error reading image {image_path}: {e}")
        return None

def verify_fleet_dashcam_pip_synchronization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criterion 1: Output Exists (10 points)
    output_exists = result.get("output_exists") == "true"
    created_during = result.get("file_created_during_task") == "true"
    
    if output_exists and created_during:
        score += 10
        feedback_parts.append("Composite file created")
    elif output_exists:
        feedback_parts.append("Composite file exists but not modified during task (anti-gaming flag)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("Composite file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Criterion 2: Resolution & Duration (15 points)
    try:
        duration = float(result.get("duration", 0))
    except ValueError:
        duration = 0.0
    width = str(result.get("width", "0"))
    height = str(result.get("height", "0"))
    
    dim_ok = width == "1920" and height == "1080"
    dur_ok = abs(duration - 15.0) <= 0.5
    
    if dim_ok and dur_ok:
        score += 15
        feedback_parts.append(f"Dimensions and duration correct ({width}x{height}, {duration:.1f}s)")
    else:
        if dim_ok:
            score += 5
            feedback_parts.append(f"Dimensions correct but duration off ({duration:.1f}s, expected 15.0s)")
        elif dur_ok:
            score += 10
            feedback_parts.append(f"Duration correct but dimensions off ({width}x{height})")
        else:
            feedback_parts.append(f"Dims and duration incorrect ({width}x{height}, {duration:.1f}s)")

    # Criterion 3: Audio Mapping (15 points)
    audio_streams = int(result.get("audio_streams", "0"))
    if audio_streams == 1:
        score += 15
        feedback_parts.append("Correct audio mapping (1 stream)")
    elif audio_streams > 1:
        score += 5
        feedback_parts.append(f"Failed to discard front audio ({audio_streams} streams found)")
    else:
        feedback_parts.append("No audio streams found")
        
    # Criterion 4 & 5: Temporal Sync & Spatial Composition via Pixels
    # We copy the extracted frames
    sync_passed = False
    composition_passed = False
    
    for t_str, is_flash in [("4_0", False), ("5_1", True)]:
        img_name = f"frame_{t_str}.png"
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(f"/tmp/{img_name}", temp_img.name)
            pixels = analyze_pixels(temp_img.name)
            
            if pixels:
                if is_flash:
                    # t=5.1s -> Flashing -> Front=Red, Cabin=Blue
                    front_red = pixels["main_center"]["red"]
                    cabin_blue = pixels["pip_center"]["blue"]
                    
                    if front_red and cabin_blue:
                        score += 30  # Temporal Sync & Trim points
                        sync_passed = True
                        feedback_parts.append("Temporal synchronization correct (Flashes aligned and trimmed)")
                    else:
                        feedback_parts.append("Flashes not aligned at t=5.0s (Sync or trim failed)")
                        
                    # Spatial margins check
                    right_red = pixels["right_margin"]["red"]
                    bottom_red = pixels["bottom_margin"]["red"]
                    top_red = pixels["top_margin"]["red"]
                    left_red = pixels["left_margin"]["red"]
                    
                    if cabin_blue and right_red and bottom_red and top_red and left_red:
                        score += 15  # Spatial Composition points
                        composition_passed = True
                        feedback_parts.append("PiP margins and sizing perfect")
                    elif cabin_blue:
                        score += 5
                        feedback_parts.append("PiP present but margins/scaling incorrect")
                else:
                    # t=4.0s -> Before flash -> Neither should be Red/Blue
                    front_red = pixels["main_center"]["red"]
                    cabin_blue = pixels["pip_center"]["blue"]
                    if front_red or cabin_blue:
                        feedback_parts.append("Flash appears too early (Trim failed)")
                        # Deduct points if we previously awarded them
                        if sync_passed:
                            score -= 30
                            sync_passed = False
                            
        except Exception as e:
            logger.warning(f"Failed to process {img_name}: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
                
    # VLM Trajectory Verification (15 points)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """Analyze these screenshots from an agent working on a video synchronization task.
                The agent is supposed to extract offsets from two videos and combine them via a tool like ffmpeg, VLC, or a video editor.
                Did the agent perform meaningful workflow steps (e.g. typing ffmpeg commands, using an editor, calculating offsets)?
                Respond with valid JSON containing a boolean "meaningful_workflow"."""
                
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("meaningful_workflow", False):
                        score += 15
                        feedback_parts.append("VLM confirmed meaningful workflow")
                    else:
                        feedback_parts.append("VLM could not confirm workflow")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped")
    else:
        feedback_parts.append("VLM not configured")

    passed = score >= 70 and sync_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }