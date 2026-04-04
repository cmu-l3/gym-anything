#!/usr/bin/env python3
"""Verifier for ieee_srs_document task.

Verification pipeline:
  1. Read result JSON -> check final_is_new gate
  2. Copy fms_srs_final.docx; parse XML via zipfile
  3. Score 6 criteria (100 pts total, pass >= 65)

Criteria:
  C1 (15 pts): Heading 1 applied to >= 4 top-level sections
  C2 (15 pts): Heading 2 applied to >= 8 sub-sections
  C3 (20 pts): Table of Contents field present (TOC instrText)
  C4 (20 pts): RTM table present with >= 10 rows (rows contain RTM- references)
  C5 (15 pts): Header with 'Collins' or 'PROPRIETARY' and 'FMS'
  C6 (15 pts): Footer with 'CA-FMS4' or 'Revision' or 'Collins'
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

RESULT_PATH = "C:\\Users\\Docker\\ieee_srs_document_result.json"
DOCX_PATH = "C:/Users/Docker/Desktop/WordTasks/fms_srs_final.docx"


def verify_ieee_srs_document(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.mkdtemp(prefix="verify_ieee_srs_")
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
                    "FAIL: fms_srs_final.docx was not saved after task started. "
                    "Use File > Save As to create the final SRS document."
                ),
            }

        # -- STEP 2: Copy and parse -------------------------------------------
        docx_local = os.path.join(tmp, "fms_srs_final.docx")
        try:
            copy_from_env(DOCX_PATH, docx_local)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy output docx: {e}"}

        if not os.path.exists(docx_local) or os.path.getsize(docx_local) == 0:
            return {"passed": False, "score": 0,
                    "feedback": "fms_srs_final.docx not found or empty"}

        if not zipfile.is_zipfile(docx_local):
            return {"passed": False, "score": 0,
                    "feedback": "fms_srs_final.docx is not a valid .docx file"}

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

            # C2: Heading 2 >= 8
            h2_count = len(re.findall(
                r'<w:pStyle\b[^/]*w:val="[Hh]eading\s*2"', doc_xml))
            if h2_count == 0:
                h2_count = len(re.findall(
                    r'<w:pStyle\b[^/]*w:val="[Hh]eading2"', doc_xml))
            if h2_count >= 8:
                score += 15
                fb.append(f"C2 PASS: {h2_count} Heading 2 paragraphs (>= 8 required)")
            elif h2_count >= 4:
                score += 7
                fb.append(f"C2 PARTIAL: {h2_count} Heading 2 paragraphs (need >= 8)")
            else:
                fb.append(f"C2 FAIL: {h2_count} Heading 2 paragraphs (need >= 8)")

            # C3: TOC field present
            has_toc = bool(re.search(r'<w:instrText[^>]*>\s*TOC\b', doc_xml, re.IGNORECASE))
            if not has_toc:
                has_toc = bool(re.search(r'TOC\\', doc_xml))
            if has_toc:
                score += 20
                fb.append("C3 PASS: Table of Contents field found")
            else:
                fb.append("C3 FAIL: Table of Contents not found "
                          "(insert via References > Table of Contents)")

            # C4: RTM table with >= 10 rows
            # Look for table(s) containing RTM references
            table_count = len(re.findall(r"<w:tbl\b", doc_xml))
            rtm_refs = len(re.findall(r"RTM-\d{3}", doc_xml))
            # Count table rows overall
            total_rows = len(re.findall(r"<w:tr\b", doc_xml))
            if table_count >= 1 and rtm_refs >= 10 and total_rows >= 10:
                score += 20
                fb.append(f"C4 PASS: RTM table found with {rtm_refs} RTM references "
                          f"and {total_rows} total rows")
            elif table_count >= 1 and rtm_refs >= 5:
                score += 10
                fb.append(f"C4 PARTIAL: {table_count} table(s) with {rtm_refs} RTM refs "
                          f"(need >= 10 rows)")
            elif table_count >= 1:
                score += 5
                fb.append(f"C4 PARTIAL: {table_count} table(s) found but RTM refs are "
                          f"{rtm_refs} (need >= 10 rows with RTM-NNN identifiers)")
            else:
                fb.append("C4 FAIL: No RTM table found — format RTM entries into a table "
                          "with 6 columns and >= 10 rows")

            # C5: Header with 'Collins' or 'PROPRIETARY' and 'FMS'
            header_ok = False
            for name in zf.namelist():
                if "header" in name.lower() and name.endswith(".xml"):
                    try:
                        hdr_xml = zf.read(name).decode("utf-8", errors="replace")
                        has_collins = "collins" in hdr_xml.lower()
                        has_prop = "proprietary" in hdr_xml.lower()
                        has_fms = "fms" in hdr_xml.lower()
                        if (has_collins or has_prop) and has_fms:
                            header_ok = True
                    except Exception:
                        pass
            if header_ok:
                score += 15
                fb.append("C5 PASS: Header with Collins/PROPRIETARY and FMS found")
            else:
                fb.append("C5 FAIL: Header must contain 'Collins Aerospace' and "
                          "'FMS-4000 SRS' and 'PROPRIETARY' (add via Insert > Header)")

            # C6: Footer with document reference or Collins info
            footer_ok = False
            for name in zf.namelist():
                if "footer" in name.lower() and name.endswith(".xml"):
                    try:
                        ftr_xml = zf.read(name).decode("utf-8", errors="replace")
                        has_doc = "ca-fms4" in ftr_xml.lower() or "revision" in ftr_xml.lower()
                        has_collins = "collins" in ftr_xml.lower()
                        if has_doc or has_collins:
                            footer_ok = True
                    except Exception:
                        pass
            if footer_ok:
                score += 15
                fb.append("C6 PASS: Footer with document reference found")
            else:
                fb.append("C6 FAIL: Footer must contain document number 'CA-FMS4-SRS-001' "
                          "and 'Revision C' (add via Insert > Footer)")

        return {
            "passed": score >= 65,
            "score": score,
            "feedback": " | ".join(fb),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
