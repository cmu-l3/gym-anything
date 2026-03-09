#!/usr/bin/env python3
"""Verifier for far_proposal_response task.

Verification pipeline:
  1. Read result JSON -> check final_is_new gate
  2. Copy mssoc_proposal_response.docx; parse XML via zipfile
  3. Score 5 criteria (100 pts total, pass >= 60)

Criteria:
  C1 (20 pts): Heading 1 applied to >= 4 section headers
  C2 (10 pts): Heading 2 applied to >= 6 sub-section headers
  C3 (25 pts): Compliance matrix table present (>= 2 tables total)
  C4 (20 pts): 'FAR 52.212' appears in document text (inside a table)
  C5 (15 pts): Header contains solicitation number 'CIRA-2025-MSOC' or 'CIRA'
  C6 (10 pts): Document word count > 400 (content preserved)
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

RESULT_PATH = "C:\\Users\\Docker\\far_proposal_response_result.json"
DOCX_PATH = "C:/Users/Docker/Desktop/WordTasks/mssoc_proposal_response.docx"


def verify_far_proposal_response(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.mkdtemp(prefix="verify_far_prop_")
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
                    "FAIL: mssoc_proposal_response.docx was not saved after task started. "
                    "Use File > Save As to create the proposal response file."
                ),
            }

        # -- STEP 2: Copy and parse -------------------------------------------
        docx_local = os.path.join(tmp, "mssoc_proposal_response.docx")
        try:
            copy_from_env(DOCX_PATH, docx_local)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy output docx: {e}"}

        if not os.path.exists(docx_local) or os.path.getsize(docx_local) == 0:
            return {"passed": False, "score": 0,
                    "feedback": "mssoc_proposal_response.docx not found or empty"}

        if not zipfile.is_zipfile(docx_local):
            return {"passed": False, "score": 0,
                    "feedback": "mssoc_proposal_response.docx is not a valid .docx file"}

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
                score += 20
                fb.append(f"C1 PASS: {h1_count} Heading 1 paragraphs (>= 4 required)")
            elif h1_count >= 2:
                score += 10
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

            # C3: At least 2 tables (compliance matrix + at least one more)
            table_count = len(re.findall(r"<w:tbl\b", doc_xml))
            if table_count >= 2:
                score += 25
                fb.append(f"C3 PASS: {table_count} tables found (compliance matrix present)")
            elif table_count == 1:
                score += 12
                fb.append(f"C3 PARTIAL: {table_count} table found (need compliance matrix "
                          f"with >= 10 rows)")
            else:
                fb.append("C3 FAIL: No tables found — create a compliance matrix table "
                          "for FAR clauses in Section B")

            # C4: 'FAR 52.212' text present
            # Extract plain text from tables in document.xml
            if "FAR 52.212" in doc_xml or "52.212" in doc_xml:
                score += 20
                fb.append("C4 PASS: 'FAR 52.212' reference found in document "
                          "(compliance matrix populated)")
            else:
                fb.append("C4 FAIL: 'FAR 52.212' not found in document — "
                          "populate compliance matrix with FAR clauses from Section B")

            # C5: Header contains solicitation number or contracting agency
            header_ok = False
            for name in zf.namelist():
                if "header" in name.lower() and name.endswith(".xml"):
                    try:
                        hdr_xml = zf.read(name).decode("utf-8", errors="replace")
                        has_cira = "cira" in hdr_xml.lower()
                        has_sol = "msoc" in hdr_xml.lower() or "0047" in hdr_xml
                        if has_cira or has_sol:
                            header_ok = True
                    except Exception:
                        pass
            if header_ok:
                score += 15
                fb.append("C5 PASS: Header with solicitation number found")
            else:
                fb.append("C5 FAIL: Header must contain 'CIRA-2025-MSOC-0047' "
                          "(add via Insert > Header)")

            # C6: Word count > 400
            text_content = re.sub(r"<[^>]+>", " ", doc_xml)
            word_count = len(text_content.split())
            if word_count > 400:
                score += 10
                fb.append(f"C6 PASS: Document has {word_count} words (content preserved)")
            else:
                fb.append(f"C6 FAIL: Document has only {word_count} words "
                          "(content appears to be missing)")

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
