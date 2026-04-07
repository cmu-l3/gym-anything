#!/usr/bin/env python3
"""
Verifier for Tile Series Layout task in Weasis.

Evaluates whether the agent successfully changed the layout to a multi-image grid (>= 2x2).
Uses a hybrid programmatic + VLM approach across trajectory frames to ensure anti-gaming.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's completion of a medical imaging task in Weasis.
The agent was asked to change the display layout from a single image to a tiled grid layout (e.g., 2x2, 3x3) to view multiple slices of a DICOM series simultaneously.

Please analyze the provided screenshots (which include trajectory frames and the final screenshot):

1. Does the final image show a grid layout with at least 4 distinct image tiles visible simultaneously (like a 2x2 grid)?
2. Do the tiles contain actual medical/DICOM image content (not empty gray panels)?
3. Do the trajectory frames show the agent interacting with the layout controls (e.g., clicking layout grid buttons in the toolbar or using the View menu)?

Respond EXACTLY in this JSON format:
{
    "multiple_tiles_visible": true/false,
    "medical_content_visible": true/false,
    "trajectory_shows_interaction": true/false,
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_tile_series_layout(traj, env_info, task_info):
    """
    Verify that the series layout was changed to a multi-tile grid and screenshot was saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/DICOM/exports/grid_layout.png')
    min_size_bytes = metadata.get('min_file_size_bytes', 10240)
    min_width = metadata.get('min_width', 800)
    min_height = metadata.get('min_height', 600)

    score = 0
    feedback_parts = []
    
    # 1. Parse JSON Result from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get("output_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    output_size_bytes = result.get("output_size_bytes", 0)

    # 2. File Verification (35 points total)
    if output_exists:
        score += 15
        feedback_parts.append("Output file found")
        
        if output_size_bytes >= min_size_bytes:
            score += 10
            feedback_parts.append(f"Valid file size ({output_size_bytes} bytes)")
        else:
            feedback_parts.append(f"File too small ({output_size_bytes} bytes)")
            
        if file_created_during_task:
            score += 10
            feedback_parts.append("Created during task")
        else:
            feedback_parts.append("File created before task started (Anti-gaming check failed)")
            file_created_during_task = False # Block pass
    else:
        feedback_parts.append("Output file not found")

    # 3. Optional Programmatic Image Inspection (Dimensions) (10 points)
    image_width, image_height = 0, 0
    if output_exists:
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_output_path, temp_img.name)
            # Use PIL to get dimensions safely without cv2 dependency risk
            try:
                from PIL import Image
                with Image.open(temp_img.name) as img:
                    image_width, image_height = img.size
                if image_width >= min_width and image_height >= min_height:
                    score += 10
                    feedback_parts.append(f"Valid dimensions ({image_width}x{image_height})")
                else:
                    feedback_parts.append(f"Dimensions too small ({image_width}x{image_height})")
            except ImportError:
                # If PIL is unavailable on host, award partial points to avoid failing
                score += 5
                feedback_parts.append("PIL unavailable for dimension check")
        except Exception as e:
            feedback_parts.append("Failed to analyze image file locally")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

    # 4. VLM Verification on Trajectory (55 points)
    vlm_score = 0
    multiple_tiles_visible = False
    
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        # Include the final frame prominently
        images_to_analyze = frames + [final_frame] if final_frame else frames
        
        if images_to_analyze:
            vlm_response = query_vlm(images=images_to_analyze, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                multiple_tiles_visible = parsed.get("multiple_tiles_visible", False)
                if multiple_tiles_visible:
                    vlm_score += 25
                    feedback_parts.append("VLM: Multi-tile layout verified")
                else:
                    feedback_parts.append("VLM: Multi-tile layout NOT detected")

                if parsed.get("medical_content_visible", False):
                    vlm_score += 15
                    feedback_parts.append("VLM: Medical content verified")
                    
                if parsed.get("trajectory_shows_interaction", False):
                    vlm_score += 15
                    feedback_parts.append("VLM: Interaction trajectory verified")
            else:
                feedback_parts.append("VLM query failed or returned no response")
        else:
            feedback_parts.append("No trajectory frames available for VLM")
            
    except ImportError:
        logger.warning("VLM module not available. Skipping VLM check.")
        feedback_parts.append("VLM verification skipped (module missing)")

    score += vlm_score

    # Determine Pass/Fail (Must score at least 60 AND have created the file AND changed layout)
    # The file checks max out at 45. VLM is required to pass the 60 threshold.
    passed = score >= 60 and output_exists and file_created_during_task and multiple_tiles_visible

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }