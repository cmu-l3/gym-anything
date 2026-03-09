#!/usr/bin/env python3
"""
Verifier for hvac_duct_layout task.
Combines programmatic DXF analysis (from container) with VLM verification.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hvac_duct_layout(traj, env_info, task_info):
    """
    Verifies the HVAC duct layout task.
    
    Criteria:
    1. File exists and is valid DXF (10 pts)
    2. File modified during task (anti-gaming) (10 pts)
    3. Required layers present (WALLS, DUCT-SUPPLY, etc.) (20 pts)
    4. Entity counts on layers are reasonable (prevents empty layers) (20 pts)
    5. Text labels exist (10 pts)
    6. VLM confirms visual correctness (layout shape, colors) (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_layers = set(metadata.get('required_layers', 
        ["WALLS", "DUCT-SUPPLY", "DUCT-DIFFUSER", "DUCT-RETURN", "DUCT-LABELS"]))

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Validity
    if result.get("output_exists", False):
        score += 10
        feedback.append("DXF file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found."}
        
    # 2. Anti-Gaming (Timestamp)
    if result.get("file_created_during_task", False):
        score += 10
        feedback.append("File modified during task session.")
    else:
        feedback.append("WARNING: File not modified during task (possible reuse).")

    # 3. DXF Content Analysis
    analysis = result.get("dxf_analysis", {})
    if not analysis.get("valid_dxf"):
        feedback.append("File is not a valid DXF.")
    else:
        # Check Layers
        found_layers = set(analysis.get("layers_found", []))
        missing_layers = required_layers - found_layers
        
        if not missing_layers:
            score += 20
            feedback.append("All required layers present.")
        else:
            partial = max(0, 20 - (len(missing_layers) * 4))
            score += partial
            feedback.append(f"Missing layers: {', '.join(missing_layers)}.")

        # Check Entities per Layer
        counts = analysis.get("entity_counts", {})
        empty_layers = [l for l in required_layers if counts.get(l, 0) == 0]
        
        if not empty_layers:
            score += 20
            feedback.append("Content found on all required layers.")
        else:
            partial = max(0, 20 - (len(empty_layers) * 4))
            score += partial
            feedback.append(f"Empty layers: {', '.join(empty_layers)}.")
            
        # Check Text
        texts = analysis.get("text_contents", [])
        text_str = " ".join(texts).lower()
        if "24" in text_str and ("10" in text_str or "8" in text_str):
            score += 10
            feedback.append("Duct labels found.")
        elif len(texts) > 0:
            score += 5
            feedback.append("Some text found, but labels may be incorrect.")
        else:
            feedback.append("No text labels found.")

    # 4. VLM Visual Verification
    # Use VLM to confirm the visual layout matches the H-shape / branching pattern
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an HVAC CAD drawing task.
    Look at the screenshot of LibreCAD.
    
    Check for:
    1. A large room rectangle.
    2. A central horizontal trunk duct with vertical branches (looking like an H shape or similar branching).
    3. Square symbols with 'X' inside them at the ends of branches (diffusers).
    4. Different colors used for different elements (indicating layers).
    
    Does the drawing generally match this description?
    Respond with JSON: {"matches_description": boolean, "details": "string"}
    """
    
    vlm_score = 0
    if final_screenshot:
        try:
            vlm_res = query_vlm(vlm_prompt, final_screenshot)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("matches_description", False):
                vlm_score = 30
                feedback.append("VLM confirms visual layout matches requirements.")
            else:
                feedback.append(f"VLM visual check failed: {parsed.get('details', 'No details')}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic check was strong, give partial credit
            if score >= 60: 
                vlm_score = 15
                feedback.append("VLM unavailable, assumed valid based on file analysis.")
    else:
        feedback.append("No screenshot available for visual check.")

    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }