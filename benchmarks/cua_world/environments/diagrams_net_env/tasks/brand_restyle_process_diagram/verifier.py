#!/usr/bin/env python3
"""
Verifier for brand_restyle_process_diagram task.
Parses the .drawio XML and checks style attributes against brand guidelines.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Brand colors (case-insensitive)
NAVY = "1B365D"
ORANGE = "E87722"
SKY_BLUE = "00A3E0"
DARK_GRAY = "4A4A4A"
WHITE = "FFFFFF"


def parse_style(style_str):
    """Parse a draw.io style string into a dict."""
    if not style_str:
        return {}
    result = {}
    for part in style_str.split(";"):
        part = part.strip()
        if "=" in part:
            k, v = part.split("=", 1)
            result[k.strip()] = v.strip()
        elif part:
            result[part] = True
    return result


def color_match(actual, expected):
    """Check if color matches (case-insensitive, with or without #)."""
    if not actual:
        return False
    actual = actual.strip().lstrip("#").upper()
    expected = expected.upper()
    return actual == expected


def verify_brand_restyle(traj, env_info, task_info):
    """
    Verify the brand restyle task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
    result_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    # 2. Retrieve final diagram XML
    diagram_xml_path = tempfile.mktemp(suffix=".drawio")
    try:
        copy_from_env("/tmp/final_diagram.drawio", diagram_xml_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Diagram file could not be retrieved (may not exist)"}

    # 3. Parse XML
    try:
        tree = ET.parse(diagram_xml_path)
        root = tree.getroot()
    except ET.ParseError:
        os.unlink(diagram_xml_path)
        return {"passed": False, "score": 0, "feedback": "Final diagram is not valid XML"}

    os.unlink(diagram_xml_path)

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # 4. Analyze Styling
    cells = root.findall(".//mxCell")
    
    # Categories (ID sets based on setup_task.sh)
    process_ids = {f"p{i}" for i in range(1, 15)}
    decision_ids = {"d1", "d2", "d3", "d4"}
    terminator_ids = {"start1", "end1"}
    
    navy_count = 0
    orange_count = 0
    blue_count = 0
    white_font_count = 0
    rounded_count = 0
    shadow_count = 0
    stroke_color_count = 0
    stroke_width_count = 0
    
    total_shapes_checked = 0
    total_edges_checked = 0

    for cell in cells:
        cid = cell.get("id", "")
        style = cell.get("style", "")
        sd = parse_style(style)
        
        # Check Fills
        fill = sd.get("fillColor", "")
        font_color = sd.get("fontColor", "")
        
        if cid in process_ids:
            total_shapes_checked += 1
            if color_match(fill, NAVY): navy_count += 1
            if sd.get("rounded") == "1" or sd.get("rounded") is True: rounded_count += 1
            if color_match(font_color, WHITE): white_font_count += 1
            if sd.get("shadow") == "1" or sd.get("shadow") is True: shadow_count += 1
            
        elif cid in decision_ids:
            total_shapes_checked += 1
            if color_match(fill, ORANGE): orange_count += 1
            if color_match(font_color, WHITE): white_font_count += 1
            if sd.get("shadow") == "1" or sd.get("shadow") is True: shadow_count += 1
            
        elif cid in terminator_ids:
            total_shapes_checked += 1
            if color_match(fill, SKY_BLUE): blue_count += 1
            if color_match(font_color, WHITE): white_font_count += 1
            if sd.get("shadow") == "1" or sd.get("shadow") is True: shadow_count += 1
            
        elif "edge" in style or cell.get("edge") == "1":
            total_edges_checked += 1
            if color_match(sd.get("strokeColor", ""), DARK_GRAY): stroke_color_count += 1
            if sd.get("strokeWidth", "") == "2": stroke_width_count += 1

    # Scoring Logic
    
    # File Modification (5 pts)
    if res_data.get("file_modified", False):
        score += 5
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified")

    # Exports (10 pts)
    if res_data.get("png_exists"):
        score += 5
        feedback_parts.append("PNG exported")
    if res_data.get("pdf_exists"):
        score += 5
        feedback_parts.append("PDF exported")

    # Process Steps Navy Fill (15 pts) - Need 10/14
    if navy_count >= 10:
        score += 15
        feedback_parts.append(f"Process steps navy ({navy_count}/14)")
    elif navy_count >= 5:
        score += 7
        feedback_parts.append(f"Process steps partial ({navy_count}/14)")
        
    # Decision Orange Fill (12 pts) - Need 3/4
    if orange_count >= 3:
        score += 12
        feedback_parts.append(f"Decisions orange ({orange_count}/4)")
    elif orange_count >= 1:
        score += 5
        feedback_parts.append(f"Decisions partial ({orange_count}/4)")

    # Terminator Sky Blue Fill (8 pts) - Need 2/2
    if blue_count >= 2:
        score += 8
        feedback_parts.append("Terminators blue")
    elif blue_count >= 1:
        score += 4
        feedback_parts.append("Terminators partial")
        
    # White Font (10 pts) - Need 15 total
    if white_font_count >= 15:
        score += 10
        feedback_parts.append("Font colors correct")
        
    # Rounded Corners (8 pts) - Need 10 rectangles
    if rounded_count >= 10:
        score += 8
        feedback_parts.append("Rounded corners applied")
        
    # Shadows (7 pts) - Need 15 shapes
    if shadow_count >= 15:
        score += 7
        feedback_parts.append("Shadows applied")
        
    # Connectors (13 pts)
    if total_edges_checked > 0:
        if stroke_color_count >= 15:
            score += 8
            feedback_parts.append("Connector colors correct")
        if stroke_width_count >= 15:
            score += 5
            feedback_parts.append("Connector width correct")
            
    # Structure Integrity (5 pts)
    # Ensure didn't delete everything
    if total_shapes_checked >= 15:
        score += 7  # Bonus for keeping structure
        feedback_parts.append("Structure preserved")
    else:
        feedback_parts.append("WARNING: Many shapes missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }