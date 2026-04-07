#!/usr/bin/env python3
import json
import logging
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from calligra_verification_utils import (
        check_heading_styles_odt,
        check_paragraph_alignment_odt,
        check_text_bold_odt,
        check_text_font_size_odt,
        copy_and_parse_document
    )
    UTILS_AVAILABLE = True
except ImportError:
    UTILS_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
}

def parse_dimension(dim_str):
    if not dim_str:
        return None
    try:
        if dim_str.endswith('in'):
            return float(dim_str[:-2])
        elif dim_str.endswith('cm'):
            return float(dim_str[:-2]) / 2.54
        elif dim_str.endswith('mm'):
            return float(dim_str[:-2]) / 25.4
        elif dim_str.endswith('pt'):
            return float(dim_str[:-2]) / 72.0
        return float(dim_str)
    except:
        return None

def verify_employee_wellness_brochure_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Read exported JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        export_result = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_modified = export_result.get("file_modified", False)
    if not file_modified:
        return {"passed": False, "score": 0, "feedback": "Document was not modified and saved. Do nothing detected."}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/wellness_brochure_draft.odt")

    if not UTILS_AVAILABLE:
        return {"passed": False, "score": 0, "feedback": "calligra_verification_utils unavailable"}

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    score = 0
    feedback_parts = []
    
    # Check page layout (orientation, columns, margins)
    landscape_found = False
    columns_3_found = False
    narrow_margins_found = False

    for tree in [styles_tree, content_tree]:
        if tree is None:
            continue
        for pl in tree.findall('.//style:page-layout', ODF_NS):
            plp = pl.find('style:page-layout-properties', ODF_NS)
            if plp is not None:
                # Check orientation
                if plp.get(f"{{{ODF_NS['style']}}}print-orientation") == "landscape":
                    landscape_found = True
                
                # Check margins
                mt = parse_dimension(plp.get(f"{{{ODF_NS['fo']}}}margin-top"))
                mb = parse_dimension(plp.get(f"{{{ODF_NS['fo']}}}margin-bottom"))
                ml = parse_dimension(plp.get(f"{{{ODF_NS['fo']}}}margin-left"))
                mr = parse_dimension(plp.get(f"{{{ODF_NS['fo']}}}margin-right"))
                
                margins = [m for m in [mt, mb, ml, mr] if m is not None]
                if len(margins) == 4 and all(m <= 0.6 for m in margins):
                    narrow_margins_found = True
                    
                # Check columns
                cols = plp.find('style:columns', ODF_NS)
                if cols is not None:
                    count = cols.get(f"{{{ODF_NS['fo']}}}column-count")
                    if count == "3":
                        columns_3_found = True

    if landscape_found:
        score += 15
        feedback_parts.append("Landscape orientation: OK")
    else:
        feedback_parts.append("Landscape orientation: FAILED")

    if columns_3_found:
        score += 15
        feedback_parts.append("3-Column layout: OK")
    else:
        feedback_parts.append("3-Column layout: FAILED")

    if narrow_margins_found:
        score += 15
        feedback_parts.append("Narrow margins: OK")
    else:
        feedback_parts.append("Narrow margins: FAILED")

    # Image Check
    images = content_tree.findall('.//draw:image', ODF_NS)
    if len(images) > 0:
        score += 15
        feedback_parts.append("Graphic inserted: OK")
    else:
        feedback_parts.append("Graphic inserted: FAILED")

    # Headings Check
    expected_headings = [
        "Program Overview", "Eligibility", "Covered Services", "Fitness Incentives", "How to Enroll"
    ]
    h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_headings, 1)
    if h1_matched >= 4:
        score += 10
        feedback_parts.append(f"Section headings (H1): {h1_matched}/{h1_total} OK")
    else:
        feedback_parts.append(f"Section headings (H1): only {h1_matched}/{h1_total} (need 4)")

    # Bulleted List Check
    services = ["Health screenings", "Mental health counseling", "Gym membership subsidies", "Nutrition planning"]
    services_in_list = 0
    for svc in services:
        found = False
        for list_elem in content_tree.findall('.//text:list', ODF_NS):
            if svc.lower() in "".join(list_elem.itertext()).lower():
                found = True
                break
        if found:
            services_in_list += 1
            
    if services_in_list >= 3:
        score += 10
        feedback_parts.append(f"Bulleted list items: {services_in_list}/4 OK")
    else:
        feedback_parts.append(f"Bulleted list items: only {services_in_list}/4 (need 3)")

    # Title Formatting Check
    title_pattern = re.escape("Meridian Corp Wellness Program")
    is_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
    is_large = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 15.5)
    align_match, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
    is_centered = align_match > 0

    if is_bold and is_large and is_centered:
        score += 10
        feedback_parts.append("Title formatting (bold, >=16pt, center): OK")
    else:
        issues = []
        if not is_bold: issues.append("not bold")
        if not is_large: issues.append("not >=16pt")
        if not is_centered: issues.append("not centered")
        feedback_parts.append(f"Title formatting: FAILED ({', '.join(issues)})")

    # Body Text Check
    body_samples = [
        re.escape("Meridian Corp is committed to the physical"),
        re.escape("Participation is entirely voluntary"),
        re.escape("We believe that healthy habits should be rewarded")
    ]
    justified_count = 0
    for sample in body_samples:
        matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, sample, "justify")
        if matched > 0:
            justified_count += 1
            
    if justified_count >= 2:
        score += 10
        feedback_parts.append(f"Body justified: {justified_count}/3 OK")
    else:
        feedback_parts.append(f"Body justified: only {justified_count}/3 (need 2)")

    # Required layout elements to pass
    key_criteria_met = landscape_found and columns_3_found

    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }