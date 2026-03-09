#!/usr/bin/env python3
"""
Verifier for create_datacenter_floorplan task.

Verification Strategy:
1. File Verification (40 pts):
   - Check .eddx and .png files exist and were created during task.
   - Inspect .eddx (zip) content for required text labels (Robust programmatic check).
2. VLM Verification (60 pts):
   - Process: Did agent build a floor plan? (Trajectory)
   - Content: Does final image show racks, layout, specific components?
"""

import os
import json
import tempfile
import zipfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_eddx_content(eddx_path, required_labels):
    """
    Unzips the .eddx file and searches XML content for required labels.
    Returns a tuple (score, found_labels, missing_labels).
    """
    found_labels = []
    missing_labels = []
    
    if not zipfile.is_zipfile(eddx_path):
        return 0, [], required_labels

    try:
        with zipfile.ZipFile(eddx_path, 'r') as zf:
            # EdrawMax files store text in page XMLs
            xml_content = ""
            for name in zf.namelist():
                if name.endswith('.xml'):
                    try:
                        xml_content += zf.read(name).decode('utf-8', errors='ignore')
                    except:
                        pass
            
            # Normalize content for search
            xml_content_lower = xml_content.lower()
            
            for label in required_labels:
                # Simple case-insensitive search
                if label.lower() in xml_content_lower:
                    found_labels.append(label)
                else:
                    missing_labels.append(label)
                    
    except Exception as e:
        logger.error(f"Error reading eddx: {e}")
        return 0, [], required_labels

    # Calculate score based on percentage of found labels
    if not required_labels:
        return 100, [], []
        
    score = (len(found_labels) / len(required_labels)) * 100
    return score, found_labels, missing_labels

def verify_create_datacenter_floorplan(traj, env_info, task_info):
    """
    Verifies the data center floor plan creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])
    
    # Load task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. FILE VERIFICATION (40 pts max)
    # ---------------------------------------------------------
    
    # Check EDDX
    eddx_valid = False
    if result_data.get('eddx_exists') and result_data.get('eddx_created_during_task'):
        if result_data.get('eddx_size_bytes', 0) > metadata.get('min_eddx_size_bytes', 1000):
            score += 10
            feedback_parts.append("EDDX file created successfully.")
            eddx_valid = True
        else:
            feedback_parts.append("EDDX file too small (likely empty).")
    else:
        feedback_parts.append("EDDX file missing or not created during task.")

    # Check PNG
    if result_data.get('png_exists') and result_data.get('png_created_during_task'):
        if result_data.get('png_size_bytes', 0) > metadata.get('min_png_size_bytes', 5000):
            score += 10
            feedback_parts.append("PNG export created successfully.")
        else:
            feedback_parts.append("PNG export too small.")
    else:
        feedback_parts.append("PNG export missing.")

    # Check Content (Programmatic Text Search in EDDX) - 20 pts
    if eddx_valid:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(metadata['expected_eddx_path'], temp_eddx.name)
            content_score, found, missing = check_eddx_content(temp_eddx.name, required_labels)
            
            # Map content score (0-100) to points (0-20)
            points = (content_score / 100) * 20
            score += points
            
            if missing:
                feedback_parts.append(f"Missing labels in diagram: {', '.join(missing[:3])}...")
            if len(found) >= 3:
                feedback_parts.append(f"Found labels: {', '.join(found[:3])}...")
                
        except Exception as e:
            feedback_parts.append(f"Failed to inspect EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("Skipping content check (EDDX invalid).")

    # ---------------------------------------------------------
    # 2. VLM VERIFICATION (60 pts max)
    # ---------------------------------------------------------
    
    # Sample trajectory frames
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " (No screenshots available for VLM)"}

    prompt = """
    You are verifying a Data Center Floor Plan creation task in EdrawMax.
    
    Review the sequence of images. The user should be building a floor plan diagram.
    
    Check for the following criteria:
    1. **Layout**: Is there a rectangular room layout visible?
    2. **Racks**: Are there multiple server rack shapes (rectangles) arranged in a grid/rows?
    3. **Equipment**: Do you see cooling units (CRAC) or other infrastructure symbols?
    4. **Text/Labels**: Are there text labels visible (e.g., "Rack", "Aisle", "Room 101")?
    5. **Progression**: Do the images show a progression of adding shapes (not just a static final screen)?
    
    Output JSON:
    {
        "layout_visible": boolean,
        "racks_visible": boolean,
        "equipment_visible": boolean,
        "labels_visible": boolean,
        "progression_visible": boolean,
        "confidence": float (0-1),
        "explanation": "string"
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {})
            
            # Scoring rubric for VLM (60 pts total)
            vlm_score = 0
            
            if analysis.get('layout_visible'): vlm_score += 10
            if analysis.get('racks_visible'): vlm_score += 15
            if analysis.get('equipment_visible'): vlm_score += 10
            if analysis.get('labels_visible'): vlm_score += 10
            if analysis.get('progression_visible'): vlm_score += 15
            
            # Adjust by confidence
            confidence = analysis.get('confidence', 1.0)
            vlm_score *= confidence
            
            score += vlm_score
            feedback_parts.append(f"Visual Verification: {analysis.get('explanation')}")
        else:
            feedback_parts.append("VLM analysis failed.")
            
    except Exception as e:
        feedback_parts.append(f"VLM error: {str(e)}")

    # Final tally
    passed = score >= 60 and result_data.get('eddx_exists') and result_data.get('png_exists')
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }