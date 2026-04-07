#!/usr/bin/env python3
"""Verifier for cybersecurity_key_ceremony_formatting task."""

import json
import logging
import os
import re
import sys

# Ensure Calligra parsing utilities are available
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_styles,
    get_odt_tables,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_style_bold(style, styles):
    """Recursively check style definitions for bold text weight."""
    if style.get('bold'):
        return True
    parent = style.get('parent')
    if parent and parent in styles:
        return is_style_bold(styles[parent], styles)
    return False

def verify_cybersecurity_key_ceremony_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/root_ca_ceremony.odt")

    # Fetch and parse the target ODT file
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # --- Anti-gaming: Ensure document isn't truncated ---
        full_text = get_document_text_odt(content_tree)
        if len(full_text) < 1000:
            return {"passed": False, "score": 0, "feedback": "Document content heavily truncated or lost."}

        # --- 1. Title Formatting (10 pts) ---
        title_text = "Root Certificate Authority Key Generation Ceremony"
        title_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(title_text))
        title_size = check_text_font_size_odt(content_tree, styles_tree, re.escape(title_text), 15.5) # Allow slight UI tolerance
        title_align, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(title_text), "center")
        
        if title_bold and title_size and title_align > 0:
            score += 10
            feedback_parts.append("Title formatting: OK")
        else:
            missing = []
            if not title_bold: missing.append("bold")
            if not title_size: missing.append(">=16pt")
            if title_align == 0: missing.append("centered")
            feedback_parts.append(f"Title missing: {', '.join(missing)}")

        # --- 2. Table of Contents (10 pts) ---
        toc_present = detect_toc_odt(content_tree)
        if toc_present:
            score += 10
            feedback_parts.append("TOC: Present")
        else:
            feedback_parts.append("TOC: Missing")

        # --- 3. Heading 1 for Phases (15 pts) ---
        expected_phases = metadata.get("phase_headings", [
            "Pre-Ceremony Environment Setup",
            "HSM Initialization",
            "Root Key Generation",
            "Root Certificate Issuance",
            "Backup and Teardown"
        ])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_phases, 1)
        if h1_matched >= 4:
            score += 15
            feedback_parts.append(f"H1 Phases: {h1_matched}/{h1_total} OK")
        elif h1_matched > 0:
            score += int(15 * (h1_matched / h1_total))
            feedback_parts.append(f"H1 Phases: Partial ({h1_matched}/{h1_total})")
        else:
            feedback_parts.append("H1 Phases: Missing")

        # Parse paragraphs and styles for custom precision checks
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)

        # --- 4. Monospace Commands & Indent (25 pts total: 15 mono, 10 indent) ---
        monospace_fonts = {'courier', 'courier new', 'monospace', 'consolas', 'liberation mono', 'dejavu sans mono', 'noto mono', 'freemono', 'nimbus mono', 'nimbus mono l', 'hack', 'fira code'}
        cmd_count = 0
        mono_count = 0
        indent_count = 0

        for para in paragraphs:
            text = para['text'].strip()
            if text.startswith('>'):
                cmd_count += 1
                style = styles.get(para['style_name'], {})
                font = style.get('font_name', '').lower()
                parent = style.get('parent', '')
                if not font and parent:
                    font = styles.get(parent, {}).get('font_name', '').lower()
                
                # Check Font Family
                is_mono = any(mf in font for mf in monospace_fonts)
                if is_mono:
                    mono_count += 1
                
                # Check Indentation
                m_left = style.get('margin_left', '')
                if not m_left and parent:
                    m_left = styles.get(parent, {}).get('margin_left', '')
                if m_left and m_left not in ('0cm', '0in', '0pt', '0mm'):
                    indent_count += 1

        if cmd_count > 0:
            mono_ratio = mono_count / cmd_count
            indent_ratio = indent_count / cmd_count
            
            if mono_ratio >= 0.8:
                score += 15
                feedback_parts.append("Monospace commands: OK")
            elif mono_ratio > 0:
                score += int(15 * mono_ratio)
                feedback_parts.append(f"Monospace commands: Partial ({mono_count}/{cmd_count})")
            else:
                feedback_parts.append("Monospace commands: Missing")
                
            if indent_ratio >= 0.8:
                score += 10
                feedback_parts.append("Command indent: OK")
            elif indent_ratio > 0:
                score += int(10 * indent_ratio)
                feedback_parts.append(f"Command indent: Partial ({indent_count}/{cmd_count})")
            else:
                feedback_parts.append("Command indent: Missing")
        else:
            feedback_parts.append("Commands (>): None found")

        # --- 5. Role Bolding (25 pts) ---
        role_prefixes = metadata.get("expected_roles", ["Internal Auditor:", "Key Administrator:", "Security Officer:"])
        role_para_count = 0
        bold_role_count = 0
        ns_text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'

        for para in paragraphs:
            text = para['text'].strip()
            for prefix in role_prefixes:
                if text.startswith(prefix):
                    role_para_count += 1
                    elem = para['element']
                    prefix_is_bold = False
                    rest_is_bold = False
                    
                    # Verify entire paragraph isn't just highlighted bold
                    para_style = styles.get(para['style_name'], {})
                    if is_style_bold(para_style, styles):
                        rest_is_bold = True
                    else:
                        for child in elem:
                            if child.tag == f"{{{ns_text}}}span":
                                span_text = "".join(child.itertext()).strip()
                                span_style = styles.get(child.get(f"{{{ns_text}}}style-name", ""), {})
                                if is_style_bold(span_style, styles):
                                    if len(span_text) >= 4 and (span_text in prefix or prefix in span_text):
                                        prefix_is_bold = True
                                    else:
                                        rest_is_bold = True
                                        
                    # Success: Prefix bolded, action text remains normal weight
                    if prefix_is_bold and not rest_is_bold:
                        bold_role_count += 1
                    break

        if role_para_count > 0:
            role_ratio = bold_role_count / role_para_count
            if role_ratio >= 0.8:
                score += 25
                feedback_parts.append("Role bolding: OK")
            elif role_ratio > 0:
                score += int(25 * role_ratio)
                feedback_parts.append(f"Role bolding: Partial ({bold_role_count}/{role_para_count})")
            else:
                feedback_parts.append("Role bolding: Missing or incorrectly applied")
        else:
            feedback_parts.append("Roles: None found")

        # --- 6. Sign-off Table (15 pts) ---
        tables = get_odt_tables(content_tree)
        table_ok = False
        for tbl in tables:
            rows = tbl.get('rows', [])
            if len(rows) >= 3 and len(rows[0]) >= 3:
                header = [str(c).lower().strip() for c in rows[0]]
                if "role" in header[0] and "name" in header[1] and "signature" in header[2]:
                    table_ok = True
                    break
                    
        if table_ok:
            score += 15
            feedback_parts.append("Sign-off table: OK")
        else:
            feedback_parts.append("Sign-off table: Missing or incorrect headers")

        # Pass gate: Must score >= 75 and successfully apply some semantic typography
        key_criteria_met = (mono_count > 0) and (bold_role_count > 0)
        passed = score >= 75 and key_criteria_met
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        cleanup_verification_temp(temp_dir)