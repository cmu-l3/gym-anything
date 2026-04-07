#!/usr/bin/env python3
"""Verifier for the hics_job_action_sheet_formatting task."""

import os
import re
import sys
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_tables
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Basic namespaces for ODF XML checks
ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}

def count_page_breaks(content_tree, styles_tree):
    """Scan ODF trees for explicit page breaks injected before paragraphs."""
    breaks = 0
    break_styles = set()
    for tree in (content_tree, styles_tree):
        if tree is None: 
            continue
        for style in tree.findall('.//style:style', ODF_NS):
            style_name = style.get(f"{{{ODF_NS['style']}}}name")
            para_props = style.find(f"{{{ODF_NS['style']}}}paragraph-properties")
            if para_props is not None:
                bb = para_props.get(f"{{{ODF_NS['fo']}}}break-before")
                ba = para_props.get(f"{{{ODF_NS['fo']}}}break-after")
                if bb == 'page' or ba == 'page':
                    break_styles.add(style_name)
    
    for p in content_tree.findall('.//text:p', ODF_NS) + content_tree.findall('.//text:h', ODF_NS):
        style_name = p.get(f"{{{ODF_NS['text']}}}style-name")
        if style_name in break_styles:
            breaks += 1
            
    return breaks

def count_lists(content_tree):
    """Count explicit ODF list blocks."""
    lists = content_tree.findall('.//text:list', ODF_NS)
    return len(lists)
    
def verify_hics_job_action_sheet_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    # Check if the requested output file exists
    document_path = "/home/ga/Documents/hics_jas_formatted.odt"
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    
    if temp_dir is None:
        # Fallback to the original file if the agent saved in place
        document_path = "/home/ga/Documents/hics_jas_raw.odt"
        temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
        
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Could not retrieve saved ODT document"}
        
    content_tree, styles_tree = doc_obj
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Page breaks (15 points) - expected at least 3 (to separate 4 roles)
        breaks = count_page_breaks(content_tree, styles_tree)
        if breaks >= 3:
            score += 15
            feedback_parts.append(f"Page breaks: {breaks} found (OK)")
        elif breaks > 0:
            score += 5
            feedback_parts.append(f"Page breaks: {breaks} found (Need >= 3)")
        else:
            feedback_parts.append("Page breaks: 0 found")
            
        # 2. Title Formatting: H1 and Centered (15 points)
        roles = [
            "Incident Commander", 
            "Medical Care Branch Director", 
            "Security Branch Director", 
            "Public Information Officer"
        ]
        matched_h1 = 0
        for role in roles:
            target = f"JOB ACTION SHEET: {role}"
            h_matched, _, _ = check_heading_styles_odt(content_tree, styles_tree, [target], 1)
            a_matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(target), "center")
            if h_matched > 0 and a_matched > 0:
                matched_h1 += 1
                
        if matched_h1 >= 3:
            score += 15
            feedback_parts.append(f"Title Formatting: {matched_h1}/4 OK")
        elif matched_h1 > 0:
            score += int(15 * (matched_h1 / 4))
            feedback_parts.append(f"Title Formatting: {matched_h1}/4")
        else:
            feedback_parts.append("Title Formatting: 0/4")
            
        # 3. Position Details Tables (20 points)
        tables = get_odt_tables(content_tree)
        valid_tables = 0
        for tbl in tables:
            tbl_text = ""
            for row in tbl.get('rows', []):
                tbl_text += " ".join(row).lower() + " "
            if "reports to" in tbl_text or "location" in tbl_text or "radio title" in tbl_text:
                valid_tables += 1
                
        if valid_tables >= 3:
            score += 20
            feedback_parts.append(f"Tables: {valid_tables} OK")
        elif valid_tables > 0:
            score += int(20 * (valid_tables / 4))
            feedback_parts.append(f"Tables: {valid_tables} created")
        else:
            feedback_parts.append("Tables: 0 valid tables found")
            
        # 4. Phase Subheadings: H2 (15 points)
        phases = [
            "Immediate Actions (0-2 Hours)",
            "Intermediate Actions (2-12 Hours)", 
            "Extended Actions (12+ Hours)"
        ]
        h2_matched, _, _ = check_heading_styles_odt(content_tree, styles_tree, phases, 2)
        if h2_matched >= 2:
            score += 15
            feedback_parts.append(f"Phase H2 Headings: {h2_matched}/3 OK")
        elif h2_matched > 0:
            score += 5
            feedback_parts.append(f"Phase H2 Headings: {h2_matched}/3")
        else:
            feedback_parts.append("Phase H2 Headings: 0/3")
            
        # 5. Action Lists (15 points)
        num_lists = count_lists(content_tree)
        if num_lists >= 3:
            score += 15
            feedback_parts.append(f"Lists: {num_lists} found OK")
        elif num_lists > 0:
            score += 5
            feedback_parts.append(f"Lists: {num_lists} found")
        else:
            feedback_parts.append("Lists: 0 found")
            
        # 6. Safety Notes Bolded (10 points)
        safety_notes = [
            "Ensure personal protective equipment",
            "Monitor staff for heat stress",
            "Verify all facility access points",
            "Do not release patient names"
        ]
        bold_notes = 0
        for note in safety_notes:
            if check_text_bold_odt(content_tree, styles_tree, re.escape(note)):
                bold_notes += 1
                
        if bold_notes >= 3:
            score += 10
            feedback_parts.append(f"Safety Notes Bold: {bold_notes}/4 OK")
        elif bold_notes > 0:
            score += int(10 * (bold_notes / 4))
            feedback_parts.append(f"Safety Notes Bold: {bold_notes}/4")
        else:
            feedback_parts.append("Safety Notes Bold: 0/4")
            
        # 7. Content Preservation (10 points)
        full_text = get_document_text_odt(content_tree).lower()
        keywords = [
            "incident command",
            "establish the hospital command center",
            "medical care branch",
            "triage protocols",
            "security branch",
            "facility lockdown",
            "public information officer",
            "media staging area"
        ]
        kw_found = sum(1 for kw in keywords if kw in full_text)
        if kw_found >= 6:
            score += 10
            feedback_parts.append(f"Content preserved: {kw_found}/{len(keywords)}")
        else:
            feedback_parts.append(f"Content lost: {kw_found}/{len(keywords)} preserved")
            
    finally:
        cleanup_verification_temp(temp_dir)
        
    passed = score >= 75 and valid_tables >= 3 and breaks >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }