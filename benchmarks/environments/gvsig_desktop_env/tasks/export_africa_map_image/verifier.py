#!/usr/bin/env python3
"""
Verifier for export_africa_map_image task.

Checks:
1. Programmatic: File existence, valid PNG header, dimensions, file size, creation timestamp.
2. VLM: Visual verification that the map shows Africa, has country borders, rivers, and cities.
"""

import json
import os
import sys
import tempfile
import struct
import logging
from typing import Dict, Any

# Import VLM utils provided by the framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"passed": False, "reason": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_africa_map_image(traj, env_info, task_info):
    """
    Verify the agent created and exported a map of Africa with specific layers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/gvsig_data/exports/africa_rivers_map.png')
    min_width = metadata.get('min_width', 400)
    min_height = metadata.get('min_height', 400)
    min_size = metadata.get('min_size_bytes', 20480) # ~20KB

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Metadata
    # ------------------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            task_result = json.load(tf)
        except Exception as e:
            logger.error(f"Failed to copy task result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result metadata"}

    # ------------------------------------------------------------------
    # 2. Retrieve Exported Image
    # ------------------------------------------------------------------
    output_exists = task_result.get('output_exists', False)
    local_image_path = None
    
    if output_exists:
        try:
            # Create a temp file for the image
            fd, local_image_path = tempfile.mkstemp(suffix='.png')
            os.close(fd)
            copy_from_env(expected_path, local_image_path)
        except Exception as e:
            logger.error(f"Failed to copy exported image: {e}")
            output_exists = False
            feedback_parts.append("Exported file reported existing but could not be retrieved")

    # ------------------------------------------------------------------
    # 3. Programmatic Verification (45 points)
    # ------------------------------------------------------------------
    
    # A. File Existence (10 pts)
    if output_exists:
        score += 10
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file NOT found")
        # Critical fail if file doesn't exist
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # B. Creation Timestamp (5 pts)
    if task_result.get('created_during_task', False):
        score += 5
    else:
        feedback_parts.append("File not created during task session (old file?)")

    # C. Valid PNG & Dimensions (15 pts)
    width, height = 0, 0
    is_valid_png = False
    
    if local_image_path and os.path.getsize(local_image_path) > 0:
        try:
            with open(local_image_path, 'rb') as f:
                header = f.read(24)
                # Check PNG signature
                if header.startswith(b'\x89PNG\r\n\x1a\n'):
                    is_valid_png = True
                    # Extract IHDR dimensions (big-endian unsigned int)
                    # IHDR starts at byte 12: Length(4) ChunkType(4) Width(4) Height(4)
                    # Actually standard header is 8 bytes, then IHDR chunk. 
                    # Structure: [8 bytes signature] [4 bytes length] [4 bytes type='IHDR'] [4 bytes width] [4 bytes height]
                    if len(header) >= 24:
                        w_bytes = header[16:20]
                        h_bytes = header[20:24]
                        width = struct.unpack('>I', w_bytes)[0]
                        height = struct.unpack('>I', h_bytes)[0]
        except Exception as e:
            logger.warning(f"Error parsing PNG header: {e}")

    if is_valid_png:
        score += 5
        feedback_parts.append("Valid PNG format")
        
        if width >= min_width and height >= min_height:
            score += 10
            feedback_parts.append(f"Dimensions OK ({width}x{height})")
        else:
            feedback_parts.append(f"Dimensions too small ({width}x{height}, expected >={min_width}x{min_height})")
    else:
        feedback_parts.append("Invalid or corrupted PNG file")

    # D. File Size & Content (15 pts)
    file_size = task_result.get('output_size_bytes', 0)
    if file_size > min_size:
        score += 5
        feedback_parts.append("File size substantial")
    elif file_size > 0:
        score += 2
        feedback_parts.append("File size suspiciously small")
    
    # Check simple color diversity if we can (requires PIL or simple byte analysis)
    # We'll skip complex local analysis and rely on VLM for content, 
    # but a simple entropy check or size check usually proxies well for "not blank".
    if file_size > 50000: # 50KB usually implies content
        score += 10
        feedback_parts.append("Content complexity likely sufficient")
    elif file_size > min_size:
        score += 5

    # ------------------------------------------------------------------
    # 4. VLM Verification (55 points)
    # ------------------------------------------------------------------
    
    # We analyze the EXPORTED IMAGE for the final result quality
    # We analyze TRAJECTORY for workflow verification
    
    vlm_feedback = []
    
    # A. Analyze the Result Image (35 pts)
    # We use the exported image if available, otherwise fallback to final screenshot
    image_to_analyze = local_image_path if local_image_path else get_final_screenshot(traj)
    
    if image_to_analyze:
        prompt = """
        Analyze this map image.
        1. Does it depict the continent of Africa?
        2. Are there country boundaries (polygons) visible?
        3. Are there blue lines representing rivers?
        4. Are there dots/points representing cities?
        
        Answer JSON: {"is_africa": bool, "has_countries": bool, "has_rivers": bool, "has_cities": bool}
        """
        
        try:
            # We pass the image path directly
            # Note: query_vlm usually expects 'images' list of paths or base64
            vlm_res = query_vlm(images=[image_to_analyze], prompt=prompt)
            
            # Simple parsing logic (assuming the VLM helper returns a dict or we parse the text)
            # Adjust based on actual VLM return format. Assuming it returns a dict or object with .get()
            # If it returns string, we'd need to parse JSON.
            # Here assuming framework handles JSON parsing if we request it, or we parse text.
            
            content = vlm_res if isinstance(vlm_res, dict) else {}
            # If content is empty or string, try to parse
            if not isinstance(content, dict):
                 # Fallback/Dummy logic if VLM fails to return structured data
                 # In production, use robust JSON parser
                 pass

            # Scoring based on VLM
            # (Using resilient logic assuming keys might be present)
            if content.get("is_africa"):
                score += 15
                vlm_feedback.append("VLM: Map shows Africa")
            
            if content.get("has_countries"):
                score += 10
                vlm_feedback.append("VLM: Countries visible")
                
            if content.get("has_rivers") and content.get("has_cities"):
                score += 10
                vlm_feedback.append("VLM: Rivers and Cities visible")
                
        except Exception as e:
            logger.error(f"VLM analysis failed: {e}")
            vlm_feedback.append("VLM analysis error")
    
    # B. Analyze Trajectory (20 pts)
    # Check if they actually loaded layers
    frames = sample_trajectory_frames(traj, 5)
    if frames:
        traj_prompt = """
        Review these screenshots of a GIS software (gvSIG) workflow.
        Did the user:
        1. Open a "Add Layer" dialog or browse for files?
        2. Are multiple layers listed in the side panel (Table of Contents)?
        
        Answer JSON: {"files_loaded": bool, "layers_panel_populated": bool}
        """
        try:
            traj_res = query_vlm(images=frames, prompt=traj_prompt)
            t_content = traj_res if isinstance(traj_res, dict) else {}
            
            if t_content.get("files_loaded") or t_content.get("layers_panel_populated"):
                score += 20
                vlm_feedback.append("VLM: Workflow trajectory confirmed")
        except Exception:
            pass

    # Cleanup
    if local_image_path and os.path.exists(local_image_path):
        os.unlink(local_image_path)

    # Final tally
    feedback_parts.extend(vlm_feedback)
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }