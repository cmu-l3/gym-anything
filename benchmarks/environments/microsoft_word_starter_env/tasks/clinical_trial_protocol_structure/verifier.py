#!/usr/bin/env python3
"""Verifier for clinical_trial_protocol_structure task.

Verification pipeline:
  1. Read result JSON -> check final_is_new gate
  2. Copy oncology_protocol_final.docx; parse word/document.xml via zipfile
  3. Score 6 criteria (100 pts total, pass >= 60)

Criteria:
  C1 (20 pts): Heading 1 style applied to >= 6 major sections
  C2 (15 pts): Heading 2 style applied to >= 8 sub-sections
  C3 (25 pts): Table of Contents field (TOC) present in document.xml
  C4 (15 pts): At least 1 table (<w:tbl>) present (Schedule of Assessments)
  C5 (15 pts): Footer containing 'CONFIDENTIAL' and 'HRZ-NSCLC' (or 'Confidential')
  C6 (10 pts): Document word count > 800 (sufficient content retained)
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

RESULT_PATH = "C:\\Users\\Docker\\clinical_trial_protocol_structure_result.json"
DOCX_PATH = "C:/Users/Docker/Desktop/WordTasks/oncology_protocol_final.docx"


def _count_heading_style(doc_xml, style_val):
    """Count paragraphs with the given heading style value (case-insensitive)."""
    pattern = rf'<w:pStyle\s+w:val="(?i:{re.escape(style_val)})"'
    return len(re.findall(pattern, doc_xml, re.IGNORECASE))


def verify_clinical_trial_protocol_structure(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.mkdtemp(prefix="verify_clinical_proto_")
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
                    "FAIL: oncology_protocol_final.docx was not saved after task started. "
                    "Use File > Save As to save as a new file."
                ),
            }

        # -- STEP 2: Copy and parse -------------------------------------------
        docx_local = os.path.join(tmp, "oncology_protocol_final.docx")
        try:
            copy_from_env(DOCX_PATH, docx_local)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy output docx: {e}"}

        if not os.path.exists(docx_local) or os.path.getsize(docx_local) == 0:
            return {"passed": False, "score": 0,
                    "feedback": "oncology_protocol_final.docx not found or empty"}

        if not zipfile.is_zipfile(docx_local):
            return {"passed": False, "score": 0,
                    "feedback": "oncology_protocol_final.docx is not a valid .docx file"}

        score = 0
        fb = []

        with zipfile.ZipFile(docx_local, "r") as zf:
            try:
                doc_xml = zf.read("word/document.xml").decode("utf-8", errors="replace")
            except KeyError:
                return {"passed": False, "score": 0,
                        "feedback": "word/document.xml not found in docx"}

            # C1: Heading 1 count >= 6
            h1_count = len(re.findall(
                r'<w:pStyle\b[^/]*w:val="[Hh]eading\s*1"', doc_xml))
            if h1_count == 0:
                # Try alternate style value patterns Word may use
                h1_count = len(re.findall(
                    r'<w:pStyle\b[^/]*w:val="[Hh]eading1"', doc_xml))
            if h1_count >= 6:
                score += 20
                fb.append(f"C1 PASS: {h1_count} Heading 1 paragraphs found (>= 6 required)")
            elif h1_count >= 3:
                score += 10
                fb.append(f"C1 PARTIAL: {h1_count} Heading 1 paragraphs (need >= 6)")
            else:
                fb.append(f"C1 FAIL: {h1_count} Heading 1 paragraphs (need >= 6)")

            # C2: Heading 2 count >= 8
            h2_count = len(re.findall(
                r'<w:pStyle\b[^/]*w:val="[Hh]eading\s*2"', doc_xml))
            if h2_count == 0:
                h2_count = len(re.findall(
                    r'<w:pStyle\b[^/]*w:val="[Hh]eading2"', doc_xml))
            if h2_count >= 8:
                score += 15
                fb.append(f"C2 PASS: {h2_count} Heading 2 paragraphs found (>= 8 required)")
            elif h2_count >= 4:
                score += 7
                fb.append(f"C2 PARTIAL: {h2_count} Heading 2 paragraphs (need >= 8)")
            else:
                fb.append(f"C2 FAIL: {h2_count} Heading 2 paragraphs (need >= 8)")

            # C3: TOC field present
            has_toc = bool(re.search(r'<w:instrText[^>]*>\s*TOC\b', doc_xml, re.IGNORECASE))
            if not has_toc:
                # Also check for TOC content control / SDT
                has_toc = bool(re.search(r'TOC\\', doc_xml))
            if has_toc:
                score += 25
                fb.append("C3 PASS: Table of Contents field found in document")
            else:
                fb.append("C3 FAIL: Table of Contents not found "
                          "(insert via References > Table of Contents)")

            # C4: At least 1 table
            table_count = len(re.findall(r"<w:tbl\b", doc_xml))
            if table_count >= 1:
                score += 15
                fb.append(f"C4 PASS: {table_count} table(s) found "
                          f"(Schedule of Assessments table present)")
            else:
                fb.append("C4 FAIL: No tables found — insert Schedule of Assessments table")

            # C5: Footer with CONFIDENTIAL
            footer_found = False
            footer_keywords = False
            for name in zf.namelist():
                if "footer" in name.lower() and name.endswith(".xml"):
                    try:
                        ftr_xml = zf.read(name).decode("utf-8", errors="replace")
                        if "confidential" in ftr_xml.lower():
                            footer_found = True
                        if "hrz-nsclc" in ftr_xml.lower() or "hrz" in ftr_xml.lower():
                            footer_keywords = True
                    except Exception:
                        pass
            if footer_found and footer_keywords:
                score += 15
                fb.append("C5 PASS: Footer with CONFIDENTIAL and protocol number found")
            elif footer_found:
                score += 8
                fb.append("C5 PARTIAL: Footer with CONFIDENTIAL found but protocol number "
                          "HRZ-NSCLC-301 missing")
            else:
                fb.append("C5 FAIL: No footer with CONFIDENTIAL text found "
                          "(add via Insert > Footer)")

            # C6: Word count > 800 (text was not accidentally deleted)
            text_content = re.sub(r"<[^>]+>", " ", doc_xml)
            word_count = len(text_content.split())
            if word_count > 800:
                score += 10
                fb.append(f"C6 PASS: Document has {word_count} words (content preserved)")
            else:
                fb.append(f"C6 FAIL: Document has only {word_count} words "
                          f"(much content appears to be missing)")

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
