#!/usr/bin/env python3
"""
Verifier for export_collection_bibtex task.

Task: Export the 'ML References' collection as BibTeX to
      /home/ga/Desktop/ml_bibliography.bib

Scoring (100 points):
  - File exists at expected path:          30 pts
  - File contains valid BibTeX entries:    20 pts
  - Authors found (5 pts each, max 30):    30 pts
  - File is non-trivially sized (>1500 B): 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_AUTHORS = ["Vaswani", "Devlin", "Brown", "Krizhevsky", "He", "Goodfellow", "LeCun", "Silver"]


def verify_export_collection_bibtex(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/export_collection_bibtex_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: File exists (30 pts)
    if result.get("file_exists"):
        score += 30
        subscores["file_exists"] = True
        path = result.get("file_path_used", "")
        feedback_parts.append(f"BibTeX file created at {path}")
    else:
        subscores["file_exists"] = False
        desktop_files = result.get("desktop_files", [])
        feedback_parts.append(
            f"No BibTeX file found. Desktop files: {desktop_files[:5]}"
        )
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    # Criterion 2: Valid BibTeX entries (20 pts)
    entry_count = result.get("bibtex_entry_count", 0)
    if result.get("has_bibtex_entries") and entry_count >= 1:
        score += 20
        subscores["has_bibtex_entries"] = True
        feedback_parts.append(f"Valid BibTeX: {entry_count} entries")
    else:
        subscores["has_bibtex_entries"] = False
        feedback_parts.append("File has no valid @-style BibTeX entries")

    # Criterion 3: Authors found (5 pts each, max 30)
    found_authors = result.get("found_authors", [])
    author_pts = min(len(found_authors) * 5, 30)
    score += author_pts
    subscores["authors_found"] = len(found_authors)
    if found_authors:
        feedback_parts.append(f"Authors found ({len(found_authors)}/8): {found_authors}")
    missing = result.get("missing_authors", [])
    if missing:
        feedback_parts.append(f"Missing authors: {missing}")

    # Criterion 4: File size (20 pts)
    size = result.get("file_size_bytes", 0)
    if size >= 1500:
        score += 20
        subscores["adequate_size"] = True
        feedback_parts.append(f"File size: {size} bytes (adequate)")
    elif size >= 500:
        score += 10
        subscores["adequate_size"] = "partial"
        feedback_parts.append(f"File size: {size} bytes (partial credit)")
    else:
        subscores["adequate_size"] = False
        feedback_parts.append(f"File too small: {size} bytes")

    passed = score >= 60 and result.get("file_exists") and result.get("has_bibtex_entries")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
