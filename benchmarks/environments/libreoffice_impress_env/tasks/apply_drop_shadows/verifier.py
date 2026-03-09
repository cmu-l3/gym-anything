#!/usr/bin/env python3
"""
Verifier for Apply Drop Shadows task.
Parses ODP XML to check for shadow attributes on specific shapes.
"""

import json
import tempfile
import os
import zipfile
import logging
from lxml import etree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF Namespaces
NS = {
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0'
}

def verify_apply_drop_shadows(traj, env_info, task_info):
    """
    Verify that drop shadows were applied to the 5 product tier rectangles.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_file = metadata.get('target_file', '/home/ga/Documents/Presentations/quarterly_review.odp')
    pass_threshold = metadata.get('pass_threshold', 60)

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found."}
    
    if not result.get('was_modified') or not result.get('content_changed'):
        return {"passed": False, "score": 0, "feedback": "File was not modified. No changes detected."}

    # 2. Retrieve ODP File
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_file, temp_odp.name)
        
        # 3. Parse ODP content
        try:
            with zipfile.ZipFile(temp_odp.name, 'r') as z:
                content_xml = z.read('content.xml')
                styles_xml = z.read('styles.xml') if 'styles.xml' in z.namelist() else b''
        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Saved file is not a valid ODP archive."}

        content_tree = etree.fromstring(content_xml)
        styles_tree = etree.fromstring(styles_xml) if styles_xml else None

        # Verify Slide Count
        slides = content_tree.xpath('//draw:page', namespaces=NS)
        if len(slides) != 3:
            return {
                "passed": False, 
                "score": 20, 
                "feedback": f"Incorrect slide count. Expected 3, found {len(slides)}. Structure must be preserved."
            }

        slide2 = slides[1] # 0-indexed
        
        # Verify Text Content (Sanity Check)
        slide2_text = " ".join(slide2.xpath('.//text:p/text()', namespaces=NS))
        expected_terms = ["Starter", "Basic", "Pro", "Enterprise", "Ultimate"]
        missing_terms = [t for t in expected_terms if t not in slide2_text]
        if len(missing_terms) > 2:
             return {
                "passed": False, 
                "score": 30, 
                "feedback": "Slide content significantly altered. Product tier names missing."
            }

        # 4. Check Shadows
        # Strategy: Find all CustomShapes/Rects on Slide 2.
        # Get their style-name.
        # Look up style in content.xml (automatic-styles) or styles.xml.
        # Check for draw:shadow="visible" or "true" in style:graphic-properties.

        shapes = slide2.xpath('.//draw:custom-shape | .//draw:rect', namespaces=NS)
        shadow_count = 0
        total_shapes_checked = 0

        # Create a lookup for styles
        style_map = {}
        
        # Helper to index styles
        def index_styles(tree):
            if tree is None: return
            for style in tree.xpath('//style:style', namespaces=NS):
                name = style.get(f'{{{NS["style"]}}}name')
                props = style.find('style:graphic-properties', namespaces=NS)
                if name and props is not None:
                    style_map[name] = props

        index_styles(content_tree) # Automatic styles
        index_styles(styles_tree)  # Named styles

        for shape in shapes:
            # Simple heuristic: Check if it's likely one of our tier boxes (has text inside)
            shape_text = "".join(shape.xpath('.//text:p/text()', namespaces=NS))
            if not any(term in shape_text for term in expected_terms):
                continue # Skip shapes that aren't our target rectangles (like title box)

            total_shapes_checked += 1
            style_name = shape.get(f'{{{NS["draw"]}}}style-name')
            
            has_shadow = False
            if style_name in style_map:
                props = style_map[style_name]
                shadow_attr = props.get(f'{{{NS["draw"]}}}shadow')
                if shadow_attr and shadow_attr.lower() in ['visible', 'true']:
                    has_shadow = True
            
            if has_shadow:
                shadow_count += 1

        # Scoring
        # 10 pts for valid file/mod
        # 10 pts for structure preserved
        # 16 pts per shadowed shape (max 5 * 16 = 80)
        score = 20 
        
        if total_shapes_checked == 0:
            # Fallback if text detection fails (maybe user deleted text): check all shapes
            # Assuming there are at least 5 main shapes
            pass 
        
        shapes_score = min(shadow_count, 5) * 16
        score += shapes_score

        feedback = f"File modified and valid. Found shadows on {shadow_count} of {max(total_shapes_checked, 5)} expected shapes."
        
        passed = score >= pass_threshold
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "shadow_count": shadow_count,
                "total_shapes_found": total_shapes_checked,
                "file_valid": True
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)