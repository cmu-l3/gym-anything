#!/usr/bin/env python3
"""
Verifier for Recolor Shapes task.

Verification Logic:
1. Verify ODP file was modified (anti-gaming).
2. Unzip ODP and parse content.xml.
3. Verify shapes (Rect, Ellipse) and Text have correct colors.
   - We verify colors by looking for automatic styles with the expected hex codes.
   - We calculate a "compliance score" based on how many elements match expectations.

Target Colors:
- Rectangles: #2E7D32 (Forest Green)
- Ellipses:   #FF8F00 (Amber)
- Titles:     #0D47A1 (Dark Blue)

Tolerance: +/- 5 per channel
"""

import json
import tempfile
import os
import logging
import zipfile
import re
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target Colors
TARGET_RECT = (46, 125, 50)   # #2E7D32
TARGET_ELLIPSE = (255, 143, 0) # #FF8F00
TARGET_TITLE = (13, 71, 161)   # #0D47A1
TOLERANCE = 5

def hex_to_rgb(hex_str):
    """Convert #RRGGBB to tuple."""
    if not hex_str: return None
    hex_str = hex_str.lstrip('#')
    try:
        return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))
    except ValueError:
        return None

def is_color_match(hex_color, target_rgb, tolerance=TOLERANCE):
    """Check if hex matches target RGB within tolerance."""
    if not hex_color:
        return False
    rgb = hex_to_rgb(hex_color)
    if not rgb:
        return False
    return all(abs(c1 - c2) <= tolerance for c1, c2 in zip(rgb, target_rgb))

def verify_recolor_shapes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('presentation_path', '/home/ga/Documents/Presentations/esg_report.odp')

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_meta.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if not result_meta.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not modified (timestamp unchanged)"}

    # Fetch ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(expected_path, temp_odp.name)
        
        # Analyze ODP content
        analysis = analyze_odp_colors(temp_odp.name)
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to analyze ODP file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # Scoring
    score = 0
    feedback_parts = []

    # 1. File Modification (10 pts)
    score += 10
    
    # 2. Rectangles (8 total expected, 2 per slide * 4) - 25 pts
    # We allow some leniency, e.g. >= 6
    rect_count = analysis['rectangles_matched']
    total_rects = analysis['total_rectangles']
    if rect_count >= 6:
        score += 25
        feedback_parts.append(f"✅ Rectangles recolored ({rect_count}/{total_rects})")
    elif rect_count > 0:
        score += int(25 * (rect_count / 8))
        feedback_parts.append(f"⚠️ Some rectangles recolored ({rect_count}/{total_rects})")
    else:
        feedback_parts.append(f"❌ No rectangles recolored to Forest Green")

    # 3. Ellipses (4 total expected) - 20 pts
    ellipse_count = analysis['ellipses_matched']
    total_ellipses = analysis['total_ellipses']
    if ellipse_count >= 3:
        score += 20
        feedback_parts.append(f"✅ Ellipses recolored ({ellipse_count}/{total_ellipses})")
    elif ellipse_count > 0:
        score += int(20 * (ellipse_count / 4))
        feedback_parts.append(f"⚠️ Some ellipses recolored ({ellipse_count}/{total_ellipses})")
    else:
        feedback_parts.append(f"❌ No ellipses recolored to Amber")

    # 4. Titles (4 total expected) - 25 pts
    title_count = analysis['titles_matched']
    total_titles = analysis['total_titles']
    if title_count >= 3:
        score += 25
        feedback_parts.append(f"✅ Titles recolored ({title_count}/{total_titles})")
    elif title_count > 0:
        score += int(25 * (title_count / 4))
        feedback_parts.append(f"⚠️ Some titles recolored ({title_count}/{total_titles})")
    else:
        feedback_parts.append(f"❌ No titles recolored to Dark Blue")

    # 5. Default Gray Removal (10 pts)
    # Check if we still have the original #C0C0C0
    if not analysis['has_default_gray']:
        score += 20
        feedback_parts.append("✅ Default gray removed")
    else:
        feedback_parts.append("⚠️ Some default gray shapes remain")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }

