#!/usr/bin/env python3
"""Verifier for the dr_runbook_formatting task."""

import json
import logging
import os
import sys
import tempfile

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_document_text_odt,
    detect_toc_odt,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}


def check_header(styles_tree, expected_text):
    """Check if the document header contains the expected text."""
    if styles_tree is None:
        return False
    
    # Headers are usually defined in master-styles inside styles.xml
    for header in styles_tree.findall(".//style:header", ODF_NS):
        text = "".join(header.itertext())
        if expected_text.lower() in text.lower():
            # Basic alignment check could be added here, but detecting the text
            # inside the <style:header> tag proves the agent successfully used the Header feature.
            return True
    return False


def check_warning_color_and_bold(content_tree, styles_tree, prefixes):
    """Verify that paragraphs starting with specific prefixes are bold and red."""
    style_colors = {}
    style_bolds = {}
    style_parents = {}
    
    # Extract properties from all styles
    for tree in [content_tree, styles_tree]:
        if tree is None: continue
        for style_elem in tree.findall(".//style:style", ODF_NS):
            name = style_elem.get(f"{{{ODF_NS['style']}}}name")
            parent = style_elem.get(f"{{{ODF_NS['style']}}}parent-style-name", "")
            style_parents[name] = parent
            
            text_props = style_elem.find(".//style:text-properties", ODF_NS)
            if text_props is not None:
                color = text_props.get(f"{{{ODF_NS['fo']}}}color", "")
                if color: style_colors[name] = color.lower()
                
                weight = text_props.get(f"{{{ODF_NS['fo']}}}font-weight", "")
                if weight == "bold": style_bolds[name] = True

    def get_color_and_bold(s_name):
        c, b = "", False
        curr = s_name
        seen = set()
        while curr and curr not in seen:
            seen.add(curr)
            if not c and curr in style_colors: c = style_colors[curr]
            if not b and curr in style_bolds: b = style_bolds[curr]
            curr = style_parents.get(curr, "")
        return c, b

    success_count = 0
    target_count = 0
    
    for p in content_tree.findall(".//text:p", ODF_NS):
        text = "".join(p.itertext()).strip()
        if any(text.startswith(prefix) for prefix in prefixes):
            target_count += 1
            s_name = p.get(f"{{{ODF_NS['text']}}}style-name", "")
            c, b = get_color_and_bold(s_name)
            
            # Check inner spans if paragraph style doesn't have it
            if not (c and b):
                for span in p.findall(".//text:span", ODF_NS):
                    span_text = "".join(span.itertext()).strip()
                    if any(span_text.startswith(prefix) for prefix in prefixes) or span_text == text:
                        span_s_name = span.get(f"{{{ODF_NS['text']}}}style-name", "")
                        sc, sb = get_color_and_bold(span_s_name)
                        if sc: c = sc
                        if sb: b = sb

            is_red = c in ["#ff0000", "#e53935", "#d32f2f", "red", "#ff0000"]
            if is_red and b:
                success_count += 1
                
    return success_count, target_count


def check_command_formatting(content_tree, styles_tree, commands):
    """Verify that specific commands are formatted as monospace and bold."""
    style_fonts = {}
    style_bolds = {}
    style_parents = {}
    
    for tree in [content_tree, styles_tree]:
        if tree is None: continue
        for style_elem in tree.findall(".//style:style", ODF_NS):
            name = style_elem.get(f"{{{ODF_NS['style']}}}name")
            parent = style_elem.get(f"{{{ODF_NS['style']}}}parent-style-name", "")
            style_parents[name] = parent
            
            text_props = style_elem.find(".//style:text-properties", ODF_NS)
            if text_props is not None:
                font = text_props.get(f"{{{ODF_NS['style']}}}font-name", "")
                if font: style_fonts[name] = font.lower()
                
                weight = text_props.get(f"{{{ODF_NS['fo']}}}font-weight", "")
                if weight == "bold": style_bolds[name] = True

    def is_monospace_and_bold(s_name):
        f, b = "", False
        curr = s_name
        seen = set()
        while curr and curr not in seen:
            seen.add(curr)
            if not f and curr in style_fonts: f = style_fonts[curr]
            if not b and curr in style_bolds: b = style_bolds[curr]
            curr = style_parents.get(curr, "")
            
        monospace = any(m in f for m in ['mono', 'courier', 'consolas', 'hack'])
        return monospace and b

    success_count = 0
    target_count = len(commands)
    
    for cmd in commands:
        cmd_found = False
        for elem in content_tree.findall(".//*", ODF_NS):
            if elem.tag not in [f"{{{ODF_NS['text']}}}p", f"{{{ODF_NS['text']}}}span"]:
                continue
            text = "".join(elem.itertext())
            if cmd in text:
                s_name = elem.get(f"{{{ODF_NS['text']}}}style-name", "")
                if is_monospace_and_bold(s_name):
                    success_count += 1
                    cmd_found = True
                    break
                    
    return success_count, target_count


