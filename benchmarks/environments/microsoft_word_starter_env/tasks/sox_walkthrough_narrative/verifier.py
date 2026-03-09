#!/usr/bin/env python3
"""Verifier for sox_walkthrough_narrative task.

Verification pipeline:
  1. Read result JSON -> check final_is_new gate
  2. Copy ap_walkthrough_final.docx; parse XML via zipfile
  3. Score 6 criteria (100 pts total, pass >= 60)

Criteria:
  C1 (15 pts): Heading 1 applied to >= 4 section headers
  C2 (10 pts): Heading 2 applied to >= 6 sub-section headers
  C3 (25 pts): At least 3 tables present (<w:tbl>) for control descriptions
  C4 (20 pts): Custom style 'Control Description' exists in word/styles.xml
  C5 (15 pts): At least 3 footnotes present in word/footnotes.xml
  C6 (15 pts): Document header contains 'Meridian' and 'SOX' or 'CONFIDENTIAL'
"""
import json
import logging
import os
import re
import shutil
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\sox_walkthrough_narrative_result.json"
DOCX_PATH = "C:/Users/Docker/Desktop/WordTasks/ap_walkthrough_final.docx"


def verify_sox_walkthrough_narrative(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.mkdtemp(prefix="verify_sox_wt_")
    try:
        # -- STEP 1: Read result JSON -----------------------------------------
        json_local = os.path.join(tmp, "result.json")
        result = {}
        try:
            copy_from_env(RESULT_PATH, json_local)
            with open(json_local, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not read result JSON: {e}")

        file_info = result.get("output_file", {})
        if not file_info.get("final_is_new", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "FAIL: ap_walkthrough_final.docx was not saved after task started. "
                    "Use File > Save As to create the formatted file."
                ),
            }

        # -- STEP 2: Copy and parse -------------------------------------------
        docx_local = os.path.join(tmp, "ap_walkthrough_final.docx")
        try:
            copy_from_env(DOCX_PATH, docx_local)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy output docx: {e}"}

        if not os.path.exists(docx_local) or os.path.getsize(docx_local) == 0:
            return {"passed": False, "score": 0,
                    "feedback": "ap_walkthrough_final.docx not found or empty"}

        if not zipfile.is_zipfile(docx_local):
            return {"passed": False, "score": 0,
                    "feedback": "ap_walkthrough_final.docx is not a valid .docx file"}

        score = 0
        fb = []

        with zipfile.ZipFile(docx_local, "r") as zf:
            try:
                doc_xml = zf.read("word/document.xml").decode("utf-8", errors="replace")
            except KeyError:
                return {"passed": False, "score": 0,
                        "feedback": "word/document.xml not found in docx"}

            # C1: Heading 1 >= 4
            h1_count = len(re.findall(
                r'<w:pStyle\b[^/]*w:val="[Hh]eading\s*1"', doc_xml))
            if h1_count == 0:
                h1_count = len(re.findall(
                    r'<w:pStyle\b[^/]*w:val="[Hh]eading1"', doc_xml))
            if h1_count >= 4:
                score += 15
                fb.append(f"C1 PASS: {h1_count} Heading 1 paragraphs (>= 4 required)")
            elif h1_count >= 2:
                score += 7
                fb.append(f"C1 PARTIAL: {h1_count} Heading 1 paragraphs (need >= 4)")
            else:
                fb.append(f"C1 FAIL: {h1_count} Heading 1 paragraphs (need >= 4)")

            # C2: Heading 2 >= 6
            h2_count = len(re.findall(
                r'<w:pStyle\b[^/]*w:val="[Hh]eading\s*2"', doc_xml))
            if h2_count == 0:
                h2_count = len(re.findall(
                    r'<w:pStyle\b[^/]*w:val="[Hh]eading2"', doc_xml))
            if h2_count >= 6:
                score += 10
                fb.append(f"C2 PASS: {h2_count} Heading 2 paragraphs (>= 6 required)")
            elif h2_count >= 3:
                score += 5
                fb.append(f"C2 PARTIAL: {h2_count} Heading 2 paragraphs (need >= 6)")
            else:
                fb.append(f"C2 FAIL: {h2_count} Heading 2 paragraphs (need >= 6)")

            # C3: At least 3 tables
            table_count = len(re.findall(r"<w:tbl\b", doc_xml))
            if table_count >= 3:
                score += 25
                fb.append(f"C3 PASS: {table_count} tables found (>= 3 control tables required)")
            elif table_count >= 1:
                score += 10
                fb.append(f"C3 PARTIAL: {table_count} table(s) found (need >= 3 control tables)")
            else:
                fb.append("C3 FAIL: No tables found — convert 5 controls into tables")

            # C4: Custom style 'Control Description' in styles.xml
            custom_style_found = False
            try:
                styles_xml = zf.read("word/styles.xml").decode("utf-8", errors="replace")
                if re.search(r'[Cc]ontrol\s*[Dd]escription', styles_xml):
                    custom_style_found = True
            except KeyError:
                pass
            if custom_style_found:
                score += 20
                fb.append("C4 PASS: Custom style 'Control Description' found in styles.xml")
            else:
                fb.append("C4 FAIL: Custom style 'Control Description' not found — "
                          "create this style via Home > Styles panel")

            # C5: At least 3 footnotes
            footnote_count = 0
            try:
                fn_xml = zf.read("word/footnotes.xml").decode("utf-8", errors="replace")
                all_fn = len(re.findall(r"<w:footnote\b", fn_xml))
                footnote_count = max(0, all_fn - 2)  # subtract 2 separator footnotes
            except KeyError:
                footnote_count = 0
            if footnote_count >= 3:
                score += 15
                fb.append(f"C5 PASS: {footnote_count} footnote(s) found (>= 3 required)")
            elif footnote_count >= 1:
                score += 7
                fb.append(f"C5 PARTIAL: {footnote_count} footnote(s) found (need >= 3)")
            else:
                fb.append("C5 FAIL: No footnotes found — insert 3 footnotes with citations")

            # C6: Header contains 'Meridian' and ('SOX' or 'CONFIDENTIAL')
            header_ok = False
            for name in zf.namelist():
                if "header" in name.lower() and name.endswith(".xml"):
                    try:
                        hdr_xml = zf.read(name).decode("utf-8", errors="replace")
                        has_meridian = "meridian" in hdr_xml.lower()
                        has_sox_or_conf = ("sox" in hdr_xml.lower() or
                                           "confidential" in hdr_xml.lower())
                        if has_meridian and has_sox_or_conf:
                            header_ok = True
                    except Exception:
                        pass
            if header_ok:
                score += 15
                fb.append("C6 PASS: Header with 'Meridian' and classification found")
            else:
                fb.append("C6 FAIL: Header must contain 'Meridian Global Industries' "
                          "and 'CONFIDENTIAL' (add via Insert > Header)")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(fb),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
