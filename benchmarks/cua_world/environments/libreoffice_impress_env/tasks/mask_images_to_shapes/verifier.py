#!/usr/bin/env python3
"""
Verifier for Mask Images to Shapes task.

Verification Logic:
1. Parse the ODP file structure.
2. Navigate to Slide 2.
3. Check for absence of standard <draw:frame><draw:image> structures (rectangular images).
4. Check for presence of <draw:custom-shape> or <draw:path> elements (vector shapes).
5. Verify these shapes have a bitmap fill (meaning they contain an image).
6. Verify aspect ratio is approximately 1:1 (circular).
7. Anti-gaming: File must be modified.
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces for ODF parsing
NS = {
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
}

def verify_mask_images_to_shapes(traj, env_info, task_info):
    """
    Verify that images on Slide 2 have been masked into circular shapes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
    
    if not result_data.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not modified/saved"}

    # Retrieve ODP file
    odp_path = result_data['file_path']
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(odp_path, temp_odp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ODP file: {e}"}

    score = 0
    feedback_parts = []
    
    try:
        # Parse ODP
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
            
            # styles.xml is also needed for fill styles sometimes, but often they are in content.xml's automatic-styles
            # We will check content.xml first.

        # Find Slide 2
        # <office:body><office:presentation><draw:page>...
        pages = root.findall('.//draw:page', NS)
        if len(pages) < 2:
            return {"passed": False, "score": 0, "feedback": "Presentation has fewer than 2 slides"}
        
        target_slide = pages[1] # Slide 2 (0-indexed 1)
        
        # 1. Check for remaining rectangular images (draw:frame containing draw:image)
        # In ODP, a standard image is a draw:frame with a draw:image child.
        # When intersected, it becomes a draw:path or draw:custom-shape.
        
        rect_images = []
        for frame in target_slide.findall('.//draw:frame', NS):
            if frame.find('draw:image', NS) is not None:
                rect_images.append(frame)
        
        if len(rect_images) == 0:
            score += 30
            feedback_parts.append("✅ All rectangular images converted")
        elif len(rect_images) < 3:
            score += 15
            feedback_parts.append(f"⚠️ Some rectangular images remain ({len(rect_images)})")
        else:
            feedback_parts.append("❌ Rectangular images still present")

        # 2. Check for new shapes (custom-shape or path)
        # These are the result of the boolean operation
        shapes = []
        shapes.extend(target_slide.findall('.//draw:custom-shape', NS))
        shapes.extend(target_slide.findall('.//draw:path', NS))
        # Sometimes circles are draw:circle if user just drew a circle, but an intersection usually makes a path/custom-shape
        
        valid_shapes = []
        
        for shape in shapes:
            # Check geometry/aspect ratio
            # attributes: svg:width, svg:height, svg:x, svg:y
            width_str = shape.get(f"{{{NS['svg']}}}width", "0cm")
            height_str = shape.get(f"{{{NS['svg']}}}height", "0cm")
            
            w = parse_measure(width_str)
            h = parse_measure(height_str)
            
            if w > 0 and h > 0:
                ratio = w / h
                # Circular tolerance 0.85 - 1.15
                if 0.85 <= ratio <= 1.15:
                    valid_shapes.append(shape)
        
        if len(valid_shapes) >= 3:
            score += 40
            feedback_parts.append("✅ 3+ circular shapes found")
        elif len(valid_shapes) > 0:
            score += 10 * len(valid_shapes)
            feedback_parts.append(f"⚠️ Found {len(valid_shapes)} circular shapes (expected 3)")
        else:
            feedback_parts.append("❌ No circular shapes found")

        # 3. Check for bitmap fill (Image content)
        # This requires checking the style referenced by draw:style-name
        # The style should contain <style:graphic-properties draw:fill="bitmap" ... />
        
        automatic_styles = root.find('.//office:automatic-styles', NS)
        bitmap_fill_count = 0
        
        for shape in valid_shapes:
            style_name = shape.get(f"{{{NS['draw']}}}style-name")
            if style_name and automatic_styles is not None:
                style_node = automatic_styles.find(f".//*[@style:name='{style_name}']", NS)
                if style_node is not None:
                    props = style_node.find('style:graphic-properties', NS)
                    if props is not None:
                        fill = props.get(f"{{{NS['draw']}}}fill")
                        # Also check if it references a bitmap image name
                        img_name = props.get(f"{{{NS['draw']}}}fill-image-name")
                        if fill == 'bitmap' or img_name:
                            bitmap_fill_count += 1

        if bitmap_fill_count >= 3:
            score += 30
            feedback_parts.append("✅ Shapes contain image data (bitmap fill)")
        elif bitmap_fill_count > 0:
            score += 10 * bitmap_fill_count
            feedback_parts.append(f"⚠️ {bitmap_fill_count} shapes have image content")
        else:
            feedback_parts.append("❌ Shapes do not appear to contain images (might be solid colors)")

        passed = score >= 75
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification Logic Error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

def parse_measure(measure_str):
    """Convert measurement string (e.g., '2.5cm') to float value in cm."""
    try:
        if not measure_str: return 0.0
        unit_map = {'cm': 1.0, 'in': 2.54, 'mm': 0.1, 'pt': 0.0352778}
        
        for unit, factor in unit_map.items():
            if measure_str.endswith(unit):
                val = float(measure_str.replace(unit, ''))
                return val * factor
        return float(measure_str) # Assume raw number
    except:
        return 0.0