def analyze_odp_colors(filepath):
    """
    Parse content.xml from ODP to check styles and object usage.
    Returns counts of matching objects.
    """
    stats = {
        'rectangles_matched': 0,
        'total_rectangles': 0,
        'ellipses_matched': 0,
        'total_ellipses': 0,
        'titles_matched': 0,
        'total_titles': 0,
        'has_default_gray': False
    }

    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            content = z.read('content.xml')
        
        root = ET.fromstring(content)
        
        # Namespaces
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
        }

        # 1. Parse Automatic Styles to map StyleNames -> Colors
        style_colors = {} # style_name -> fill_color (hex)
        text_colors = {}  # style_name -> font_color (hex)

        auto_styles = root.find('office:automatic-styles', ns)
        if auto_styles is not None:
            # Graphic styles (shapes)
            for style_node in auto_styles.findall('style:style', ns):
                name = style_node.get(f"{{{ns['style']}}}name")
                family = style_node.get(f"{{{ns['style']}}}family")
                
                if family == 'graphic':
                    props = style_node.find('style:graphic-properties', ns)
                    if props is not None:
                        fill_color = props.get(f"{{{ns['draw']}}}fill-color")
                        if fill_color:
                            style_colors[name] = fill_color
                
                # Text/Paragraph styles
                if family == 'paragraph' or family == 'text':
                    props = style_node.find('style:text-properties', ns)
                    if props is not None:
                        color = props.get(f"{{{ns['fo']}}}color")
                        if color:
                            text_colors[name] = color

        # 2. Traverse slides (draw:page)
        body = root.find('office:body', ns)
        presentation = body.find('office:presentation', ns)
        
        for page in presentation.findall('draw:page', ns):
            # Check Shapes
            for rect in page.findall('draw:rect', ns):
                stats['total_rectangles'] += 1
                style_name = rect.get(f"{{{ns['draw']}}}style-name")
                color = style_colors.get(style_name)
                
                if is_color_match(color, TARGET_RECT):
                    stats['rectangles_matched'] += 1
                elif is_color_match(color, (192, 192, 192)): # Default Gray
                    stats['has_default_gray'] = True

            for ellipse in page.findall('draw:ellipse', ns):
                stats['total_ellipses'] += 1
                style_name = ellipse.get(f"{{{ns['draw']}}}style-name")
                color = style_colors.get(style_name)

                if is_color_match(color, TARGET_ELLIPSE):
                    stats['ellipses_matched'] += 1
                elif is_color_match(color, (192, 192, 192)):
                    stats['has_default_gray'] = True
            
            # Check Titles
            # Titles are usually in a draw:frame with presentation:class="title"
            # Inside the frame is a text-box, inside is a p (paragraph) or span with style
            for frame in page.findall('draw:frame', ns):
                p_class = frame.get(f"{{{ns['presentation']}}}class", "") if 'presentation' in ns else ""
                # Note: presentation namespace might need to be added to ns dict if not detected automatically
                # but standard ODP usually has it. Let's try flexible check.
                
                # Find text content in frame
                textbox = frame.find('draw:text-box', ns)
                if textbox is not None:
                    # Check if this looks like a title (by position or content, but here we assume logic)
                    # For simplicity, we check ALL text that matches the title color.
                    # Or simpler: Is this a title frame?
                    
                    # We iterate paragraphs/spans
                    for p in textbox.findall('text:p', ns):
                        # Check paragraph style
                        style_name = p.get(f"{{{ns['text']}}}style-name", "") if 'text' in ns else "" # actually style-name is generic
                        # The element is usually text:p
                        
                        # We need to correctly access text:p
                        # Let's just search all text:p in the page and check colors
                        pass

        # Robust text search (simpler approach)
        # We iterate all text:p elements in the document and check if they use a blue style
        # and assume those are the titles (since body text shouldn't be blue).
        # This avoids complex frame identification.
        
        all_ps = root.findall('.//text:p', ns)
        for p in all_ps:
            # Check direct style on P
            style_name = p.get(f"{{{ns['text']}}}style-name")
            color = text_colors.get(style_name)
            
            # Also check spans inside p
            spans = p.findall('text:span', ns)
            for span in spans:
                span_style = span.get(f"{{{ns['text']}}}style-name")
                span_color = text_colors.get(span_style)
                if is_color_match(span_color, TARGET_TITLE):
                    # Found a blue span
                    pass # We count this below

            if is_color_match(color, TARGET_TITLE):
                stats['titles_matched'] += 1
            else:
                # If the style didn't have color, it might inherit. 
                # For this task, direct formatting usually creates an automatic style.
                pass
                
        # Since identifying exactly "Title" vs "Body" via XML without class can be tricky
        # we will rely on the count of blue text paragraphs.
        # We expect 1 title per slide = 4 titles.
        # If the user changed the title color, we should find ~4 blue paragraphs.
        
        # Refined Title Logic:
        # Just count how many separate paragraphs have the target blue color.
        # If the user colored body text blue, they get points but maybe fail "structure" checks if we had them.
        stats['total_titles'] = 4 # We know there are 4 slides
        
    except Exception as e:
        logger.error(f"XML Parse Error: {e}")
        # Fallback to string search if XML fails (last resort)
        # Search for hex codes in the raw content
        if content:
            content_str = str(content)
            # Simple heuristic counts
            stats['rectangles_matched'] = content_str.lower().count('#2e7d32') // 2 # occur twice (style def + usage?) approximation
            stats['ellipses_matched'] = content_str.lower().count('#ff8f00') // 2
            stats['titles_matched'] = content_str.lower().count('#0d47a1') // 2
            
    return stats