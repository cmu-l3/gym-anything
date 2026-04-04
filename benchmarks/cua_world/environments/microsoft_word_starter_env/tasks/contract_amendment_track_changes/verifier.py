#!/usr/bin/env python3
"""Verifier for contract_amendment_track_changes task.

Verification pipeline:
  1. Read result JSON -> check final_is_new gate (score 0 if file not saved)
  2. Copy patent_license_final.docx from VM; parse word/document.xml via zipfile
  3. Score 5 criteria (100 pts total, pass >= 60)

Criteria:
  C1 (25 pts): Zero <w:ins> tracked insertions remain (all accepted/rejected)
  C2 (25 pts): Zero <w:del> tracked deletions remain
  C3 (15 pts): 'sublicensable' present in document text (correct insertion accepted)
  C4 (15 pts): 'thirty (30) days' present in document text (correct insertion accepted)
  C5 (20 pts): At least 2 footnotes present in word/footnotes.xml
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

RESULT_PATH = "C:\\Users\\Docker\\contract_amendment_track_changes_result.json"
DOCX_PATH = "C:/Users/Docker/Desktop/WordTasks/patent_license_final.docx"


def verify_contract_amendment_track_changes(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.mkdtemp(prefix="verify_contract_tc_")
    try:
        # -- STEP 1: Read result JSON and check is_new gate --------------------
        json_local = os.path.join(tmp, "result.json")
        result = {}
        try:
            copy_from_env(RESULT_PATH, json_local)
            with open(json_local, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not read result JSON: {e}")

        output_file_info = result.get("output_file", {})
        if not output_file_info.get("final_is_new", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "FAIL: patent_license_final.docx was not saved after task started "
                    "(is_new=False). Agent must use File > Save As to create the final file."
                ),
            }

        # -- STEP 2: Copy and parse the output docx ---------------------------
        docx_local = os.path.join(tmp, "patent_license_final.docx")
        try:
            copy_from_env(DOCX_PATH, docx_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy output docx: {e}"}

        if not os.path.exists(docx_local) or os.path.getsize(docx_local) == 0:
            return {"passed": False, "score": 0,
                    "feedback": "patent_license_final.docx not found or empty"}

        if not zipfile.is_zipfile(docx_local):
            return {"passed": False, "score": 0,
                    "feedback": "patent_license_final.docx is not a valid .docx file"}

        # -- STEP 3: Score criteria -------------------------------------------
        score = 0
        fb = []

        with zipfile.ZipFile(docx_local, "r") as zf:
            # Read document.xml
            try:
                doc_xml = zf.read("word/document.xml").decode("utf-8", errors="replace")
            except KeyError:
                return {"passed": False, "score": 0,
                        "feedback": "word/document.xml not found in docx"}

            # C1: Zero <w:ins> elements
            ins_count = len(re.findall(r"<w:ins\b", doc_xml))
            if ins_count == 0:
                score += 25
                fb.append("C1 PASS: No tracked insertions remain (0 <w:ins>)")
            else:
                fb.append(f"C1 FAIL: {ins_count} tracked insertion(s) still present "
                          f"(must Accept All Changes)")

            # C2: Zero <w:del> elements
            del_count = len(re.findall(r"<w:del\b", doc_xml))
            if del_count == 0:
                score += 25
                fb.append("C2 PASS: No tracked deletions remain (0 <w:del>)")
            else:
                fb.append(f"C2 FAIL: {del_count} tracked deletion(s) still present "
                          f"(must Accept All Changes)")

            # C3: 'sublicensable' present (correct insertion accepted, not rejected)
            if "sublicensable" in doc_xml.lower():
                score += 15
                fb.append("C3 PASS: 'sublicensable' found in document (correct change accepted)")
            else:
                fb.append("C3 FAIL: 'sublicensable' not found — ensure R. Chen's insertion "
                          "in Section 2.1 was accepted (not rejected)")

            # C4: 'thirty (30) days' present
            if "thirty (30) days" in doc_xml.lower():
                score += 15
                fb.append("C4 PASS: 'thirty (30) days' found in document (correct change accepted)")
            else:
                fb.append("C4 FAIL: 'thirty (30) days' not found — ensure R. Chen's insertion "
                          "in Section 5.2 was accepted (not rejected)")

            # C5: At least 2 footnotes in word/footnotes.xml
            footnote_count = 0
            try:
                fn_xml = zf.read("word/footnotes.xml").decode("utf-8", errors="replace")
                # Count <w:footnote> elements with w:type="normal" or no type (exclude
                # separator/continuationSeparator footnotes which are always present)
                footnote_count = len(re.findall(
                    r'<w:footnote\b(?:(?!w:type="separator"|w:type="continuationSeparator").)*?>',
                    fn_xml,
                    re.DOTALL,
                ))
                # Subtract 2 for the mandatory separator footnotes Word always inserts
                footnote_count = max(0, footnote_count - 2)
            except KeyError:
                footnote_count = 0

            if footnote_count >= 2:
                score += 20
                fb.append(f"C5 PASS: {footnote_count} footnote(s) found "
                          f"(need >= 2 legal citations)")
            elif footnote_count == 1:
                score += 10
                fb.append(f"C5 PARTIAL: {footnote_count} footnote found (need >= 2)")
            else:
                fb.append("C5 FAIL: No footnotes found — insert 2 footnotes with legal "
                          "citations per task description")

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
