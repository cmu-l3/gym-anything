#!/usr/bin/env python3
"""
Verifier for Create Risk Matrix Slide task.
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil
from xml.dom import minidom
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_risk_matrix_slide(traj, env_info, task_info):
    """
    Verify the Risk Matrix task using:
    1. ODP File Parsing (Structure, Content, Colors)
    2. VLM Verification (Visual correctness, Spatial logic)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            basic_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not basic_result.get("file_exists") or not basic_result.get("file_modified"):
        return {"passed": False, "score": 0, "feedback": "Presentation file not modified or not found."}

    # 2. Extract and Parse ODP Content
    score = 0
    feedback_parts = []
    
    # Copy ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(basic_result["target_path"], temp_odp.name)
        
        # ODP is a zip file. Extract content.xml
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml')
            
        dom = minidom.parseString(content_xml)
        
        # --- CHECK 1: Slide Count (10 pts) ---
        slides = dom.getElementsByTagName('draw:page')
        if len(slides) >= 2:
            score += 10
            feedback_parts.append(f"✅ Created new slide (Total: {len(slides)})")
            target_slide = slides[1] # Assuming 2nd slide is the risk matrix
        else:
            feedback_parts.append("❌ Failed to create new slide")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # --- CHECK 2: Text Content (20 pts) ---
        # Extract all text from the target slide
        slide_text = []
        for text_node in target_slide.getElementsByTagName('text:p'):
            if text_node.firstChild and text_node.firstChild.nodeType == text_node.TEXT_NODE:
                slide_text.append(text_node.firstChild.data)
            # Handle spans
            for span in text_node.getElementsByTagName('text:span'):
                if span.firstChild:
                    slide_text.append(span.firstChild.data)
                    
        full_text = " ".join(slide_text)
        required_terms = [
            ("Impact", 5), 
            ("Probability", 5), 
            ("Cloud Migration", 5), 
            ("Staff Training", 5),
            ("Hardware Cost", 5) # partial match ok
        ]
        
        text_score = 0
        for term, points in required_terms:
            if term.lower() in full_text.lower():
                text_score += points
        
        score += text_score
        if text_score >= 20:
            feedback_parts.append("✅ All required labels present")
        elif text_score > 0:
            feedback_parts.append(f"⚠️ Some labels missing (Score: {text_score}/25)")
        else:
            feedback_parts.append("❌ No required labels found")

        # --- CHECK 3: Matrix Construction (Shapes & Colors) (30 pts) ---
        # Look for rectangles
        rects = target_slide.getElementsByTagName('draw:rect')
        custom_shapes = target_slide.getElementsByTagName('draw:custom-shape')
        total_shapes = len(rects) + len(custom_shapes)
        
        if total_shapes >= 4:
            score += 10
            feedback_parts.append("✅ Matrix structure detected (4+ shapes)")
        else:
            feedback_parts.append(f"⚠️ Matrix structure unclear (Found {total_shapes} shapes)")

        # Deep color verification is hard without resolving styles, 
        # so we'll inspect styles.xml or automatic styles in content.xml for RGB colors
        # We look for fill colors in the XML string roughly
        style_content = content_xml.decode('utf-8') + styles_xml.decode('utf-8')
        
        colors_found = []
        # Check for standard hex colors often used for R/G/B/Y
        # Red-ish
        if "#ff0000" in style_content.lower() or "#cc0000" in style_content.lower() or "#e06666" in style_content.lower():
            colors_found.append("Red")
        # Green-ish
        if "#00ff00" in style_content.lower() or "#008000" in style_content.lower() or "#6aa84f" in style_content.lower():
            colors_found.append("Green")
        # Yellow/Orange
        if "#ffff00" in style_content.lower() or "#ffa500" in style_content.lower() or "#f1c232" in style_content.lower():
            colors_found.append("Yellow/Orange")
            
        if len(colors_found) >= 2:
            score += 20
            feedback_parts.append(f"✅ Semantic colors detected: {', '.join(colors_found)}")
        else:
            feedback_parts.append("⚠️ Could not strictly verify specific fill colors in XML")

    except Exception as e:
        logger.error(f"ODP parsing failed: {e}")
        feedback_parts.append("⚠️ Failed to parse presentation file structure")

    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # 3. VLM Verification (40 pts)
    # Use VLM to verify the visual arrangement which is hard to parse from XML
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = """
        Analyze this slide presentation screenshot. The user is supposed to create a 'Risk Matrix' slide.
        
        Check for:
        1. A 2x2 colored grid (Matrix).
        2. Colors: One quadrant Red, one Green, two Yellow/Orange.
        3. Text 'Cloud Migration' located in the RED zone (High Impact/High Prob).
        4. Text 'Staff Training' located in the GREEN zone (Low Impact/Low Prob).
        
        JSON Response:
        {
            "matrix_visible": true/false,
            "colors_correct": true/false,
            "cloud_in_red": true/false,
            "staff_in_green": true/false,
            "score_0_to_40": <int>
        }
        """
        
        vlm_res = query_vlm(prompt=vlm_prompt, image=final_screen)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = parsed.get("score_0_to_40", 0)
            score += vlm_score
            
            checks = []
            if parsed.get("matrix_visible"): checks.append("Matrix Visible")
            if parsed.get("colors_correct"): checks.append("Colors Correct")
            if parsed.get("cloud_in_red"): checks.append("Risks Plotted Correctly")
            
            feedback_parts.append(f"👁️ Visual Verification: {', '.join(checks)}")
        else:
            feedback_parts.append("⚠️ Visual verification failed to run")

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }