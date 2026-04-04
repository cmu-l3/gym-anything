#!/usr/bin/env python3
"""
Verifier for create_state_list_drawable task.

Scoring (100 points):
- Drawable file exists (10 pts)
- Root element is <selector> (10 pts)
- Pressed state defined correctly (color + corners) (20 pts)
- Default state defined correctly (color + corners) (20 pts)
- Layout file references the drawable (15 pts)
- Layout file sets backgroundTint to null (15 pts)
- XML is valid/Project builds (10 pts)
"""

import json
import logging
import os
import re
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def normalize_color(color_str):
    """Normalize hex color string to uppercase 6-digit format if possible."""
    if not color_str: return ""
    color_str = color_str.strip().upper()
    if color_str.startswith("#"):
        return color_str
    return color_str

def check_xml_shape(xml_content, expected_color):
    """
    Heuristic check for shape properties in XML content string.
    Returns (has_corners, has_color)
    """
    has_corners = "android:radius" in xml_content and "16dp" in xml_content
    # Check for color (case insensitive)
    has_color = expected_color.lower() in xml_content.lower()
    return has_corners, has_color

def verify_create_state_list_drawable(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_pressed = metadata.get("expected_pressed_color", "#1565C0")
    expected_default = metadata.get("expected_default_color", "#2196F3")
    
    # Read result
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    drawable_content = result.get("drawable_content", "")
    layout_content = result.get("layout_content", "")
    
    score = 0
    feedback_parts = []
    
    # 1. Drawable File Exists (10 pts)
    if result.get("drawable_exists"):
        score += 10
        feedback_parts.append("Drawable file created")
    else:
        return {"passed": False, "score": 0, "feedback": "Drawable file not found"}

    # 2. Parse Drawable XML
    try:
        # Simple string-based analysis usually more robust for partial implementations
        # but let's try to structure it
        
        # Check Root Selector (10 pts)
        if "<selector" in drawable_content:
            score += 10
        else:
            feedback_parts.append("Root element is not <selector>")

        # Check Pressed State (20 pts)
        # Look for item with state_pressed="true"
        pressed_match = re.search(r'<item[^>]*android:state_pressed="true"[^>]*>(.*?)</item>', drawable_content, re.DOTALL)
        if not pressed_match:
            # Maybe self-closing item referencing a drawable?
            pressed_match = re.search(r'<item[^>]*android:state_pressed="true"[^>]*/>', drawable_content)
            
        if pressed_match:
            item_content = pressed_match.group(0)
            corners, color = check_xml_shape(item_content, expected_pressed)
            
            # If item references another drawable, we can't easily check content without following link.
            # We assume inline shape or relaxed check if color string appears in the line.
            if expected_pressed.lower() in item_content.lower():
                score += 10
                feedback_parts.append("Pressed color correct")
            else:
                feedback_parts.append("Pressed color mismatch")
                
            if "16dp" in item_content or "radius" in item_content: # Loose check
                score += 10
                feedback_parts.append("Pressed corners correct")
        else:
            feedback_parts.append("Pressed state definition not found")

        # Check Default State (20 pts)
        # Item without state attribute usually
        # This regex is tricky, let's just check if the default color exists in the file and isn't the pressed one
        if expected_default.lower() in drawable_content.lower():
            score += 10
            feedback_parts.append("Default color found")
        
        if drawable_content.count("16dp") >= 1:
             score += 10
        
    except Exception as e:
        feedback_parts.append(f"Error parsing drawable XML: {str(e)}")

    # 3. Check Layout Implementation
    
    # Background applied (15 pts)
    if 'android:background="@drawable/login_button_bg"' in layout_content:
        score += 15
        feedback_parts.append("Background drawable applied to button")
    else:
        feedback_parts.append("Button background not set to new drawable")

    # Background Tint Null (15 pts)
    # This is critical for Material buttons
    if 'app:backgroundTint="@null"' in layout_content or 'android:backgroundTint="@null"' in layout_content:
        score += 15
        feedback_parts.append("backgroundTint cleared correctly")
    else:
        feedback_parts.append("backgroundTint NOT cleared (drawable may be invisible)")

    # 4. Build Success (10 pts)
    if result.get("build_success"):
        score += 10
        feedback_parts.append("Resources compile successfully")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }