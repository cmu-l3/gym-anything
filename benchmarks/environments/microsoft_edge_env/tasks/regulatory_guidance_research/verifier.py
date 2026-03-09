#!/usr/bin/env python3
"""
Verifier for Regulatory Guidance Research task.

Scoring (100 points):
- Summary file exists and was modified after task start: 10 points
- At least one PDF downloaded from fda.gov: 30 points
- History shows visits to FDA guidance pages (fda.gov/guidance or /drugs): 20 points
- "FDA Guidance" bookmark folder exists with fda.gov bookmarks: 20 points
- Summary contains FDA regulatory vocabulary (pharmacokinetics, bioavailability, NDA, etc.): 20 points

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/regulatory_guidance_research_result.json"
PASS_THRESHOLD = 60


def verify_regulatory_guidance_research(traj, env_info, task_info):
    """Verify the Regulatory Guidance Research task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

        score = 0
        feedback_parts = []
        subscores = {}

        summary = result.get("summary", {})
        history = result.get("history", {})
        downloads = result.get("downloads", {})
        bookmarks = result.get("bookmarks", {})

        # Criterion 1: Summary file exists and was written after task start (10 pts)
        if summary.get("exists") and summary.get("modified_after_start"):
            score += 10
            subscores["summary_exists"] = True
            feedback_parts.append("Research summary created after task start (10/10)")
        elif summary.get("exists"):
            score += 4
            subscores["summary_exists"] = "stale"
            feedback_parts.append("Summary file exists but may be pre-existing (4/10)")
        else:
            subscores["summary_exists"] = False
            feedback_parts.append("Research summary not found at /home/ga/Desktop/fda_research_summary.txt (0/10)")

        # Criterion 2: At least one PDF downloaded from fda.gov (30 pts)
        new_pdfs = downloads.get("new_pdfs", 0)
        fda_dl = downloads.get("fda_source_downloads", 0)
        if new_pdfs >= 2 and fda_dl >= 1:
            score += 30
            subscores["pdfs_downloaded"] = True
            feedback_parts.append(f"{new_pdfs} PDF(s) downloaded from FDA source (30/30)")
        elif new_pdfs >= 1 and fda_dl >= 1:
            score += 22
            subscores["pdfs_downloaded"] = "partial"
            feedback_parts.append(f"1 PDF downloaded from FDA (required 2) (22/30)")
        elif new_pdfs >= 1:
            score += 15
            subscores["pdfs_downloaded"] = "unconfirmed"
            feedback_parts.append(f"{new_pdfs} PDF(s) downloaded but source not confirmed as FDA (15/30)")
        elif fda_dl >= 1:
            score += 10
            subscores["pdfs_downloaded"] = "download_only"
            feedback_parts.append("Download from FDA detected but no PDF files found in Downloads (10/30)")
        else:
            subscores["pdfs_downloaded"] = False
            feedback_parts.append("No PDF files downloaded from fda.gov (0/30)")

        # Criterion 3: History shows visits to FDA guidance pages (20 pts)
        fda_new = history.get("fda_new", False)
        fda_guidance_pages = history.get("fda_guidance_pages", 0)
        if fda_new and fda_guidance_pages >= 3:
            score += 20
            subscores["fda_visited"] = True
            feedback_parts.append(f"Multiple FDA guidance pages visited ({fda_guidance_pages}) (20/20)")
        elif fda_new and fda_guidance_pages >= 1:
            score += 12
            subscores["fda_visited"] = "partial"
            feedback_parts.append(f"FDA visited but few guidance pages ({fda_guidance_pages}) (12/20)")
        elif fda_new:
            score += 7
            subscores["fda_visited"] = "homepage_only"
            feedback_parts.append("FDA.gov visited but no guidance-specific pages detected (7/20)")
        else:
            subscores["fda_visited"] = False
            feedback_parts.append("No new visits to fda.gov detected (0/20)")

        # Criterion 4: "FDA Guidance" bookmark folder with fda.gov bookmarks (20 pts)
        folder_exists = bookmarks.get("fda_folder_exists", False)
        bm_count = bookmarks.get("fda_bookmark_count", 0)
        has_fda_bm = bookmarks.get("fda_bookmarks_have_fda", False)
        if folder_exists and bm_count >= 2 and has_fda_bm:
            score += 20
            subscores["bookmark_folder"] = True
            feedback_parts.append(f"'FDA Guidance' folder with {bm_count} FDA bookmarks (20/20)")
        elif folder_exists and bm_count >= 1:
            score += 12
            subscores["bookmark_folder"] = "partial"
            feedback_parts.append(f"'FDA Guidance' folder with {bm_count} bookmark(s) (12/20)")
        elif folder_exists:
            score += 5
            subscores["bookmark_folder"] = "empty"
            feedback_parts.append("'FDA Guidance' folder exists but is empty (5/20)")
        else:
            subscores["bookmark_folder"] = False
            feedback_parts.append("No 'FDA Guidance' bookmark folder found (0/20)")

        # Criterion 5: Summary contains FDA regulatory vocabulary (20 pts)
        has_vocab = summary.get("has_fda_vocab", False)
        vocab_found = summary.get("vocab_found", [])
        if has_vocab and len(vocab_found) >= 4:
            score += 20
            subscores["fda_vocabulary"] = True
            feedback_parts.append(f"Summary has rich FDA regulatory vocabulary ({len(vocab_found)} terms) (20/20)")
        elif has_vocab:
            score += 12
            subscores["fda_vocabulary"] = "partial"
            feedback_parts.append(f"Summary has some FDA vocabulary ({vocab_found}) (12/20)")
        else:
            subscores["fda_vocabulary"] = False
            feedback_parts.append("Summary lacks FDA regulatory vocabulary (NDA, pharmacokinetics, etc.) (0/20)")

        score = min(score, 100)
        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores,
            "debug": {
                "fda_guidance_pages": history.get("fda_guidance_pages", 0),
                "new_pdfs": downloads.get("new_pdfs", 0),
                "vocab_found": vocab_found,
            },
        }

    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
