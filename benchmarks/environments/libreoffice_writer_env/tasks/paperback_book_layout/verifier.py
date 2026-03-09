#!/usr/bin/env python3
"""
Verifier for paperback_book_layout task.

Verifies:
1. Output ODT file exists and was modified during task.
2. Page size is 6" x 9".
3. Margins are mirrored with correct dimensions.
4. Headers are alternating (different left/right).
5. Headers contain dynamic fields (Page Number, Chapter).
"""

import os
import json
import zipfile
import tempfile
import shutil
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_length_to_inches(length_str: str) -> float:
    """Convert ODF length string (e.g., '6in', '15.24cm') to inches."""
    if not length_str:
        return 0.0
    
    s = length_str.lower().strip()
    if s.endswith('in'):
        return float(s[:-2])
    elif s.endswith('cm'):
        return float(s[:-2]) / 2.54
    elif s.endswith('mm'):
        return float(s[:-2]) / 25.4
    elif s.endswith('pt'):
        return float(s[:-2]) / 72.0
    
    try:
        return float(s)
    except ValueError:
        return 0.0

def verify_paperback_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width_in', 6.0)
    expected_height = metadata.get('expected_height_in', 9.0)
    inner_margin = metadata.get('inner_margin_in', 0.8)
    outer_margin = metadata.get('outer_margin_in', 0.5)
    tolerance = metadata.get('margin_tolerance', 0.1)

    score = 0
    feedback = []
    
    # 1. Check basic file existence and timestamp
    temp_json_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json_path):
            os.remove(temp_json_path)

    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    score += 10 # File exists

    if not result_data.get('file_created_during_task'):
        feedback.append("Warning: File timestamp suggests it wasn't modified during task")
    else:
        score += 5 # Created during task

    # 2. Parse ODT content
    temp_odt_path = tempfile.mktemp(suffix='.odt')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env(metadata.get('output_path'), temp_odt_path)
        
        try:
            with zipfile.ZipFile(temp_odt_path, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
        except zipfile.BadZipFile:
             return {"passed": False, "score": score, "feedback": "Output file is not a valid ODT/ZIP archive"}

        # Namespaces
        ns = {
            'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
        }

        # Parse styles.xml
        styles_path = os.path.join(extract_dir, 'styles.xml')
        if not os.path.exists(styles_path):
             return {"passed": False, "score": score, "feedback": "Invalid ODT: missing styles.xml"}
        
        tree = ET.parse(styles_path)
        root = tree.getroot()

        # Find Page Layout
        # We look for the default page layout or the one used by Standard style
        page_layout = None
        # Usually found in office:automatic-styles or office:styles
        # First, find the master page to see which layout it uses
        master_page = root.find('.//style:master-page', ns)
        layout_name = master_page.get(f"{{{ns['style']}}}page-layout-name") if master_page is not None else None
        
        if layout_name:
            # Find the layout definition
            for pl in root.findall('.//style:page-layout', ns):
                if pl.get(f"{{{ns['style']}}}name") == layout_name:
                    page_layout = pl
                    break
        
        if page_layout is None:
             # Fallback: take first page layout found
             page_layout = root.find('.//style:page-layout', ns)

        if page_layout is None:
            feedback.append("Could not find page layout definition")
        else:
            props = page_layout.find('style:page-layout-properties', ns)
            if props is not None:
                # Check Dimensions
                w_str = props.get(f"{{{ns['fo']}}}page-width")
                h_str = props.get(f"{{{ns['fo']}}}page-height")
                w = parse_length_to_inches(w_str)
                h = parse_length_to_inches(h_str)

                if abs(w - expected_width) < tolerance and abs(h - expected_height) < tolerance:
                    score += 20
                    feedback.append(f"Page size correct ({w:.2f}x{h:.2f})")
                else:
                    feedback.append(f"Page size incorrect: {w:.2f}x{h:.2f} (Expected 6x9)")

                # Check Mirrored
                usage = props.get(f"{{{ns['style']}}}page-usage")
                # Mirrored margins often represented by page-usage="mirrored" OR print-orientation
                # In ODF, mirrored pages usually have style:page-usage="mirrored"
                if usage and usage.lower() == 'mirrored':
                    score += 20
                    feedback.append("Mirrored layout enabled")
                else:
                    feedback.append(f"Layout not set to Mirrored (found usage='{usage}')")

                # Check Margins
                # In mirrored mode: margin-left usually becomes Inner, margin-right becomes Outer (or vice versa)
                # We check if ONE is inner and ONE is outer, loosely
                m_left = parse_length_to_inches(props.get(f"{{{ns['fo']}}}margin-left"))
                m_right = parse_length_to_inches(props.get(f"{{{ns['fo']}}}margin-right"))
                
                margins_found = [m_left, m_right]
                # Check if we have ~0.8 and ~0.5
                has_inner = any(abs(m - inner_margin) < tolerance for m in margins_found)
                has_outer = any(abs(m - outer_margin) < tolerance for m in margins_found)

                if has_inner and has_outer:
                    score += 20
                    feedback.append("Margins correct (Inner/Outer)")
                elif has_inner or has_outer:
                    score += 10
                    feedback.append(f"Margins partially correct: Found {m_left:.2f}, {m_right:.2f}")
                else:
                    feedback.append(f"Margins incorrect: {m_left:.2f}, {m_right:.2f}")

        # Check Headers (Alternating and Fields)
        if master_page is not None:
            header = master_page.find('style:header', ns)
            header_left = master_page.find('style:header-left', ns)

            if header is not None and header_left is not None:
                score += 15
                feedback.append("Alternating headers configured")
                
                # Check Content (Fields)
                # Need to verify presence of <text:page-number> and <text:chapter>
                # These might be in styles.xml under the master page definition
                
                def check_header_content(element):
                    content_str = ET.tostring(element, encoding='unicode')
                    has_page_num = 'text:page-number' in content_str
                    has_chapter = 'text:chapter' in content_str
                    return has_page_num, has_chapter

                l_pg, l_ch = check_header_content(header_left)
                r_pg, r_ch = check_header_content(header)

                # Requirement: Left=Page#+Title, Right=Chapter+Page#
                # We just check for existence of fields in general to be generous but rigorous on "dynamic" nature
                if (l_pg or r_pg) and (l_ch or r_ch):
                    score += 20
                    feedback.append("Dynamic fields (Page Number/Chapter) found in headers")
                elif l_pg or r_pg:
                    score += 10
                    feedback.append("Page number field found, but Chapter field missing")
                else:
                    feedback.append("Dynamic fields missing in headers (text might be hardcoded)")

            else:
                feedback.append("Alternating headers NOT found (Header Left/Right missing)")

    except Exception as e:
        feedback.append(f"Error parsing ODT: {e}")
    finally:
        if os.path.exists(temp_odt_path):
            os.remove(temp_odt_path)
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }