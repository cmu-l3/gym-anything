#!/usr/bin/env python3
"""
Verifier for format_planetary_image_grid task.
Parses ODP file to verify image count, dimensions, positioning, and borders.
"""

import json
import tempfile
import os
import zipfile
import logging
import math
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odp_content(odp_path):
    """
    Extracts and parses content.xml from an ODP file.
    Returns a list of image frame objects with attributes.
    """
    if not os.path.exists(odp_path):
        return None

    try:
        with zipfile.ZipFile(odp_path, 'r') as z:
            content_xml = z.read('content.xml')
        
        root = ET.fromstring(content_xml)
        
        # Namespaces in ODF
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
            'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
        }
        
        # 1. Parse Styles to look up properties (like borders)
        # Styles can be in automatic-styles or styles (less common for direct formatting)
        styles = {}
        for style_node in root.findall('.//style:style', ns):
            style_name = style_node.get(f"{{{ns['style']}}}name")
            graphic_props = style_node.find('style:graphic-properties', ns)
            if graphic_props is not None:
                props = {}
                # Stroke (Border style)
                props['stroke'] = graphic_props.get(f"{{{ns['draw']}}}stroke")
                props['stroke_width'] = graphic_props.get(f"{{{ns['svg']}}}stroke-width")
                props['stroke_color'] = graphic_props.get(f"{{{ns['svg']}}}stroke-color")
                styles[style_name] = props

        # 2. Find Image Frames
        image_frames = []
        # Look for draw:frame that contains draw:image
        for frame in root.findall('.//draw:frame', ns):
            image_node = frame.find('draw:image', ns)
            if image_node is not None:
                # Get geometry
                width = frame.get(f"{{{ns['svg']}}}width")
                height = frame.get(f"{{{ns['svg']}}}height")
                x = frame.get(f"{{{ns['svg']}}}x")
                y = frame.get(f"{{{ns['svg']}}}y")
                style_ref = frame.get(f"{{{ns['draw']}}}style-name")
                
                # Resolve style
                frame_style = styles.get(style_ref, {})
                
                image_frames.append({
                    'width': width,
                    'height': height,
                    'x': x,
                    'y': y,
                    'style': frame_style
                })
                
        return image_frames
        
    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        return []

def parse_measure(value_str):
    """Converts ODF measurement string (e.g. '5cm', '2.5in') to cm float."""
    if not value_str:
        return 0.0
    
    value_str = value_str.lower().strip()
    try:
        if value_str.endswith('cm'):
            return float(value_str[:-2])
        elif value_str.endswith('mm'):
            return float(value_str[:-2]) / 10.0
        elif value_str.endswith('in'):
            return float(value_str[:-2]) * 2.54
        elif value_str.endswith('pt'):
            return float(value_str[:-2]) * 0.0352778
        else:
            # Fallback/assume cm or unitless
            return float(value_str)
    except ValueError:
        return 0.0

def verify_planetary_grid(traj, env_info, task_info):
    """
    Verifies:
    1. File exists and modified
    2. 4 images present
    3. Dimensions ~5cm x 5cm
    4. Border applied (solid, blue, ~2pt)
    5. Grid arrangement (2 rows, 2 cols)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to load result JSON"}
    finally:
        os.unlink(temp_result.name)

    if not result.get('output_exists') or not result.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file not found or not created during task"}

    # Copy ODP file for parsing
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(result['output_path'], temp_odp.name)
        frames = parse_odp_content(temp_odp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse ODP file: {str(e)}"}
    finally:
        os.unlink(temp_odp.name)

    if frames is None:
        return {"passed": False, "score": 0, "feedback": "Failed to parse ODP XML content"}

    feedback_parts = []
    score = 10 # Base score for file existing
    
    # 1. Image Count (Max 20 pts)
    count = len(frames)
    if count == 4:
        score += 20
        feedback_parts.append("✅ 4 images found")
    else:
        feedback_parts.append(f"❌ Found {count} images (expected 4)")
    
    # 2. Dimensions (Max 30 pts)
    # Target 5cm +/- 0.1cm
    correct_dims = 0
    for f in frames:
        w = parse_measure(f['width'])
        h = parse_measure(f['height'])
        # 5.0 cm +/- 0.15
        if 4.85 <= w <= 5.15 and 4.85 <= h <= 5.15:
            correct_dims += 1
    
    if correct_dims == 4:
        score += 30
        feedback_parts.append("✅ All images sized 5x5cm")
    elif correct_dims > 0:
        score += int(30 * (correct_dims / 4))
        feedback_parts.append(f"⚠️ {correct_dims}/4 images correctly sized")
    else:
        feedback_parts.append("❌ Image dimensions incorrect")

    # 3. Borders (Max 20 pts)
    # Check for stroke="solid", blue color, width approx 2pt (0.07cm)
    correct_borders = 0
    for f in frames:
        style = f.get('style', {})
        stroke = style.get('stroke', 'none')
        color = style.get('stroke_color', '#000000')
        width = parse_measure(style.get('stroke_width', '0'))
        
        # Checks
        has_stroke = stroke != 'none'
        is_blue = False
        if color:
            color = color.lower()
            # Crude blue check: ends in high blue hex or typical blue names
            if color in ['#0000ff', '#000080', 'blue', 'darkblue'] or (len(color)==7 and color[5:7] > color[1:3]):
                is_blue = True
        
        # 2pt is approx 0.07cm. Allow range 0.05 - 0.10 cm
        is_width_ok = 0.05 <= width <= 0.15
        
        if has_stroke and is_blue and is_width_ok:
            correct_borders += 1
            
    if correct_borders >= 3: # Allow one mistake
        score += 20
        feedback_parts.append("✅ Blue borders applied")
    elif correct_borders > 0:
        score += 10
        feedback_parts.append(f"⚠️ {correct_borders}/4 borders correct")
    else:
        feedback_parts.append("❌ Borders missing or incorrect")

    # 4. Grid Layout (Max 20 pts)
    # Sort by Y then X to check structure
    # We expect 2 roughly distinct Y levels, and 2 roughly distinct X levels
    if count == 4:
        x_coords = sorted([parse_measure(f['x']) for f in frames])
        y_coords = sorted([parse_measure(f['y']) for f in frames])
        
        # Check Y separation (Row 1 vs Row 2)
        # Average of first 2 vs Average of last 2 should be > 5cm
        y_gap = (y_coords[2] + y_coords[3])/2 - (y_coords[0] + y_coords[1])/2
        
        # Check X separation (Col 1 vs Col 2)
        # We need to pair them properly to be sure, but simple distribution check is usually enough
        # X coords should cluster into two groups
        x_gap = (x_coords[2] + x_coords[3])/2 - (x_coords[0] + x_coords[1])/2
        
        if y_gap > 4.0 and x_gap > 4.0:
            score += 20
            feedback_parts.append("✅ Grid layout detected")
        else:
            feedback_parts.append(f"❌ Layout does not look like a grid (gaps: X={x_gap:.1f}, Y={y_gap:.1f})")

    passed = score >= 70 and correct_dims >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }