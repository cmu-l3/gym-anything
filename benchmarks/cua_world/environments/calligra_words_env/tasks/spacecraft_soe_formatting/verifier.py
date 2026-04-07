#!/usr/bin/env python3
"""Verifier for the spacecraft_soe_formatting task."""

import json
import logging
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_italic_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    detect_toc_odt,
    get_odt_paragraphs,
    get_odt_styles,
    get_odt_tables,
)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _parse_margin_val(margin_str):
    """Parse ODF margin strings like '0.5in' or '1.2cm' into floats (inches roughly converted to cm) to just check > 0."""
    if not margin_str:
        return 0.0
    match = re.search(r'([\d\.]+)', str(margin_str))
    if match:
        return float(match.group(1))
    return 0.0


def _resolve_font_name(styles, style_name):
    """Walk style parent chain to find the font name."""
    visited = set()
    current = style_name
    while current and current not in visited:
        visited.add(current)
        st = styles.get(current, {})
        if 'font_name' in st and st['font_name']:
            return st['font_name']
        current = st.get('parent', '')
    return ""


def _check_monospace_commands(content_tree, styles_tree):
    """Check that [COMMAND: strings are formatted in monospace."""
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)
    
    # We allow any font that implies monospace
    mono_indicators = ['mono', 'courier', 'consolas', 'lucida console', 'inconsolata']
    
    cmd_count = 0
    mono_count = 0
    
    # Text nodes with inline spans are a bit complex in ODF.
    # The get_odt_paragraphs extracts plain text. Let's do a basic search in the XML tree.
    ns = {'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'}
    
    for node in content_tree.iter():
        text_content = ""
        if node.text:
            text_content += node.text
        if node.tail:
            text_content += node.tail
            
        if "[COMMAND:" in text_content:
            cmd_count += 1
            # Check the style of this node or its parent paragraph
            style_name = node.get(f"{{{ns['text']}}}style-name", "")
            if not style_name:
                parent = node.find('..')
                if parent is not None:
                    style_name = parent.get(f"{{{ns['text']}}}style-name", "")
            
            font_name = _resolve_font_name(styles, style_name)
            if any(ind in font_name.lower() for ind in mono_indicators):
                mono_count += 1
                
    return cmd_count, mono_count


def verify_spacecraft_soe_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/artemis_loi_soe.odt")

    # Load the result JSON to check file modification
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document (agent may not have saved it)"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # Check basic file modification (anti-gaming)
        if not result.get("file_modified_during_task", False):
            feedback_parts.append("WARNING: Document was not modified during the task session.")
            # We don't fail immediately, but it's suspicious.

        # ── 1. Title Formatting (Centered, Bold, >= 16pt) - 10 pts ──
        title_text = metadata.get("title_text", "Artemis V Lunar Orbit Insertion (LOI) Sequence of Events")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
        
        if title_bold and title_sized and title_centered > 0:
            score += 10
            feedback_parts.append("Title: Formatted OK")
        else:
            issues = []
            if not title_bold: issues.append("not bold")
            if not title_sized: issues.append("not >=16pt")
            if title_centered == 0: issues.append("not centered")
            feedback_parts.append(f"Title: {', '.join(issues)}")

        # ── 2. Phase Headings (H1) - 10 pts ──
        phase_headings = metadata.get("phase_headings", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, phase_headings, 1)
        if h1_matched >= 3:
            score += 10
            feedback_parts.append("Phase Headings: H1 OK")
        elif h1_matched > 0:
            score += 5
            feedback_parts.append(f"Phase Headings: Partial ({h1_matched}/3)")
        else:
            feedback_parts.append("Phase Headings: None formatted as H1")

        # ── 3. Table Assembly - 20 pts ──
        tables = get_odt_tables(content_tree)
        table_found = False
        for tbl in tables:
            rows = tbl.get("rows", [])
            if len(rows) >= 5: # Should be ~7 rows including header
                text_content = " ".join([" ".join(c) for r in rows for c in r]).lower()
                if "time" in text_content and "event" in text_content and "status" in text_content:
                    table_found = True
                    break
                    
        if table_found:
            score += 20
            feedback_parts.append("Timeline Table: Created OK")
        else:
            feedback_parts.append("Timeline Table: Not found or missing columns/rows")

        # ── 4. Monospace Commands - 20 pts ──
        cmd_expected = metadata.get("command_count", 8)
        cmd_found, cmd_mono = _check_monospace_commands(content_tree, styles_tree)
        
        # Fallback to visual/VLM if exact XML parsing misses it due to complex nesting
        vlm_mono_confirmed = False
        if cmd_mono >= (cmd_expected - 2): # Allow slight misses
            score += 20
            feedback_parts.append(f"Commands: Monospace OK ({cmd_mono}/{cmd_expected})")
        elif cmd_mono > 0:
            score += int(20 * (cmd_mono / cmd_expected))
            feedback_parts.append(f"Commands: Partial monospace ({cmd_mono}/{cmd_expected})")
        else:
            feedback_parts.append("Commands: Monospace formatting not detected in XML")

        # ── 5. Warning Blocks (Indented, Bold) - 15 pts ──
        warn_expected = metadata.get("warning_count", 2)
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)
        
        warn_bold = 0
        warn_indented = 0
        
        for para in paragraphs:
            if "WARNING:" in para['text']:
                style_name = para.get('style_name', '')
                st = styles.get(style_name, {})
                parent_st = styles.get(st.get('parent', ''), {})
                
                # Check bold
                is_bold = st.get('bold') or parent_st.get('bold')
                if not is_bold:
                    # check if the text itself has bold
                    if check_text_bold_odt(content_tree, styles_tree, re.escape(para['text'][:20])):
                        is_bold = True
                if is_bold:
                    warn_bold += 1
                
                # Check indents
                ml = st.get('margin_left') or parent_st.get('margin_left') or "0"
                mr = st.get('margin_right') or parent_st.get('margin_right') or "0"
                
                if _parse_margin_val(ml) > 0 and _parse_margin_val(mr) > 0:
                    warn_indented += 1
                    
        if warn_indented >= warn_expected and warn_bold >= warn_expected:
            score += 15
            feedback_parts.append("Warning Blocks: Indented and Bold OK")
        elif warn_indented > 0 or warn_bold > 0:
            score += 7
            feedback_parts.append(f"Warning Blocks: Partial (Indents: {warn_indented}, Bold: {warn_bold})")
        else:
            feedback_parts.append("Warning Blocks: Not indented/bold")

        # ── 6. Critical Gates (Bold + Italic) - 15 pts ──
        gate_expected = metadata.get("gate_count", 3)
        gate_pattern = r"CRITICAL GO/NO-GO:"
        
        # Check if the specific text is bold and italic
        gate_bold = check_text_bold_odt(content_tree, styles_tree, gate_pattern)
        gate_italic = check_text_italic_odt(content_tree, styles_tree, gate_pattern)
        
        if gate_bold and gate_italic:
            score += 15
            feedback_parts.append("Critical Gates: Bold & Italic OK")
        elif gate_bold or gate_italic:
            score += 7
            feedback_parts.append("Critical Gates: Partial (Missing either Bold or Italic)")
        else:
            feedback_parts.append("Critical Gates: Not formatted")

        # ── 7. Table of Contents - 10 pts ──
        if detect_toc_odt(content_tree):
            score += 10
            feedback_parts.append("TOC: Found OK")
        else:
            feedback_parts.append("TOC: Not found")

        # ── Optional VLM check if programmatic evaluation struggles ──
        if query_vlm and (score < 100):
            try:
                frames = sample_trajectory_frames(traj, n=4)
                final_screenshot = get_final_screenshot(traj)
                images = frames + [final_screenshot] if final_screenshot else frames
                
                if images:
                    prompt = """Analyze these screenshots of a Calligra Words document.
Check for the presence of:
1. A structured TABLE containing Time, Event, Subsystem, and Status columns.
2. Text starting with "[COMMAND:" formatted in a distinct MONOSPACE font.
3. Warning paragraphs visibly INDENTED on both the left and right sides compared to normal text.

Respond in JSON format:
{
  "table_visible": true/false,
  "monospace_commands_visible": true/false,
  "indented_warnings_visible": true/false
}"""
                    vlm_res = query_vlm(prompt=prompt, images=images)
                    if vlm_res.get("success"):
                        parsed = vlm_res.get("parsed", {})
                        
                        # Apply VLM fallback logic for specific hard-to-parse XML criteria
                        if not table_found and parsed.get("table_visible"):
                            score += 15
                            feedback_parts.append("[VLM] Confirmed Table visually")
                            table_found = True
                        if cmd_mono == 0 and parsed.get("monospace_commands_visible"):
                            score += 15
                            feedback_parts.append("[VLM] Confirmed Monospace Commands visually")
                        if warn_indented == 0 and parsed.get("indented_warnings_visible"):
                            score += 10
                            feedback_parts.append("[VLM] Confirmed Indented Warnings visually")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        key_criteria = table_found and (cmd_mono > 0 or vlm_mono_confirmed)
        passed = (score >= 70) and key_criteria
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        cleanup_verification_temp(temp_dir)