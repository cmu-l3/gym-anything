#!/usr/bin/env python3
"""
Verifier for report_pagination_flow_control task.
Verifies ODT file for correct style definitions and removed empty paragraphs.
"""

import json
import os
import shutil
import tempfile
import zipfile
import logging
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_report_pagination(traj, env_info, task_info):
    """
    Verify the report pagination task.
    
    Criteria:
    1. Output file exists and was modified.
    2. Empty paragraphs (manual spacing) are largely removed.
    3. Heading styles (Heading 1 & 2) have 'keep-with-next' enabled.
    4. Text Body style has 'widow/orphan' control >= 2.
    5. Text Body style has bottom margin > 0.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load basic result stats
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_stats = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result stats: {e}"}
    finally:
        os.unlink(temp_json.name)

    if not result_stats.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'structural_analysis_final.odt' not found."}

    # Retrieve the ODT file
    temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
    try:
        copy_from_env("/home/ga/Documents/structural_analysis_final.odt", temp_odt.name)
    except Exception as e:
        os.unlink(temp_odt.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output file: {e}"}

    # Analyze the ODT
    score = 0
    feedback = []
    
    try:
        # Unzip ODT to parse XML directly (more reliable for specific style attributes than high-level libs)
        with zipfile.ZipFile(temp_odt.name, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml')
            
        content_root = ET.fromstring(content_xml)
        styles_root = ET.fromstring(styles_xml)
        
        # Namespaces
        ns = {
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
        }

        # --- Check 1: Empty Paragraphs (Manual Spacing) ---
        # Count paragraphs that are empty or contain only whitespace
        empty_paras = 0
        total_paras = 0
        body = content_root.find('.//office:body/office:text', ns)
        if body is not None:
            for p in body.findall('text:p', ns):
                total_paras += 1
                text_content = "".join(p.itertext()).strip()
                if not text_content:
                    empty_paras += 1
        
        # Original messy doc has ~40 empty paras. Good result should have < 5.
        if empty_paras < 5:
            score += 25
            feedback.append(f"Manual spacing removed (found {empty_paras} empty paragraphs)")
        elif empty_paras < 15:
            score += 15
            feedback.append(f"Partial removal of manual spacing (found {empty_paras} empty paragraphs)")
        else:
            feedback.append(f"Too many empty paragraphs remaining ({empty_paras}) - Manual spacing not fixed")

        # --- Check 2 & 3: Style Definitions ---
        # We need to find the style names. In ODT, 'Heading 1' usually maps to a style named 'Heading_20_1' or similar.
        # We look in styles.xml for style definitions.
        
        def check_style_attribute(style_name_substring, attr_name, attr_ns, expected_val_condition):
            # Find style with name containing substring
            found_styles = []
            for style in styles_root.findall('.//style:style', ns):
                name = style.get(f"{{{ns['style']}}}name", "")
                display_name = style.get(f"{{{ns['style']}}}display-name", "")
                if style_name_substring in name or style_name_substring in display_name:
                    found_styles.append(style)
            
            if not found_styles:
                return False, f"Style '{style_name_substring}' not found"

            # Check properties
            for style in found_styles:
                props = style.find('style:paragraph-properties', ns)
                if props is not None:
                    val = props.get(f"{{{ns[attr_ns]}}}{attr_name}")
                    if val and expected_val_condition(val):
                        return True, f"Found {val}"
            return False, "Attribute not found or incorrect"

        # Check Heading 1 Flow Control (keep-with-next)
        h1_ok, msg = check_style_attribute("Heading_20_1", "keep-with-next", "fo", lambda x: x == "always" or x == "true")
        if not h1_ok:
             # Try display name "Heading 1"
             h1_ok, msg = check_style_attribute("Heading 1", "keep-with-next", "fo", lambda x: x == "always" or x == "true")
        
        if h1_ok:
            score += 15
            feedback.append("Heading 1 flow control: OK")
        else:
            feedback.append("Heading 1 missing 'Keep with next' flow control")

        # Check Heading 2 Flow Control
        h2_ok, _ = check_style_attribute("Heading_20_2", "keep-with-next", "fo", lambda x: x == "always" or x == "true")
        if not h2_ok:
            h2_ok, _ = check_style_attribute("Heading 2", "keep-with-next", "fo", lambda x: x == "always" or x == "true")
        
        if h2_ok:
            score += 10
            feedback.append("Heading 2 flow control: OK")
        else:
            feedback.append("Heading 2 missing 'Keep with next' flow control")

        # Check Text Body / Default Paragraph Style for Widows/Orphans
        # Often mapped to "Text_20_body"
        body_ok = False
        for s_name in ["Text_20_body", "Text Body", "Standard"]:
            widows_ok, _ = check_style_attribute(s_name, "widows", "fo", lambda x: x.isdigit() and int(x) >= 2)
            orphans_ok, _ = check_style_attribute(s_name, "orphans", "fo", lambda x: x.isdigit() and int(x) >= 2)
            
            if widows_ok and orphans_ok:
                body_ok = True
                break
        
        if body_ok:
            score += 20
            feedback.append("Body style Widow/Orphan control: OK")
        else:
            feedback.append("Body style missing Widow/Orphan control (>=2 lines)")

        # Check Text Body Spacing (margin-bottom)
        # 0.1in is approx 0.254cm. ODT stores usually in cm or in.
        spacing_ok = False
        for s_name in ["Text_20_body", "Text Body", "Standard"]:
            # Check for margin-bottom
            m_ok, val = check_style_attribute(s_name, "margin-bottom", "fo", lambda x: x != "0in" and x != "0cm")
            if m_ok:
                spacing_ok = True
                break
        
        if spacing_ok:
            score += 20
            feedback.append("Body style spacing (margin-bottom): OK")
        else:
            feedback.append("Body style missing bottom spacing")

        # Basic file existence points
        if result_stats.get("output_exists"):
            score += 10

    except Exception as e:
        logger.error(f"Error parsing ODT: {e}")
        return {"passed": False, "score": score, "feedback": f"Error verifying file structure: {e}"}
    finally:
        if os.path.exists(temp_odt.name):
            os.unlink(temp_odt.name)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }