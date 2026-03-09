#!/usr/bin/env python3
"""
Verifier for bicycle_frame_geometry task.
Uses pre-calculated geometry metrics from the container-side ezdxf script
and VLM for visual confirmation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bicycle_geometry(traj, env_info, task_info):
    """
    Verify the bicycle frame geometry task.
    
    Score breakdown:
    - 60 pts: Geometric accuracy (calculated inside container via ezdxf)
      - Layers correct
      - Key nodes (BB, Axle, HeadTube, SeatTube) at correct coordinates
      - Entities exist (Dimensions, Text)
    - 20 pts: File properties (Created during task, reasonable size)
    - 20 pts: VLM Visual Verification (Looks like a bike frame, correct orientation)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Load Result JSON
    # ================================================================
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

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 2. File Properties (20 pts)
    # ================================================================
    output_exists = result.get("output_exists", False)
    created_during = result.get("file_created_during_task", False)
    size = result.get("output_size_bytes", 0)
    
    if output_exists:
        if created_during:
            score += 15
            feedback_parts.append("DXF file created during task")
        else:
            feedback_parts.append("DXF file exists but timestamp matches pre-task (not new)")
        
        if size > 1000: # Empty DXF header is usually small, content adds size
            score += 5
            feedback_parts.append("File size indicates content")
        else:
            feedback_parts.append("File size very small (empty drawing?)")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    # ================================================================
    # 3. Geometric Analysis (60 pts)
    # ================================================================
    geo = result.get("geometry_analysis", {})
    
    if not geo.get("valid_dxf", False):
        feedback_parts.append("File is not a valid DXF")
    else:
        # The container script calculates a score up to ~70 based on nodes and layers
        # We normalize this to our 60 pt bucket
        container_score = geo.get("geometry_score", 0)
        # Cap at 60 for this section
        geo_score = min(60, container_score)
        score += geo_score
        
        feedback_parts.append(f"Geometry Analysis: {container_score} pts")
        
        # Add detailed feedback from script
        script_feedback = geo.get("feedback", [])
        if script_feedback:
            feedback_parts.append("Issues: " + "; ".join(script_feedback[:3]))
        
        # Check specific critical nodes for reporting
        nodes = geo.get("nodes_found", {})
        if nodes.get("BB", {}).get("found") and nodes.get("HT_Top", {}).get("found"):
            feedback_parts.append("Main triangle anchors found")
            
    # ================================================================
    # 4. VLM Verification (20 pts)
    # ================================================================
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=2)
    
    if final_screenshot:
        prompt = """
        Analyze this LibreCAD screenshot. 
        1. Do you see a 2D line drawing of a bicycle frame? 
        2. Does it look like a "double triangle" or diamond frame shape?
        3. Are there text labels or dimensions visible?
        4. Is the background mostly black or dark grey (typical CAD)?
        
        Return JSON:
        {
            "is_bicycle_frame": true/false,
            "has_dimensions": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames + [final_screenshot])
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("is_bicycle_frame", False):
                score += 15
                feedback_parts.append("VLM confirms bicycle frame geometry")
            
            if parsed.get("has_dimensions", False):
                score += 5
                feedback_parts.append("VLM sees dimensions/annotations")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if geometry score is high, give some VLM points
            if score >= 50:
                score += 10
                feedback_parts.append("VLM skipped, trusting geometry check")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }