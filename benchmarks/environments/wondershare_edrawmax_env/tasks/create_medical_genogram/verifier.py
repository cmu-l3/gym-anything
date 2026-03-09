#!/usr/bin/env python3
"""
Verifier for create_medical_genogram task.
Verifies the existence and content of a medical genogram file.
"""

import json
import os
import tempfile
import zipfile
import logging
import re
from typing import Dict, Any, List

# Import VLM utils provided by the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing if gym_anything is not available
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_text_from_eddx(file_path: str) -> str:
    """Extracts all text content from an .eddx file (which is a zip of XMLs)."""
    text_content = ""
    try:
        with zipfile.ZipFile(file_path, "r") as zf:
            for name in zf.namelist():
                if name.endswith(".xml"):
                    try:
                        # EdrawMax text is often in <Text> tags or just plain text within shapes
                        content = zf.read(name).decode("utf-8", errors="ignore")
                        text_content += content + "\n"
                    except Exception:
                        pass
    except Exception as e:
        logger.error(f"Failed to read eddx file: {e}")
    return text_content

def verify_create_medical_genogram(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies the medical genogram task.
    
    Criteria:
    1. Files (.eddx and .png) exist and were created during task.
    2. EDDX file contains correct names and medical info.
    3. VLM verifies the visual structure (tree hierarchy, symbols).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON from export_result.sh
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify File Existence & Anti-Gaming (20 pts)
    eddx_exists = task_result.get('eddx_exists', False)
    eddx_fresh = task_result.get('eddx_created_during_task', False)
    png_exists = task_result.get('png_exists', False)
    png_fresh = task_result.get('png_created_during_task', False)

    if eddx_exists and eddx_fresh:
        score += 15
        feedback_parts.append("Genogram file (.eddx) created.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("Genogram file exists but timestamp suggests it wasn't created during this session.")
    else:
        feedback_parts.append("Genogram file (.eddx) not found.")

    if png_exists and png_fresh:
        score += 5
        feedback_parts.append("Image export (.png) created.")
    elif png_exists:
        score += 2
        feedback_parts.append("Image export exists (old timestamp).")
    
    # 3. Verify Content in EDDX (40 pts)
    content_score = 0
    missing_items = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(metadata.get('expected_eddx_path'), temp_eddx.name)
            file_text = extract_text_from_eddx(temp_eddx.name)
            
            # Check for required strings
            found_count = 0
            for item in required_text:
                if item.lower() in file_text.lower():
                    found_count += 1
                else:
                    missing_items.append(item)
            
            # Calculate content score based on percentage of found items
            if len(required_text) > 0:
                content_percentage = found_count / len(required_text)
                content_score = int(40 * content_percentage)
                score += content_score
                
            if found_count == len(required_text):
                feedback_parts.append("All names, ages, and conditions found in file.")
            else:
                feedback_parts.append(f"Missing text info: {', '.join(missing_items[:3])}...")
                
        except Exception as e:
            feedback_parts.append(f"Error checking file content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("Cannot verify content (file missing).")

    # 4. VLM Verification of Visual Structure (40 pts)
    # Uses trajectory frames + final screenshot
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        all_images = frames + [final_shot]
        
        prompt = """
        You are verifying a "Medical Genogram" task. 
        Look at the images to check for a family tree diagram.
        
        Criteria:
        1. Is there a tree structure with 3 distinct generations (vertical levels)?
        2. Are there squares (males) and circles (females)?
        3. Is there a specific person marked with "Heart Disease" or colored/shaded differently?
        4. Is there a person marked as deceased (crossed out)?
        
        Answer with a JSON object:
        {
            "tree_structure_visible": true/false,
            "generations_count_approx": 3,
            "gender_shapes_visible": true/false,
            "condition_marked": true/false,
            "deceased_marker_visible": true/false,
            "score": <0-40 based on criteria>
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=all_images)
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            vlm_score = parsed.get("score", 0)
            score += vlm_score
            
            checks = []
            if parsed.get("tree_structure_visible"): checks.append("Tree Structure")
            if parsed.get("gender_shapes_visible"): checks.append("Gender Shapes")
            if parsed.get("condition_marked"): checks.append("Condition Marked")
            
            feedback_parts.append(f"Visual Verification ({vlm_score}/40): {', '.join(checks)} verified.")
        else:
            feedback_parts.append("VLM verification failed to run.")
            # Fallback: if file content score was high, give partial credit
            if content_score > 30:
                score += 20
                feedback_parts.append("Awarding partial visual credit based on strong text content.")

    # Final logic
    passed = score >= 60 and eddx_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }