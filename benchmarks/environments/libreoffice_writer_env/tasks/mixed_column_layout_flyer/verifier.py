#!/usr/bin/env python3
"""
Verifier for mixed_column_layout_flyer task.
Verifies:
1. File creation (ODT preferred).
2. Document structure (Title, Image, Section with Columns).
3. Visual layout via VLM.
"""

import sys
import os
import json
import logging
import zipfile
import tempfile
import shutil
from xml.etree import ElementTree

# Import utils from environment if available
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from writer_verification_utils import vlm_verify_screenshot
except ImportError:
    vlm_verify_screenshot = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odt_structure(odt_path):
    """
    Parses content.xml and styles.xml from an ODT file to extract:
    - Sections and their column counts.
    - Images (frames).
    - Paragraph styles (for title checks).
    """
    ns = {
        'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
        'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
        'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
        'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
        'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0'
    }
    
    info = {
        'has_sections': False,
        'max_columns': 1,
        'has_images': False,
        'image_widths': [],
        'title_found': False,
        'title_centered': False
    }

    try:
        with zipfile.ZipFile(odt_path, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml') # Usually needed for automatic styles
            
            tree = ElementTree.fromstring(content_xml)
            
            # 1. Check for Sections and Columns
            # Find all section elements
            sections = tree.findall('.//text:section', ns)
            if sections:
                info['has_sections'] = True
                
                # Check section styles for column-count
                # Note: In ODT, section style is referenced by text:style-name
                # The style definition is in content.xml (automatic-styles) or styles.xml
                
                auto_styles = tree.find('office:automatic-styles', {'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'})
                
                for section in sections:
                    style_name = section.get(f"{{{ns['text']}}}style-name")
                    if style_name and auto_styles:
                        # Find the style definition
                        style_def = auto_styles.find(f".//style:style[@style:name='{style_name}']", ns)
                        if style_def:
                            section_props = style_def.find('style:section-properties', ns)
                            if section_props is not None:
                                cols = section_props.find('style:columns', ns)
                                if cols is not None:
                                    col_count = int(cols.get(f"{{{ns['fo']}}}column-count", 1))
                                    if col_count > info['max_columns']:
                                        info['max_columns'] = col_count

            # 2. Check for Images
            frames = tree.findall('.//draw:frame', ns)
            for frame in frames:
                # Check if it contains an image
                if frame.find('draw:image', ns) is not None:
                    info['has_images'] = True
                    width_str = frame.get(f"{{{ns['svg']}}}width", "0cm")
                    # Crude parsing of "17cm" or "6.5in"
                    try:
                        if "in" in width_str:
                            width = float(width_str.replace("in", ""))
                        elif "cm" in width_str:
                            width = float(width_str.replace("cm", "")) / 2.54
                        else:
                            width = 0
                        info['image_widths'].append(width)
                    except ValueError:
                        pass

            # 3. Check Title (Heuristic: First paragraph with large font or 'Title' style)
            # This is hard to do perfectly without style resolution, but we can check specific text
            paragraphs = tree.findall('.//text:p', ns)
            for p in paragraphs:
                if p.text and "OPEN HOUSE" in p.text:
                    info['title_found'] = True
                    # Check style alignment if possible (skipped for robustness, handled by VLM)
                    break

    except Exception as e:
        logger.error(f"Error parsing ODT: {e}")
        return None

    return info

def verify_mixed_column_flyer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load previous result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result_data = json.load(f)
        os.unlink(temp_json.name)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Failed to load task result"}

    score = 0
    feedback = []

    # 1. File Existence & Anti-Gaming (20 pts)
    if result_data.get("output_found") and result_data.get("file_created_during_task"):
        score += 20
        feedback.append("Output file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file created during task."}

    # 2. Structure Verification (ODT Parsing) (50 pts)
    output_path = result_data.get("output_path")
    if output_path.endswith(".odt"):
        # Copy ODT to temp
        temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
        try:
            copy_from_env(output_path, temp_odt.name)
            odt_info = parse_odt_structure(temp_odt.name)
            
            if odt_info:
                # Check Columns (20 pts)
                if odt_info['max_columns'] >= 2:
                    score += 20
                    feedback.append("Multi-column section detected.")
                else:
                    feedback.append("Failed: No multi-column section found (Max columns: 1).")

                # Check Image (15 pts)
                if odt_info['has_images']:
                    score += 15
                    # Check width
                    if any(w > 5.0 for w in odt_info['image_widths']):
                         feedback.append("Full-width image detected.")
                    else:
                         feedback.append("Image found but might be too small.")
                else:
                    feedback.append("Failed: No image detected in document.")

                # Check Title (15 pts)
                if odt_info['title_found']:
                    score += 15
                    feedback.append("Title text found.")
                else:
                    feedback.append("Title text not found.")
            else:
                feedback.append("Error parsing ODT structure.")
        finally:
            if os.path.exists(temp_odt.name):
                os.unlink(temp_odt.name)

    elif output_path.endswith(".docx"):
        feedback.append("DOCX format used instead of ODT. Skipping structural column check (Partial credit).")
        score += 20 # Partial credit for saving
        # Can't reliably check sections in DOCX without complex library, rely on VLM

    # 3. VLM Verification (30 pts)
    # Visual check is crucial for layout (Top-heavy vs Split-bottom)
    if vlm_verify_screenshot:
        vlm_res = vlm_verify_screenshot(env_info, traj, prompt="""
        Analyze this document flyer. 
        1. Is there a large image at the top?
        2. Is the text below the image split into two columns?
        3. Is the title 'OPEN HOUSE' visible and centered?
        Answer JSON: {"has_large_image": bool, "two_column_layout": bool, "title_visible": bool}
        """)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('two_column_layout'):
                score += 15
                feedback.append("VLM: Two-column layout confirmed.")
            if parsed.get('has_large_image'):
                score += 10
                feedback.append("VLM: Large image visible.")
            if parsed.get('title_visible'):
                score += 5
                feedback.append("VLM: Title visible.")
    else:
        feedback.append("VLM verification unavailable.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }