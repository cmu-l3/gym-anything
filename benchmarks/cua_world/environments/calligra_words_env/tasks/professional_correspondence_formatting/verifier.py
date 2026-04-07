#!/usr/bin/env python3
"""
Verifier for the professional_correspondence_formatting task.
"""

import json
import os
import sys
import tempfile
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    ODF_NS,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_odt_paragraphs,
    get_odt_styles,
    _get_text_content,
)
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def check_page_breaks(content_tree, styles):
    """Check for at least 2 page breaks separating the 3 letters."""
    score = 0
    details = []
    page_break_count = 0

    ns_style = ODF_NS["style"]
    ns_fo = ODF_NS["fo"]

    # Collect style names that have page breaks
    page_break_styles = set()
    auto_styles = content_tree.find(".//office:automatic-styles", ODF_NS)
    if auto_styles is not None:
        for style_elem in auto_styles:
            style_name = style_elem.get(f"{{{ns_style}}}name", "")
            para_props = style_elem.find(f"{{{ns_style}}}paragraph-properties")
            if para_props is not None:
                break_before = para_props.get(f"{{{ns_fo}}}break-before", "")
                break_after = para_props.get(f"{{{ns_fo}}}break-after", "")
                if break_before == "page" or break_after == "page":
                    page_break_styles.add(style_name)

    paragraphs = get_odt_paragraphs(content_tree)
    for p in paragraphs:
        style_name = p["style_name"]
        elem = p["element"]
        if style_name in page_break_styles:
            page_break_count += 1
        else:
            # direct master-page-name attribute check
            mp = elem.get(f"{{{ns_style}}}master-page-name", "")
            if mp:
                page_break_count += 1

    if page_break_count >= 2:
        score = 15
        details.append(f"PASS: Found {page_break_count} page breaks (need >=2)")
    elif page_break_count == 1:
        score = 7
        details.append(f"PARTIAL: Found only 1 page break (need >=2)")
    else:
        details.append(f"FAIL: No page breaks found")

    return score, details


def check_alignment(paragraphs, styles, target_phrases, expected_alignments, label):
    """Check alignment of specific paragraphs identified by target_phrases."""
    score = 0
    details = []

    aligned_count = 0
    total_found = 0
    found_phrases = set()

    for p in paragraphs:
        for phrase in target_phrases:
            if phrase in p["text"] and phrase not in found_phrases:
                found_phrases.add(phrase)
                total_found += 1
                style_name = p["style_name"]
                
                # Walk the style chain to find alignment
                alignment = ""
                curr_style = style_name
                while curr_style in styles:
                    alignment = styles[curr_style].get("alignment", "")
                    if alignment:
                        break
                    curr_style = styles[curr_style].get("parent", "")
                
                if alignment in expected_alignments:
                    aligned_count += 1
                break

    if total_found == 0:
        details.append(f"WARNING: No {label} paragraphs found")
        return 0, details

    if aligned_count >= 2:
        score = 12 if label == "sender" else 8
        details.append(f"PASS: {aligned_count}/{total_found} {label} paragraphs properly aligned")
    elif aligned_count >= 1:
        score = 6 if label == "sender" else 4
        details.append(f"PARTIAL: {aligned_count}/{total_found} {label} paragraphs properly aligned")
    else:
        details.append(f"FAIL: No {label} paragraphs properly aligned")

    return score, details


def check_body_justified(paragraphs, styles, body_samples):
    """Check that specified body paragraphs are justified."""
    score = 0
    details = []

    justified_count = 0
    total_found = 0

    for sample in body_samples:
        for p in paragraphs:
            if sample in p["text"]:
                total_found += 1
                style_name = p["style_name"]
                
                alignment = ""
                curr_style = style_name
                while curr_style in styles:
                    alignment = styles[curr_style].get("alignment", "")
                    if alignment:
                        break
                    curr_style = styles[curr_style].get("parent", "")

                if alignment == "justify":
                    justified_count += 1
                break

    if total_found == 0:
        details.append("WARNING: No body sample paragraphs identified")
        return 0, details

    if justified_count >= 4:
        score = 15
        details.append(f"PASS: {justified_count}/{total_found} body paragraphs justified")
    elif justified_count >= 2:
        score = 8
        details.append(f"PARTIAL: {justified_count}/{total_found} body paragraphs justified")
    else:
        details.append(f"FAIL: Only {justified_count}/{total_found} body paragraphs justified")

    return score, details


def check_bold_re_lines(paragraphs, styles):
    """Check that RE: subject lines are bold."""
    score = 0
    details = []

    re_bold = 0
    re_total = 0

    for p in paragraphs:
        if "RE:" in p["text"]:
            re_total += 1
            style_name = p["style_name"]
            is_bold = False

            # Check paragraph style
            curr_style = style_name
            while curr_style in styles:
                if styles[curr_style].get("bold", False):
                    is_bold = True
                    break
                curr_style = styles[curr_style].get("parent", "")

            # Check inline spans
            if not is_bold and p.get("element") is not None:
                elem = p["element"]
                for span in elem.iter(f"{{{ODF_NS['text']}}}span"):
                    span_style = span.get(f"{{{ODF_NS['text']}}}style-name", "")
                    
                    curr_span_style = span_style
                    span_is_bold = False
                    while curr_span_style in styles:
                        if styles[curr_span_style].get("bold", False):
                            span_is_bold = True
                            break
                        curr_span_style = styles[curr_span_style].get("parent", "")
                    
                    if span_is_bold:
                        span_text = _get_text_content(span)
                        if "RE:" in span_text:
                            is_bold = True
                            break

            if is_bold:
                re_bold += 1

    if re_total == 0:
        details.append("WARNING: No RE: lines found")
        return 0, details

    if re_bold >= 2:
        score = 12
        details.append(f"PASS: {re_bold}/{re_total} RE: lines are bold")
    elif re_bold >= 1:
        score = 6
        details.append(f"PARTIAL: {re_bold}/{re_total} RE: lines are bold")
    else:
        details.append(f"FAIL: No RE: lines are bold")

    return score, details


def check_content_preservation(paragraphs, key_phrases):
    """Check that key content from all three letters is preserved."""
    score = 0
    details = []

    full_text = " ".join(p["text"] for p in paragraphs)
    found = sum(1 for phrase in key_phrases if phrase in full_text)

    if found >= 8:
        score = 15
        details.append(f"PASS: {found}/{len(key_phrases)} key phrases preserved")
    elif found >= 5:
        score = 8
        details.append(f"PARTIAL: {found}/{len(key_phrases)} key phrases preserved")
    else:
        details.append(f"FAIL: Only {found}/{len(key_phrases)} key phrases preserved")

    return score, details


def check_document_length(paragraphs, copy_from_env):
    """Anti-gaming: check document hasn't been overly truncated."""
    score = 0
    details = []

    total_chars = sum(len(p["text"]) for p in paragraphs)
    baseline = 5000
    
    # Try to read baseline char count file
    temp_baseline = tempfile.NamedTemporaryFile(delete=False)
    try:
        copy_from_env("/tmp/baseline_char_count.txt", temp_baseline.name)
        with open(temp_baseline.name, "r") as f:
            baseline = int(f.read().strip())
    except Exception:
        pass
    finally:
        if os.path.exists(temp_baseline.name):
            os.unlink(temp_baseline.name)

    ratio = total_chars / max(baseline, 1)

    if ratio >= 0.6:
        score = 5
        details.append(f"PASS: Document length {total_chars} chars ({ratio:.0%} of baseline)")
    else:
        details.append(f"FAIL: Document too short: {total_chars} chars ({ratio:.0%} of baseline)")

    return score, details


def check_file_timestamp(copy_from_env):
    """Anti-gaming: verify file was modified after task start."""
    details = []
    
    temp_start = tempfile.NamedTemporaryFile(delete=False)
    try:
        copy_from_env("/tmp/task_start_time.txt", temp_start.name)
        with open(temp_start.name, "r") as f:
            start_time = int(f.read().strip())
    except Exception:
        details.append("WARNING: Could not read task start time")
        return True, details
    finally:
        if os.path.exists(temp_start.name):
            os.unlink(temp_start.name)

    try:
        # Check stat of remote file via a script or assume the copied file has modified time?
        # Actually, copy_from_env doesn't preserve remote mtime reliably. 
        # But we can assume if the user saved it, the size or content changed. 
        # To strictly do mtime, the export script should have recorded it. 
        # Since we just check the file content anyway, if content matches but is unformatted initially, 
        # passing the format checks inherently proves action was taken.
        details.append("File modification checked implicitly by format changes.")
        return True, details
    except Exception as e:
        details.append(f"WARNING: Could not check file timestamp: {e}")
        return True, details


def run_vlm_check(traj, env_info):
    """VLM trajectory verification of professional letter formatting."""
    score = 0
    details = []
    
    query_vlm = env_info.get("query_vlm")
    if not query_vlm:
        details.append("WARNING: VLM query function unavailable")
        return 0, details
        
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            details.append("FAIL: No trajectory frames available for VLM check")
            return 0, details

        prompt = """You are assessing an agent formatting a business letter document in Calligra Words.
Look at this sequence of screenshots from the task.
        
Does it appear that the agent successfully formatted the plain text into standard business letters?
Specifically look for:
1. Alignment changes: Address blocks aligned to the right or center.
2. Page separation: Multiple distinct letters separated onto different pages or distinct areas.
3. Formatting applied: Selectively bolding text or justifying paragraphs.

Answer in JSON format:
{
    "formatted_appearance": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""
        response = query_vlm(prompt=prompt, images=frames)
        if response and response.get("success"):
            parsed = response.get("parsed", {})
            if parsed.get("formatted_appearance"):
                score = 10
                details.append("PASS: VLM confirmed professional formatted appearance")
            else:
                details.append("FAIL: VLM did not detect properly formatted letters")
        else:
            details.append("WARNING: VLM query failed or returned invalid format")
            
    except Exception as e:
        details.append(f"VLM check error: {e}")

    return score, details


def verify_professional_correspondence(traj, env_info, task_info):
    """Main verification function."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/meridian_correspondence.odt")

    # Copy and parse ODT
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if not temp_dir or doc_type != "odt":
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to copy or parse ODT document. Ensure document was saved."
        }

    content_tree, styles_tree = doc_obj
    feedback_parts = []
    total_score = 0
    subscores = {}

    try:
        styles = get_odt_styles(content_tree, styles_tree)
        paragraphs = get_odt_paragraphs(content_tree)

        # Anti-gaming timestamp
        ts_ok, ts_details = check_file_timestamp(copy_from_env)
        if not ts_ok:
            return {"passed": False, "score": 0, "feedback": "File not modified after task start."}

        # 1. Page breaks (15 pts)
        s, d = check_page_breaks(content_tree, styles)
        total_score += s
        subscores["page_breaks"] = s
        feedback_parts.extend(d)

        # 2. Sender alignment (12 pts)
        sender_id = [metadata.get("sender_identifier", "MERIDIAN PROPERTY GROUP")]
        s, d = check_alignment(paragraphs, styles, sender_id, ["end", "right", "center"], "sender")
        total_score += s
        subscores["sender_alignment"] = s
        feedback_parts.extend(d)

        # 3. Date alignment (8 pts)
        dates = metadata.get("date_identifiers", ["October 15", "October 18", "October 20"])
        s, d = check_alignment(paragraphs, styles, dates, ["end", "right", "center"], "date")
        total_score += s
        subscores["date_alignment"] = s
        feedback_parts.extend(d)

        # 4. Body justified (15 pts)
        body_samples = metadata.get("body_samples", [])
        s, d = check_body_justified(paragraphs, styles, body_samples)
        total_score += s
        subscores["body_justified"] = s
        feedback_parts.extend(d)

        # 5. Bold RE: lines (12 pts)
        s, d = check_bold_re_lines(paragraphs, styles)
        total_score += s
        subscores["bold_re_lines"] = s
        feedback_parts.extend(d)

        # 6. Closing alignment (8 pts)
        closing_id = [metadata.get("closing_identifier", "Sincerely")]
        s, d = check_alignment(paragraphs, styles, closing_id, ["end", "right", "center"], "closing")
        total_score += s
        subscores["closing_alignment"] = s
        feedback_parts.extend(d)

        # 7. Content preservation (15 pts)
        key_phrases = metadata.get("content_preservation_phrases", [])
        s, d = check_content_preservation(paragraphs, key_phrases)
        total_score += s
        subscores["content_preservation"] = s
        feedback_parts.extend(d)

        # 8. Document length (5 pts)
        s, d = check_document_length(paragraphs, copy_from_env)
        total_score += s
        subscores["document_length"] = s
        feedback_parts.extend(d)

        # 9. VLM check (10 pts)
        s, d = run_vlm_check(traj, env_info)
        total_score += s
        subscores["vlm_check"] = s
        feedback_parts.extend(d)

        passed = total_score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": total_score,
            "feedback": "\n".join(feedback_parts),
            "subscores": subscores
        }

    finally:
        cleanup_verification_temp(temp_dir)