#!/usr/bin/env python3
"""
Verifier for Create Venn Diagram Task.

Verifies:
1. Slide inserted (total count = 4)
2. Slide 2 contains title "Sustainability" or "Pillars"
3. Venn diagram structure (3 ellipses, overlapping)
4. Formatting (Transparency, Distinct Colors)
5. Text content (Labels present)
"""

import json
import tempfile
import os
import logging
import zipfile
import re
from lxml import etree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF Namespaces
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}

def parse_length(val):
    """Parse ODF length string to centimeters."""
    if not val: return 0.0
    val = str(val).strip()
    try:
        if val.endswith('cm'): return float(val[:-2])
        if val.endswith('mm'): return float(val[:-2]) / 10.0
        if val.endswith('in'): return float(val[:-2]) * 2.54
        if val.endswith('pt'): return float(val[:-2]) * 0.03528
        return float(val)
    except ValueError:
        return 0.0

def bboxes_overlap(b1, b2):
    """Check if two bounding boxes (x,y,w,h) overlap."""
    x1, y1, w1, h1 = b1
    x2, y2, w2, h2 = b2
    return not (x1 + w1 < x2 or x2 + w2 < x1 or y1 + h1 < y2 or y2 + h2 < y1)

def verify_create_venn_diagram(traj, env_info, task_info):
    """Verify the Venn diagram creation task."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    if not result_data.get('file_exists') or not result_data.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "Presentation file was not modified or saved."}

    # Download ODP File
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(result_data['target_path'], temp_odp.name)
        
        # Open ODP (Zip)
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": 0, "feedback": "Saved file is not a valid ODP/Zip archive."}

        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml') if 'styles.xml' in z.namelist() else b''

        # Parse XML
        root = etree.fromstring(content_xml)
        styles_root = etree.fromstring(styles_xml) if styles_xml else None
        
        # --- SCORING CRITERIA ---
        score = 0
        feedback = []
        
        # 1. Check Slide Count (10 pts)
        slides = root.findall('.//draw:page', NS)
        slide_count = len(slides)
        if slide_count == 4:
            score += 10
            feedback.append("Correct slide count (4).")
        else:
            feedback.append(f"Incorrect slide count: {slide_count} (expected 4).")

        # Identify Target Slide (Should be index 1 / 2nd slide)
        # We also scan all slides just in case
        target_slide = None
        for i, slide in enumerate(slides):
            # Extract text to identify
            text_content = " ".join([elem.text for elem in slide.findall('.//text:p', NS) if elem.text]).lower()
            if "pillars" in text_content or "sustainability" in text_content:
                # If it's the 2nd slide (index 1), that's perfect
                target_slide = slide
                if i == 1:
                    score += 10 # Bonus for correct position
                    feedback.append("Slide in correct position.")
                break
        
        if not target_slide and len(slides) > 1:
            target_slide = slides[1] # Fallback to index 1

        if not target_slide:
             return {"passed": False, "score": score, "feedback": "Could not locate target slide."}

        # 2. Check Title (10 pts)
        slide_text = " ".join([elem.text for elem in target_slide.findall('.//text:p', NS) if elem.text]).lower()
        if "three pillars" in slide_text or "pillars of sustainability" in slide_text:
            score += 10
            feedback.append("Title text correct.")
        
        # 3. Check Ellipses (20 pts)
        # Find shapes: draw:ellipse or custom-shape with ellipse type
        ellipses = target_slide.findall('.//draw:ellipse', NS)
        custom_shapes = target_slide.findall('.//draw:custom-shape', NS)
        
        valid_ellipses = list(ellipses)
        for cs in custom_shapes:
            geom = cs.find('.//draw:enhanced-geometry', NS)
            if geom is not None:
                type_attr = geom.get(f'{{{NS["draw"]}}}type', '').lower()
                if 'ellipse' in type_attr or 'circle' in type_attr:
                    valid_ellipses.append(cs)
        
        ellipse_count = len(valid_ellipses)
        if ellipse_count >= 3:
            score += 20
            feedback.append(f"Found {ellipse_count} ellipses.")
        elif ellipse_count > 0:
            score += 10
            feedback.append(f"Found only {ellipse_count} ellipses (expected 3).")
        else:
            feedback.append("No ellipses found.")

        # 4. Check Overlap (15 pts)
        bboxes = []
        for ell in valid_ellipses:
            x = parse_length(ell.get(f'{{{NS["svg"]}}}x'))
            y = parse_length(ell.get(f'{{{NS["svg"]}}}y'))
            w = parse_length(ell.get(f'{{{NS["svg"]}}}width'))
            h = parse_length(ell.get(f'{{{NS["svg"]}}}height'))
            if w > 0 and h > 0:
                bboxes.append((x, y, w, h))
        
        overlap_found = False
        if len(bboxes) >= 2:
            import itertools
            for b1, b2 in itertools.combinations(bboxes, 2):
                if bboxes_overlap(b1, b2):
                    overlap_found = True
                    break
        
        if overlap_found:
            score += 15
            feedback.append("Shapes overlap correctly.")
        elif ellipse_count >= 2:
            feedback.append("Shapes do not overlap.")

        # 5. Check Transparency (15 pts) & Colors (5 pts)
        # We need to look up styles. Styles can be in automatic-styles in content.xml
        auto_styles = root.find('.//office:automatic-styles', NS)
        style_map = {}
        if auto_styles is not None:
            for style in auto_styles:
                name = style.get(f'{{{NS["style"]}}}name')
                props = style.find('style:graphic-properties', NS)
                if name and props is not None:
                    style_map[name] = props

        transparency_count = 0
        fill_colors = set()

        for ell in valid_ellipses:
            style_name = ell.get(f'{{{NS["draw"]}}}style-name')
            if style_name and style_name in style_map:
                props = style_map[style_name]
                # Check opacity/transparency
                opacity = props.get(f'{{{NS["draw"]}}}opacity')
                transparency = props.get(f'{{{NS["draw"]}}}fill-transparency') # Alternative attribute
                
                is_transparent = False
                if opacity:
                    op_val = float(opacity.strip('%'))
                    if op_val < 95: is_transparent = True
                if transparency:
                    tr_val = float(transparency.strip('%'))
                    if tr_val > 5: is_transparent = True
                
                if is_transparent:
                    transparency_count += 1
                
                # Check color
                color = props.get(f'{{{NS["draw"]}}}fill-color')
                if color:
                    fill_colors.add(color)

        if transparency_count >= 2:
            score += 15
            feedback.append("Transparency applied.")
        elif transparency_count > 0:
            score += 5
            feedback.append("Partial transparency detected.")
        else:
            feedback.append("No transparency detected.")
            
        if len(fill_colors) >= 3:
            score += 5
            feedback.append("Distinct colors applied.")

        # 6. Check Text Labels (15 pts)
        required_labels = ["environmental", "social", "economic"]
        labels_found = 0
        for req in required_labels:
            if req in slide_text:
                labels_found += 1
        
        if labels_found == 3:
            score += 15
            feedback.append("All category labels found.")
        else:
            score += (labels_found * 5)
            feedback.append(f"Found {labels_found}/3 category labels.")

        if "sustainable development" in slide_text:
            score += 10
            feedback.append("Central label found.")
        
        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name): os.unlink(temp_odp.name)