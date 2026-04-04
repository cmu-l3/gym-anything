#!/usr/bin/env python3
"""Verifier for import_bibtex_library task."""

import json
import tempfile
import os

def verify_import_bibtex_library(traj, env_info, task_info):
    """Verify that BibTeX file was imported successfully into Zotero."""

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_min_items = metadata.get('expected_min_items', 9)
    expected_max_items = metadata.get('expected_max_items', 11)
    expected_authors = metadata.get('expected_authors', [])

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Evaluate results
    score = 0
    feedback_parts = []

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    items_added = result.get('items_added', 0)
    bibtex_imported = result.get('bibtex_imported', False)
    found_authors = result.get('found_authors', '')

    # Criterion 1: Items were added (20 points)
    if items_added > 0:
        score += 20
        feedback_parts.append(f"Items added: {items_added}")
    else:
        feedback_parts.append("No items were added")

    # Criterion 2: Correct number of items (30 points)
    if expected_min_items <= items_added <= expected_max_items:
        score += 30
        feedback_parts.append(f"Correct item count ({items_added} items)")
    elif items_added > 0:
        score += 15
        feedback_parts.append(f"Partial: {items_added} items (expected {expected_min_items}-{expected_max_items})")
    else:
        feedback_parts.append(f"Wrong item count: {items_added}")

    # Criterion 3: Expected authors found (30 points)
    authors_found = 0
    for author in expected_authors:
        if author in found_authors and f"{author}:0" not in found_authors:
            authors_found += 1

    if authors_found == len(expected_authors):
        score += 30
        feedback_parts.append(f"All expected authors found ({authors_found}/{len(expected_authors)})")
    elif authors_found > 0:
        author_score = int(30 * authors_found / len(expected_authors))
        score += author_score
        feedback_parts.append(f"Some authors found ({authors_found}/{len(expected_authors)})")
    else:
        feedback_parts.append("Expected authors not found")

    # Criterion 4: Import method verification (20 points)
    if bibtex_imported == "true" or str(bibtex_imported).lower() == "true":
        score += 20
        feedback_parts.append("BibTeX import confirmed")
    else:
        feedback_parts.append("BibTeX import not confirmed")

    # Task passes if score >= 60
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "items_added": items_added,
            "authors_found": authors_found,
            "bibtex_imported": bibtex_imported
        }
    }
