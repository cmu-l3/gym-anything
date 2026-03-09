#!/usr/bin/env python3
"""
Verifier for Create Interactive Image Map task.

Checks:
1. File exists and was modified.
2. ODP structure contains a `draw:image-map` on the first slide.
3. Image map has at least 3 defined areas (hotspots).
4. Hotspots link to correct targets (Slide 2, Slide 3, Slide 4).
5. VLM verification of trajectory to confirm UI usage.
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_image_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from export script
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result JSON"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # Check 1: File saved/modified (10 pts)
    if not task_result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
    
    if task_result.get('file_modified'):
        score += 10
        feedback_parts.append("File saved successfully")
    else:
        feedback_parts.append("Warning: File timestamp suggests no changes saved")

    # 2. Parse ODP Content (XML)
    odp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(task_result['file_path'], odp_file.name)
        
        with zipfile.ZipFile(odp_file.name, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
        
        # Define namespaces
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'xlink': 'http://www.w3.org/1999/xlink',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
        }
        
        # Find Slide 1
        pages = root.findall('.//draw:page', ns)
        if not pages:
            return {"passed": False, "score": score, "feedback": "Invalid ODP structure (no slides)"}
        
        first_page = pages[0]
        
        # Find ImageMap
        # <draw:image> usually contains <draw:image-map>
        # Note: image might be wrapped in <draw:frame>
        image_maps = first_page.findall('.//draw:image-map', ns)
        
        has_imagemap = False
        hotspot_count = 0
        targets_found = set()
        
        if image_maps:
            has_imagemap = True
            image_map = image_maps[0]
            
            # Count areas (rect, poly, circle, etc)
            # Typically draw:area-rectangle
            areas = list(image_map)
            hotspot_count = len(areas)
            
            # Check targets
            for area in areas:
                href = area.get(f"{{{ns['xlink']}}}href", "").lower()
                # Targets are internal links usually starting with #
                # e.g. #Slide 2, #page2, or unique IDs
                
                # We check for presence of target slide names/numbers in the link
                if "slide 2" in href or "slide2" in href or "page2" in href:
                    targets_found.add("Slide 2")
                elif "slide 3" in href or "slide3" in href or "page3" in href:
                    targets_found.add("Slide 3")
                elif "slide 4" in href or "slide4" in href or "page4" in href:
                    targets_found.add("Slide 4")
        
        # Scoring logic for content
        if has_imagemap:
            score += 30
            feedback_parts.append("ImageMap created")
            
            if hotspot_count >= 3:
                score += 20
                feedback_parts.append(f"Sufficient hotspots ({hotspot_count})")
            else:
                feedback_parts.append(f"Insufficient hotspots ({hotspot_count}/3)")
            
            # Check targets (10 pts each)
            if "Slide 2" in targets_found: score += 10
            if "Slide 3" in targets_found: score += 10
            if "Slide 4" in targets_found: score += 10
            
            # Spatial logic (implicit 10 pts bonus if all distinct targets found)
            if len(targets_found) >= 3:
                score += 10
                feedback_parts.append("All targets correctly linked")
            else:
                feedback_parts.append(f"Missing targets (found: {list(targets_found)})")
        else:
            feedback_parts.append("No ImageMap found on Slide 1")

    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        feedback_parts.append(f"Verification error: {e}")
    finally:
        if os.path.exists(odp_file.name):
            os.unlink(odp_file.name)

    # 3. VLM Verification (Anti-gaming check)
    # Ensure they used the ImageMap Editor, not just transparent buttons (which is a different technique)
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
    
    vlm_prompt = """
    You are verifying if a user created an "ImageMap" in LibreOffice Impress.
    Look at these screenshots of the user's workflow.
    
    Positive signs:
    1. A window titled "ImageMap Editor" is visible.
    2. Green checkmark icon in the toolbar (Apply).
    3. Drawing rectangles on top of an image in a separate editor window.
    
    Did the user appear to use the ImageMap Editor tool?
    Respond in JSON: {"used_editor": true/false, "confidence": "high/med/low"}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if not parsed.get("used_editor", False):
            feedback_parts.append("VLM Note: ImageMap Editor usage not clearly observed")
            # We don't penalize heavily if programmatic check passed, but good for logs
        else:
            feedback_parts.append("VLM confirmed ImageMap Editor usage")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }