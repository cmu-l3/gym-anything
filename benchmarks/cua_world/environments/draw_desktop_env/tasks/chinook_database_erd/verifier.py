#!/usr/bin/env python3
"""
Verifier for chinook_database_erd task.

Scoring (100 points total):
- File exists and was modified after task start: 10 pts
- 9+ of 11 tables represented as shapes: 25 pts  (partial: 5+ tables = 10 pts)
- 7+ FK relationship edges drawn: 20 pts           (partial: 3+ edges = 8 pts)
- 2+ diagram pages (ERD page + summary page): 15 pts
- PK/FK attribute keywords present in shapes: 10 pts
- Logical grouping (swimlanes/groups present): 10 pts
- PNG exported and valid: 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

REQUIRED_TABLES = [
    "artist", "album", "track", "mediatype", "genre",
    "playlist", "playlisttrack", "invoice", "invoiceline",
    "customer", "employee"
]


def verify_chinook_database_erd(traj, env_info, task_info):
    """Verify Chinook Physical ERD creation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    min_tables = metadata.get('min_tables', 9)
    min_edges = metadata.get('min_edges', 7)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: File exists and was modified after task start (10 pts) ---
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "ERD file ~/Desktop/chinook_erd.drawio not found. Nothing was saved.",
            "subscores": {}
        }
    if result.get('file_modified_after_start'):
        score += 10
        subscores["file_saved"] = True
        feedback.append("ERD file saved")
    else:
        subscores["file_saved"] = False
        feedback.append("WARN: File not modified after task start (may be stale)")

    file_size = result.get('file_size', 0)
    if file_size < 500:
        feedback.append(f"WARN: File suspiciously small ({file_size} bytes)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback),
            "subscores": subscores
        }

    # --- Criterion 2: Tables represented (25 pts full, 10 pts partial) ---
    tables_found = result.get('tables_found', 0)
    subscores["tables_found"] = tables_found
    if tables_found >= min_tables:
        score += 25
        feedback.append(f"Tables: {tables_found}/11 found (excellent)")
    elif tables_found >= 5:
        score += 10
        feedback.append(f"Tables: {tables_found}/11 found (partial)")
    elif tables_found >= 2:
        score += 4
        feedback.append(f"Tables: {tables_found}/11 found (insufficient)")
    else:
        feedback.append(f"Tables: only {tables_found}/11 tables identified in diagram")

    # --- Criterion 3: FK relationship edges (20 pts full, 8 pts partial) ---
    num_edges = result.get('num_edges', 0)
    subscores["num_edges"] = num_edges
    if num_edges >= min_edges:
        score += 20
        feedback.append(f"Edges: {num_edges} drawn (≥{min_edges} required)")
    elif num_edges >= 3:
        score += 8
        feedback.append(f"Edges: {num_edges} drawn (partial, need ≥{min_edges})")
    elif num_edges >= 1:
        score += 3
        feedback.append(f"Edges: only {num_edges} drawn")
    else:
        feedback.append("No relationship edges drawn")

    # --- Criterion 4: Multiple pages (15 pts) ---
    num_pages = result.get('num_pages', 0)
    subscores["num_pages"] = num_pages
    if num_pages >= 2:
        score += 15
        feedback.append(f"Pages: {num_pages} pages (multi-page diagram created)")
    else:
        feedback.append(f"Pages: only {num_pages} page (need ≥2 for full credit)")

    # --- Criterion 5: PK/FK keywords in shapes (10 pts) ---
    fk_count = result.get('fk_keywords_count', 0)
    subscores["fk_keywords"] = fk_count
    if fk_count >= 4:
        score += 10
        feedback.append(f"PK/FK notation: {fk_count} keywords found")
    elif fk_count >= 2:
        score += 5
        feedback.append(f"PK/FK notation: {fk_count} keywords (partial)")
    else:
        feedback.append(f"PK/FK notation: missing or incomplete ({fk_count})")

    # --- Criterion 6: Logical groups/swimlanes (10 pts) ---
    if result.get('has_groups'):
        score += 10
        subscores["has_groups"] = True
        feedback.append("Logical grouping: subject-area groups present")
    else:
        subscores["has_groups"] = False
        feedback.append("Logical grouping: no groups/swimlanes found (need ≥3 subject-area groups)")

    # --- Criterion 7: PNG exported (10 pts) ---
    png_exists = result.get('png_exists', False)
    png_valid = result.get('png_valid', False)
    png_size = result.get('png_size', 0)
    subscores["png_exported"] = png_exists and png_valid
    if png_exists and png_valid and png_size >= 2000:
        score += 10
        feedback.append(f"PNG exported: {png_size} bytes")
    elif png_exists and png_size >= 500:
        score += 5
        feedback.append(f"PNG exported but small: {png_size} bytes")
    else:
        feedback.append("PNG not exported (~/Desktop/chinook_erd.png missing or invalid)")

    passed = score >= 60
    if passed:
        feedback.append(f"PASSED (score={score}/100)")
    else:
        feedback.append(f"FAILED (score={score}/100, need ≥60)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }
