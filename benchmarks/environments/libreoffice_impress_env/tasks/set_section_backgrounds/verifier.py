#!/usr/bin/env python3
"""
Verifier for Set Section Backgrounds task in LibreOffice Impress.

Verification Strategy:
1. Parse the ODP file (which is a ZIP of XMLs).
2. Extract background color properties from 'content.xml' and 'styles.xml'.
3. Verify that specific slides have the correct RGB hex colors.
4. Verify slide count and content preservation.
"""

import json
import os
import sys
import zipfile
import tempfile
import logging
import shutil
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces map for ODP XML parsing
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
}

def hex_to_rgb(hex_color: str) -> Tuple[int, int, int]:
    """Convert hex string (#RRGGBB) to (r, g, b) tuple."""
    hex_color = hex_color.lstrip('#')
    if len(hex_color) != 6:
        return (255, 255, 255) # Default/Fallback
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def color_distance(hex1: str, hex2: str) -> float:
    """Calculate Euclidean distance between two hex colors."""
    r1, g1, b1 = hex_to_rgb(hex1)
    r2, g2, b2 = hex_to_rgb(hex2)
    return ((r1 - r2)**2 + (g1 - g2)**2 + (b1 - b2)**2) ** 0.5

def extract_odp_colors(odp_path: str) -> Dict[int, str]:
    """
    Extract background colors for each slide in an ODP file.
    Returns a dict {slide_index_1_based: hex_color_string}.
    Defaults to 'none' if no fill is set.
    """
    slide_colors = {}
    temp_dir = tempfile.mkdtemp()
    
    try:
        with zipfile.ZipFile(odp_path, 'r') as zip_ref:
            zip_ref.extractall(temp_dir)
        
        content_path = os.path.join(temp_dir, 'content.xml')
        if not os.path.exists(content_path):
            logger.error("content.xml not found in ODP")
            return {}

        tree = ET.parse(content_path)
        root = tree.getroot()

        # 1. Map slides (draw:page) to their style names
        slides = []
        # Find all draw:page inside office:presentation
        body = root.find('office:body', NS)
        if body:
            presentation = body.find('office:presentation', NS)
            if presentation:
                for page in presentation.findall('draw:page', NS):
                    style_name = page.get(f"{{{NS['draw']}}}style-name")
                    slides.append(style_name)

        # 2. Extract styles from content.xml (automatic styles)
        styles_map = {} # style_name -> fill_color
        
        # Helper to parse a style element
        def parse_style(style_elem):
            name = style_elem.get(f"{{{NS['style']}}}name")
            props = style_elem.find('style:drawing-page-properties', NS)
            if props is not None:
                fill = props.get(f"{{{NS['draw']}}}fill")
                fill_color = props.get(f"{{{NS['draw']}}}fill-color")
                
                if fill == 'solid' and fill_color:
                    return name, fill_color
                elif fill == 'none':
                    return name, 'none'
            return name, None

        # Check automatic styles in content.xml
        auto_styles = root.find('office:automatic-styles', NS)
        if auto_styles:
            for style_elem in auto_styles.findall('style:style', NS):
                if style_elem.get(f"{{{NS['style']}}}family") == 'drawing-page':
                    name, color = parse_style(style_elem)
                    if color:
                        styles_map[name] = color

        # Check styles in styles.xml (named styles/master pages)
        styles_xml_path = os.path.join(temp_dir, 'styles.xml')
        if os.path.exists(styles_xml_path):
            styles_tree = ET.parse(styles_xml_path)
            styles_root = styles_tree.getroot()
            
            # Look in office:styles
            office_styles = styles_root.find('office:styles', NS)
            if office_styles:
                for style_elem in office_styles.findall('style:style', NS):
                    name, color = parse_style(style_elem)
                    if color:
                        styles_map[name] = color

        # 3. Resolve colors for each slide
        for idx, style_name in enumerate(slides):
            # Check direct style mapping
            color = styles_map.get(style_name, 'none')
            slide_colors[idx + 1] = color

    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
    finally:
        shutil.rmtree(temp_dir)
        
    return slide_colors

def verify_section_backgrounds(traj, env_info, task_info):
    """
    Verify that background colors are correctly applied to specific sections.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_reqs = metadata.get('requirements', [])
    color_tolerance = metadata.get('color_tolerance', 40) # RGB distance tolerance
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get task result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    
    if not task_result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
        
    if not task_result.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task (timestamp check failed)"}

    score += 10 # File valid and modified
    feedback_parts.append("File preserved and modified")

    # 2. Get ODP file for analysis
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(task_result['file_path'], temp_odp.name)
        slide_colors = extract_odp_colors(temp_odp.name)
    except Exception as e:
        os.unlink(temp_odp.name)
        return {"passed": False, "score": 10, "feedback": f"Failed to parse ODP file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # 3. Verify Slide Count
    slide_count = len(slide_colors)
    if slide_count == 7:
        score += 5
        feedback_parts.append("Slide count correct (7)")
    else:
        feedback_parts.append(f"Incorrect slide count: {slide_count} (expected 7)")

    # 4. Verify Colors
    # Requirements: 
    # Title (1): none
    # Revenue (2,3): #C8E6C9
    # Challenges (4,5): #FFF9C4
    # Next Steps (6,7): #BBDEFB
    
    colors_correct = 0
    total_slides_to_check = 7
    
    distinct_colors = set()

    for req in expected_reqs:
        target_indices = req['slides']
        target_color_hex = req['color']
        section_name = req['name']
        
        section_passed = True
        
        for idx in target_indices:
            actual_color = slide_colors.get(idx, 'none')
            distinct_colors.add(actual_color)
            
            # Special case for 'none' (default white/transparent)
            if target_color_hex.lower() == 'none':
                # Accept 'none' or white
                is_match = actual_color == 'none' or actual_color.lower() == '#ffffff'
            else:
                # Color distance check
                if actual_color == 'none':
                    is_match = False
                else:
                    dist = color_distance(target_color_hex, actual_color)
                    is_match = dist <= color_tolerance
            
            if is_match:
                colors_correct += 1
            else:
                section_passed = False
                feedback_parts.append(f"Slide {idx} ({section_name}) wrong color: got {actual_color}, expected {target_color_hex}")

        if section_passed:
            # Award points based on section weight
            # Total color points = 75 (Title: 5, Others: 20 each)
            if section_name == "Title":
                score += 5
            else:
                score += 20
    
    # Check differentiation (Anti-gaming: did they just set everything to green?)
    if len(distinct_colors) < 3:
        score = min(score, 40) # Cap score if no differentiation
        feedback_parts.append("⚠️ Sections not visually distinct")
    else:
        score += 10 # Bonus for differentiation
        feedback_parts.append("Sections visually distinct")

    passed = score >= 60 and len(distinct_colors) >= 3

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }