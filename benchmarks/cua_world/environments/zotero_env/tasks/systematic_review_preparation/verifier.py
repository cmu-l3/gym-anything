#!/usr/bin/env python3
"""
Verifier for systematic_review_preparation task.

Task: Prepare a 25-paper library for systematic review:
  1. Merge 3 duplicate pairs (25 -> 22 items)
  2. Trash 4 pre-2000 papers (22 -> 18 non-deleted)
  3. Tag 4 papers with placeholder abstracts as "incomplete-record",
     move to "Needs Manual Review" collection
  4. Standardize 2 abbreviated venue names
  5. Create "Included Studies" collection with ~14 screened-in papers,
     add "Screening Summary" standalone note, export as BibTeX

Scoring (100 points):
  - Duplicates merged (no duplicate titles, <=22 items): 15 pts
  - Pre-2000 papers trashed (4 specific titles): 15 pts
  - Incomplete papers tagged "incomplete-record": 15 pts
  - "Needs Manual Review" collection with 4 papers: 10 pts
  - Venue standardization (2 papers): 10 pts
  - "Included Studies" collection with ~14 papers: 15 pts
  - Standalone note "Screening Summary" in collection: 5 pts
  - BibTeX file exported with >=12 entries: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PRE2000_TITLES = [
    "A Quantitative Description of Membrane Current and its Application to Conduction and Excitation in Nerve",
    "Neural Networks and Physical Systems with Emergent Collective Computational Abilities",
    "Learning Representations by Back-propagating Errors",
    "Receptive Fields, Binocular Interaction and Functional Architecture in the Cat's Visual Cortex",
]

INCOMPLETE_TITLES = [
    "Performance-optimized hierarchical models predict neural responses in higher visual cortex",
    "Vector-based navigation using grid-like representations in artificial agents",
    "A Task-Optimized Neural Network Replicates Human Auditory Behavior, Predicts Brain Responses, and Reveals a Cortical Processing Hierarchy",
    "If deep learning is the answer, what is the question?",
]

DUPLICATE_TITLES = [
    "Neuroscience-Inspired Artificial Intelligence",
    "A deep learning framework for neuroscience",
    "Toward an Integration of Deep Learning and Neuroscience",
]

VENUE_FIXES = {
    "Recurrent neural networks as versatile tools of neuroscience research": "Current Opinion in Neurobiology",
    "Deep Neural Networks: A New Framework for Modeling Biological Vision and Brain Information Processing": "Annual Review of Vision Science",
}


def verify_systematic_review_preparation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/systematic_review_preparation_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: Duplicates merged (15 pts) ──────────────────────────
    dup_counts = result.get("duplicate_title_counts", {})
    all_merged = all(dup_counts.get(t, 2) <= 1 for t in DUPLICATE_TITLES)
    total_items = result.get("total_non_deleted_items", 25)
    if all_merged and total_items <= 22:
        score += 15
        subscores["duplicates_merged"] = True
        feedback_parts.append("All 3 duplicate pairs merged")
    else:
        merged_count = sum(1 for t in DUPLICATE_TITLES if dup_counts.get(t, 2) <= 1)
        pts = int(merged_count * 5)
        score += pts
        subscores["duplicates_merged"] = f"{merged_count}/3"
        feedback_parts.append(f"Duplicates merged: {merged_count}/3 (total items: {total_items})")

    # ── Criterion 2: Pre-2000 papers trashed (15 pts) ────────────────────
    trashed = set(result.get("trashed_titles", []))
    trashed_correct = sum(1 for t in PRE2000_TITLES if t in trashed)
    pts2 = int(trashed_correct * 3.75)
    score += pts2
    subscores["pre2000_trashed"] = f"{trashed_correct}/4"
    if trashed_correct == 4:
        feedback_parts.append("All 4 pre-2000 papers trashed")
    else:
        feedback_parts.append(f"Pre-2000 trashed: {trashed_correct}/4")

    # ── Criterion 3: Incomplete papers tagged (15 pts) ───────────────────
    tagged = set(result.get("incomplete_record_tagged_titles", []))
    tagged_correct = sum(1 for t in INCOMPLETE_TITLES if t in tagged)
    pts3 = int(tagged_correct * 3.75)
    score += pts3
    subscores["incomplete_tagged"] = f"{tagged_correct}/4"
    if tagged_correct == 4:
        feedback_parts.append("All 4 incomplete papers tagged 'incomplete-record'")
    else:
        feedback_parts.append(f"Incomplete tagged: {tagged_correct}/4")

    # ── Criterion 4: "Needs Manual Review" collection (10 pts) ───────────
    nmr = result.get("needs_manual_review_collection", {})
    if nmr.get("exists"):
        nmr_titles = set(nmr.get("titles", []))
        nmr_correct = sum(1 for t in INCOMPLETE_TITLES if t in nmr_titles)
        if nmr_correct >= 3:
            score += 10
            subscores["needs_manual_review"] = True
            feedback_parts.append(f"'Needs Manual Review' has {nmr_correct}/4 incomplete papers")
        else:
            score += int(nmr_correct * 2.5)
            subscores["needs_manual_review"] = f"{nmr_correct}/4"
            feedback_parts.append(f"'Needs Manual Review' has {nmr_correct}/4 incomplete papers")
    else:
        subscores["needs_manual_review"] = False
        feedback_parts.append("'Needs Manual Review' collection NOT found")

    # ── Criterion 5: Venue standardization (10 pts) ──────────────────────
    venues = result.get("venue_values", {})
    venue_correct = 0
    for title, expected in VENUE_FIXES.items():
        actual = venues.get(title, "")
        if actual and actual.strip() == expected:
            venue_correct += 1
    score += venue_correct * 5
    subscores["venues_fixed"] = f"{venue_correct}/2"
    if venue_correct == 2:
        feedback_parts.append("Both venue names standardized")
    else:
        feedback_parts.append(f"Venues fixed: {venue_correct}/2")

    # ── Criterion 6: "Included Studies" collection (15 pts) ──────────────
    inc = result.get("included_studies_collection", {})
    if inc.get("exists"):
        inc_count = inc.get("item_count", 0)
        if 12 <= inc_count <= 16:
            score += 15
            subscores["included_studies"] = inc_count
            feedback_parts.append(f"'Included Studies' has {inc_count} papers")
        elif inc_count >= 8:
            score += 8
            subscores["included_studies"] = inc_count
            feedback_parts.append(f"'Included Studies' has {inc_count} papers (expected ~14)")
        else:
            subscores["included_studies"] = inc_count
            feedback_parts.append(f"'Included Studies' has only {inc_count} papers (expected ~14)")
    else:
        subscores["included_studies"] = False
        feedback_parts.append("'Included Studies' collection NOT found")

    # ── Criterion 7: Screening Summary note (5 pts) ──────────────────────
    note = result.get("screening_summary_note", {})
    if note.get("exists"):
        score += 5
        subscores["screening_note"] = True
        feedback_parts.append("'Screening Summary' note found")
    else:
        subscores["screening_note"] = False
        feedback_parts.append("'Screening Summary' note NOT found")

    # ── Criterion 8: BibTeX export (15 pts) ──────────────────────────────
    if result.get("bib_file_exists") and result.get("bib_file_size", 0) > 100:
        entry_count = result.get("bib_entry_count", 0)
        if entry_count >= 12:
            score += 15
            subscores["bib_export"] = entry_count
            feedback_parts.append(f"BibTeX exported ({entry_count} entries)")
        elif entry_count >= 5:
            score += 8
            subscores["bib_export"] = entry_count
            feedback_parts.append(f"BibTeX exported but only {entry_count} entries (expected ~14)")
        else:
            score += 3
            subscores["bib_export"] = entry_count
            feedback_parts.append(f"BibTeX file exists but few entries ({entry_count})")
    else:
        subscores["bib_export"] = False
        feedback_parts.append("BibTeX file not found at /home/ga/Desktop/included_studies.bib")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
