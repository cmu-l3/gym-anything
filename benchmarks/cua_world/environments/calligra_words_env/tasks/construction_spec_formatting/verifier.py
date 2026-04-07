#!/usr/bin/env python3
import logging
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from calligra_verification_utils import (
        check_heading_styles_odt,
        check_paragraph_alignment_odt,
        check_text_bold_odt,
        check_text_font_size_odt,
        copy_and_parse_document,
        get_document_text_odt
    )
except ImportError:
    logging.error("Failed to import calligra_verification_utils")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ODF_NS_LOCAL = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}

def get_element_text(element):
    parts = []
    if element.text:
        parts.append(element.text)
    for child in element:
        parts.append(get_element_text(child))
        if child.tail:
            parts.append(child.tail)
    return ''.join(parts)

def style_has_break(content_tree, style_name):
    if not style_name: 
        return False
    for style in content_tree.findall('.//style:style', ODF_NS_LOCAL):
        if style.get(f"{{{ODF_NS_LOCAL['style']}}}name") == style_name:
            props = style.find(f"{{{ODF_NS_LOCAL['style']}}}paragraph-properties")
            if props is not None:
                if props.get(f"{{{ODF_NS_LOCAL['fo']}}}break-before") == "page":
                    return True
    return False

def check_page_break_before(content_tree, target_text):
    all_paras = []
    for elem in content_tree.iter():
        if elem.tag in (f"{{{ODF_NS_LOCAL['text']}}}p", f"{{{ODF_NS_LOCAL['text']}}}h"):
            all_paras.append(elem)
            
    for i, p in enumerate(all_paras):
        text = get_element_text(p)
        if target_text in text:
            style_name = p.get(f"{{{ODF_NS_LOCAL['text']}}}style-name")
            if style_has_break(content_tree, style_name):
                return True
            if i > 0:
                prev_p = all_paras[i-1]
                prev_text = get_element_text(prev_p).strip()
                if not prev_text:  # Empty paragraph might carry the break (if inserted via manual blank line)
                    prev_style = prev_p.get(f"{{{ODF_NS_LOCAL['text']}}}style-name")
                    if style_has_break(content_tree, prev_style):
                        return True
    return False

def verify_construction_spec_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Anti-gaming: Check file modification timestamps
    mtime_init = 0
    mtime_final = 0
    
    try:
        tmp_init = tempfile.mktemp()
        copy_from_env("/tmp/initial_mtime.txt", tmp_init)
        with open(tmp_init, 'r') as f:
            mtime_init = int(f.read().strip())
        os.unlink(tmp_init)
    except Exception:
        pass
        
    try:
        tmp_fin = tempfile.mktemp()
        copy_from_env("/tmp/final_mtime.txt", tmp_fin)
        with open(tmp_fin, 'r') as f:
            mtime_final = int(f.read().strip())
        os.unlink(tmp_fin)
    except Exception:
        pass

    file_modified = (mtime_final > mtime_init)

    document_path = "/home/ga/Documents/concrete_specification.odt"
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj
    
    score = 0
    feedback_parts = []
    
    # Check 1: File Modified
    if file_modified:
        score += 10
        feedback_parts.append("File modified OK")
    else:
        feedback_parts.append("File NOT modified")

    # Check 2: Title Formatted
    title_text = "SECTION 03 30 00 - CAST-IN-PLACE CONCRETE"
    title_pattern = re.escape(title_text)
    title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
    title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)
    title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
    
    if title_bold and title_sized and title_centered > 0:
        score += 10
        feedback_parts.append("Title formatted OK")
    else:
        issues = []
        if not title_bold: issues.append("not bold")
        if not title_sized: issues.append("<14pt")
        if title_centered == 0: issues.append("not centered")
        feedback_parts.append(f"Title issues: {', '.join(issues)}")
        
    # Check 3: Heading 1
    part_headings = ["PART 1 - GENERAL", "PART 2 - PRODUCTS", "PART 3 - EXECUTION"]
    h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, part_headings, 1)
    if h1_matched == 3:
        score += 15
        feedback_parts.append("Heading 1 OK")
    else:
        feedback_parts.append(f"Heading 1: {h1_matched}/3")
        
    # Check 4: Heading 2
    sub_headings = [
        "1.1 SUMMARY", "1.2 SUBMITTALS", "1.3 QUALITY ASSURANCE", "1.4 DELIVERY, STORAGE, AND HANDLING",
        "2.1 CONCRETE MATERIALS", "2.2 ADMIXTURES", "2.3 CURING MATERIALS", "2.4 RELATED MATERIALS",
        "3.1 PREPARATION", "3.2 PLACING CONCRETE", "3.3 FINISHING", "3.4 CONCRETE PROTECTING AND CURING"
    ]
    h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, sub_headings, 2)
    if h2_matched >= 9:
        score += 15
        feedback_parts.append(f"Heading 2 OK ({h2_matched}/12)")
    else:
        feedback_parts.append(f"Heading 2: {h2_matched}/12")
        
    # Check 5: Page Breaks
    pb_part2 = check_page_break_before(content_tree, "PART 2 - PRODUCTS")
    pb_part3 = check_page_break_before(content_tree, "PART 3 - EXECUTION")
    if pb_part2 and pb_part3:
        score += 15
        feedback_parts.append("Page breaks OK")
    else:
        missing_pb = []
        if not pb_part2: missing_pb.append("PART 2")
        if not pb_part3: missing_pb.append("PART 3")
        feedback_parts.append(f"Page breaks missing before: {', '.join(missing_pb)}")
        
    # Check 6 & 7: Header & Footer
    header_found = False
    footer_found = False
    for tree in [content_tree, styles_tree]:
        if tree is None: continue
        for header in tree.findall('.//style:header', ODF_NS_LOCAL):
            if "Project: City Library Expansion".lower() in get_element_text(header).lower():
                header_found = True
        for footer in tree.findall('.//style:footer', ODF_NS_LOCAL):
            if "Section 03 30 00".lower() in get_element_text(footer).lower():
                footer_found = True
                
    if header_found:
        score += 15
        feedback_parts.append("Header OK")
    else:
        feedback_parts.append("Header missing/incorrect")
        
    if footer_found:
        score += 10
        feedback_parts.append("Footer OK")
    else:
        feedback_parts.append("Footer missing/incorrect")
        
    # Check 8: Content Preserved
    full_text = get_document_text_odt(content_tree)
    words = len(full_text.split())
    if words >= 350:  # Ensures the agent didn't delete the document
        score += 10
        feedback_parts.append(f"Content preserved ({words} words)")
    else:
        feedback_parts.append(f"Content truncated ({words} words)")
        
    # Final passing logic: Must achieve >= 75 points and MUST have header/footer formatted correctly (proving they used the page layout GUI)
    key_criteria_met = (header_found or footer_found) and file_modified
    passed = (score >= 75) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }