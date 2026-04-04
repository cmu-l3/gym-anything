#!/usr/bin/env python3
"""
Verifier for citation_qa_export task.

Task: Fix metadata problems in 20 "cite-in-paper" tagged CS theory papers:
  - 3 papers have empty journal/venue fields → fill them in
  - 3 pairs of duplicate entries (6 items) → merge to 3 unique items
  Then export all cite-in-paper items as BibTeX to /home/ga/Desktop/references.bib

Scoring (100 points):
  - Empty journal fields filled (3 papers): 30 pts (10 each)
  - Duplicate entries resolved (3 pairs): 30 pts (10 each)
  - BibTeX file exported and non-empty: 25 pts
  - BibTeX has no duplicate citekeys: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EMPTY_JOURNAL_TITLES = [
    "Algebraic Complexity Theory and Circuit Lower Bounds",
    "Interactive Proofs and Zero-Knowledge Arguments",
    "Parameterized Complexity and Kernelization",
]
DUPLICATE_TITLES = [
    "Linear Programming and Extensions",
    "Computability and Unsolvability",
    "Foundations of Cryptography: Basic Tools",
]


def verify_citation_qa_export(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/citation_qa_export_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Empty journal fields filled (30 pts, 10 each)
    journal_status = result.get("empty_journal_status", {})
    journal_fixed = 0
    for title in EMPTY_JOURNAL_TITLES:
        info = journal_status.get(title, {})
        if info.get("has_journal"):
            journal_fixed += 1
    journal_pts = journal_fixed * 10
    score += journal_pts
    subscores["empty_journals_fixed"] = f"{journal_fixed}/3"
    if journal_fixed == 3:
        feedback_parts.append("All 3 empty journal fields filled")
    else:
        feedback_parts.append(f"Empty journal fields filled: {journal_fixed}/3")

    # Criterion 2: Duplicates merged (30 pts, 10 each)
    dup_counts = result.get("duplicate_title_counts", {})
    duplicates_resolved = 0
    for title in DUPLICATE_TITLES:
        count = dup_counts.get(title, 2)
        if count <= 1:
            duplicates_resolved += 1
    dup_pts = duplicates_resolved * 10
    score += dup_pts
    subscores["duplicates_resolved"] = f"{duplicates_resolved}/3"
    if duplicates_resolved == 3:
        feedback_parts.append("All 3 duplicate pairs merged")
    else:
        feedback_parts.append(f"Duplicates merged: {duplicates_resolved}/3")

    # Criterion 3: BibTeX file exported and non-empty (25 pts)
    bib_size = result.get("bib_file_size", 0)
    bib_exists = result.get("bib_file_exists", False)
    entry_count = result.get("bib_entry_count", 0)
    if bib_exists and bib_size > 100 and entry_count > 0:
        score += 25
        subscores["bib_exported"] = True
        feedback_parts.append(f"BibTeX exported ({bib_size} bytes, {entry_count} entries)")
    elif bib_exists and bib_size > 0:
        score += 10
        subscores["bib_exported"] = "partial"
        feedback_parts.append(f"BibTeX file exists but small ({bib_size} bytes)")
    else:
        subscores["bib_exported"] = False
        feedback_parts.append("BibTeX file /home/ga/Desktop/references.bib not found or empty")

    # Criterion 4: No duplicate citekeys in BibTeX (15 pts)
    if bib_exists and not result.get("bib_has_duplicates", True):
        score += 15
        subscores["bib_no_duplicates"] = True
        feedback_parts.append("BibTeX has no duplicate citekeys")
    elif bib_exists:
        dup_keys = result.get("bib_duplicate_keys", [])
        subscores["bib_no_duplicates"] = False
        if dup_keys:
            feedback_parts.append(f"BibTeX has {len(dup_keys)} duplicate citekey(s)")
        else:
            feedback_parts.append("BibTeX duplicate status unknown")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