def verify_dr_runbook_formatting(traj, env_info, task_info):
    """Main verifier for the runbook formatting task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Check Anti-Gaming (File Modification)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_data.get("file_modified_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Agent failed to save any modifications to the document."
        }

    # 2. Extract Document
    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/postgres_failover_runbook.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    score = 0
    feedback_parts = []

    try:
        # Full text extraction for simple string checks
        full_text = get_document_text_odt(content_tree)

        # ----------------------------------------------------------------
        # Criterion 1: Document Header (15 points)
        # ----------------------------------------------------------------
        expected_header = metadata.get("expected_header_text", "CRITICAL SYSTEM RUNBOOK - TIER 1")
        if check_header(styles_tree, expected_header):
            score += 15
            feedback_parts.append("Document Header: OK")
        else:
            feedback_parts.append("Document Header: Missing or Incorrect")

        # ----------------------------------------------------------------
        # Criterion 2: Warning Formatting (20 points)
        # ----------------------------------------------------------------
        warning_prefixes = metadata.get("warning_prefixes", ["WARNING:", "CRITICAL:"])
        w_success, w_total = check_warning_color_and_bold(content_tree, styles_tree, warning_prefixes)
        
        if w_total > 0:
            pct = w_success / w_total
            pts = int(20 * pct)
            score += pts
            feedback_parts.append(f"Warning Formatting: {w_success}/{w_total} ({pts} pts)")
        else:
            feedback_parts.append("Warning Formatting: 0/2 found")

        # ----------------------------------------------------------------
        # Criterion 3: Command Formatting (20 points)
        # ----------------------------------------------------------------
        target_commands = metadata.get("target_commands", [])
        c_success, c_total = check_command_formatting(content_tree, styles_tree, target_commands)
        
        if c_total > 0:
            pct = c_success / c_total
            pts = int(20 * pct)
            score += pts
            feedback_parts.append(f"Command Formatting: {c_success}/{c_total} ({pts} pts)")
        else:
            feedback_parts.append(f"Command Formatting: 0/{len(target_commands)} found")

        # ----------------------------------------------------------------
        # Criterion 4: Backtick Removal (10 points)
        # ----------------------------------------------------------------
        if "`" not in full_text:
            score += 10
            feedback_parts.append("Backtick Removal: OK")
        else:
            feedback_parts.append("Backtick Removal: Failed (Backticks still present)")

        # ----------------------------------------------------------------
        # Criterion 5: Automated Lists (15 points)
        # ----------------------------------------------------------------
        list_elements = content_tree.findall(".//text:list", ODF_NS)
        if len(list_elements) > 0:
            score += 15
            feedback_parts.append("Automated Lists: OK")
        else:
            feedback_parts.append("Automated Lists: Missing")

        # ----------------------------------------------------------------
        # Criterion 6: Prefix Cleanup (10 points)
        # ----------------------------------------------------------------
        step_prefixes = metadata.get("step_prefixes_to_remove", [])
        prefixes_found = [p for p in step_prefixes if p in full_text]
        if len(prefixes_found) == 0:
            score += 10
            feedback_parts.append("Prefix Cleanup: OK")
        else:
            feedback_parts.append(f"Prefix Cleanup: Failed ({len(prefixes_found)} prefixes still present)")

        # ----------------------------------------------------------------
        # Criterion 7: Table of Contents (10 points)
        # ----------------------------------------------------------------
        if detect_toc_odt(content_tree):
            score += 10
            feedback_parts.append("Table of Contents: OK")
        else:
            feedback_parts.append("Table of Contents: Missing")

        # Ensure safety-critical criteria (Warnings & Commands) have some level of success to pass
        passed = score >= 75 and w_success > 0 and c_success > 0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}