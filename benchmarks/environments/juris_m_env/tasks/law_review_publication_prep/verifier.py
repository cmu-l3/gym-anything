#!/usr/bin/env python3
"""
Verifier for law_review_publication_prep task.

Scoring (100 points, pass threshold = 60):

1. Collection hierarchy (20 pts):
   - parent_collection_exists:                5 pts
   - data_privacy_subcollection_exists:       5 pts
   - digital_search_subcollection_exists:     5 pts
   - surveillance_law_subcollection_exists:   5 pts

2. All 15 items assigned to subcollections (20 pts):
   - total_assigned_items >= 12: 20 pts
   - total_assigned_items >=  8: 10 pts
   - total_assigned_items >=  4:  5 pts

3. Missing abstracts added (15 pts):
   - Count how many of the 4 no-abstract articles now appear in items_with_abstract
     (using fuzzy title match on first significant word).
   - >= 3 added: 15 pts
   - >= 2 added: 10 pts
   - >= 1 added:  5 pts

4. Table of Contents note (15 pts):
   - standalone_notes has >= 1 entry with note_length >= 200 AND
     (title contains 'table' or 'contents' (case-insensitive) OR note_length >= 500): 15 pts
   - standalone_notes non-empty:  7 pts

5. Citation style set to Chicago (10 pts):
   - quick_copy_style contains "chicago" (case-insensitive): 10 pts

6. 'tech-privacy-2024' tag (10 pts):
   - total_items_with_tag >= 12: 10 pts
   - total_items_with_tag >=  8:  5 pts

7. Classification roughly correct (10 pts):
   - Law review articles must NOT be in Digital Search Cases subcollection.
   - If no article title (fuzzy-matched) appears in digital_search_items: 10 pts
   - Article titles to check (partial, case-insensitive):
     ["taxonomy", "lex informatica", "broken promises", "big data ethics",
      "history of online gatekeeping", "fourth amendment and new technologies",
      "pii problem", "privacy on the books"]
"""

import os
import json
import logging
import tempfile
from typing import Any, Dict, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Articles that started WITHOUT an abstract
NO_ABSTRACT_TITLES = [
    "A Taxonomy of Privacy",
    "Lex Informatica: The Formulation of Information Policy Rules Through Technology",
    "Broken Promises of Privacy: Responding to the Surprising Failure of Anonymization",
    "Big Data Ethics",
]

# Short keyword slugs for fuzzy matching (all lowercase)
NO_ABSTRACT_SLUGS = [
    "taxonomy",
    "lex informatica",
    "broken promises",
    "big data ethics",
]

# Article slugs used for classification check (should NOT appear in Digital Search Cases)
ALL_ARTICLE_SLUGS = [
    "taxonomy",
    "lex informatica",
    "broken promises",
    "big data ethics",
    "history of online gatekeeping",
    "fourth amendment and new technologies",
    "pii problem",
    "privacy on the books",
]


def _fuzzy_match(target_slug: str, candidate: str) -> bool:
    """Return True if target_slug appears as a substring of candidate (case-insensitive)."""
    return target_slug.lower() in candidate.lower()


def _count_no_abstract_now_filled(items_with_abstract: List[str]) -> int:
    """
    Count how many of the 4 originally-no-abstract articles now have an abstract.
    Uses fuzzy slug matching against each item's display name.
    """
    filled = 0
    for slug in NO_ABSTRACT_SLUGS:
        for name in items_with_abstract:
            if _fuzzy_match(slug, name):
                filled += 1
                break
    return filled


def _count_articles_in_digital_search(digital_search_items: List[str]) -> int:
    """
    Count how many law review article titles appear in the Digital Search Cases subcollection.
    Articles should NOT be placed there.
    """
    misclassified = 0
    for slug in ALL_ARTICLE_SLUGS:
        for name in digital_search_items:
            if _fuzzy_match(slug, name):
                misclassified += 1
                break
    return misclassified


def verify_law_review_publication_prep(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify the law_review_publication_prep task.

    Retrieves /tmp/law_review_publication_prep_result.json from the VM,
    then scores each sub-task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available in env_info",
        }

    # Retrieve result JSON from the VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/law_review_publication_prep_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        logger.error("Failed to retrieve result: %s", e)
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Could not retrieve export result: {e}. "
                "Ensure the task was completed and export_result.sh ran successfully."
            ),
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback: List[str] = []

    # ------------------------------------------------------------------
    # 1. Collection hierarchy (20 pts)
    # ------------------------------------------------------------------
    hier_score = 0
    parent_exists = result.get("parent_collection_exists", False)
    dp_exists = result.get("data_privacy_subcollection_exists", False)
    ds_exists = result.get("digital_search_subcollection_exists", False)
    sl_exists = result.get("surveillance_law_subcollection_exists", False)

    if parent_exists:
        hier_score += 5
        feedback.append("Parent collection 'Tech & Privacy Special Issue' exists (+5)")
    else:
        feedback.append(
            "MISSING parent collection 'Tech & Privacy Special Issue'. "
            "Right-click 'My Library' > New Collection."
        )

    if dp_exists:
        hier_score += 5
        feedback.append("Subcollection 'Data Privacy Articles' exists (+5)")
    else:
        feedback.append("MISSING subcollection 'Data Privacy Articles'")

    if ds_exists:
        hier_score += 5
        feedback.append("Subcollection 'Digital Search Cases' exists (+5)")
    else:
        feedback.append("MISSING subcollection 'Digital Search Cases'")

    if sl_exists:
        hier_score += 5
        feedback.append("Subcollection 'Surveillance Law' exists (+5)")
    else:
        feedback.append("MISSING subcollection 'Surveillance Law'")

    score += hier_score
    logger.info("Hierarchy score: %d/20", hier_score)

    # ------------------------------------------------------------------
    # 2. Items assigned to subcollections (20 pts)
    # ------------------------------------------------------------------
    total_assigned = result.get("total_assigned_items", 0)
    if total_assigned >= 12:
        assign_score = 20
        feedback.append(f"{total_assigned} items assigned to subcollections (+20)")
    elif total_assigned >= 8:
        assign_score = 10
        feedback.append(f"{total_assigned} items assigned (need 12 for full credit) (+10)")
    elif total_assigned >= 4:
        assign_score = 5
        feedback.append(f"{total_assigned} items assigned (need 12 for full credit) (+5)")
    else:
        assign_score = 0
        feedback.append(
            f"Only {total_assigned} items assigned to subcollections. "
            "Drag items from My Library into each subcollection."
        )
    score += assign_score
    logger.info("Assignment score: %d/20 (assigned=%d)", assign_score, total_assigned)

    # ------------------------------------------------------------------
    # 3. Missing abstracts added (15 pts)
    # ------------------------------------------------------------------
    items_with_abstract = result.get("items_with_abstract", [])
    filled_count = _count_no_abstract_now_filled(items_with_abstract)
    if filled_count >= 3:
        abstract_score = 15
        feedback.append(f"{filled_count}/4 missing abstracts now filled (+15)")
    elif filled_count >= 2:
        abstract_score = 10
        feedback.append(f"{filled_count}/4 missing abstracts filled (+10)")
    elif filled_count >= 1:
        abstract_score = 5
        feedback.append(f"{filled_count}/4 missing abstracts filled (+5)")
    else:
        abstract_score = 0
        feedback.append(
            "No missing abstracts filled. Click on each article, then edit the "
            "Abstract field in the right panel. Articles needing abstracts: "
            "A Taxonomy of Privacy, Lex Informatica, Broken Promises of Privacy, Big Data Ethics."
        )
    score += abstract_score
    logger.info("Abstract score: %d/15 (filled=%d)", abstract_score, filled_count)

    # ------------------------------------------------------------------
    # 4. Table of Contents standalone note (15 pts)
    # ------------------------------------------------------------------
    standalone_notes = result.get("standalone_notes", [])
    toc_score = 0
    if standalone_notes:
        # Look for a note that plausibly is a ToC
        best_note = max(standalone_notes, key=lambda n: n.get("note_length", 0))
        note_len = best_note.get("note_length", 0)
        note_title = (best_note.get("title") or "").lower()
        is_toc_title = "table" in note_title or "contents" in note_title or "toc" in note_title
        if note_len >= 200 and (is_toc_title or note_len >= 500):
            toc_score = 15
            feedback.append(
                f"Standalone 'Table of Contents' note found "
                f"(length={note_len}, title='{best_note.get('title', '')}') (+15)"
            )
        else:
            toc_score = 7
            feedback.append(
                f"Standalone note found but may not be a full Table of Contents "
                f"(length={note_len}, title='{best_note.get('title', '')}') (+7). "
                "Note should be titled 'Table of Contents' and list all 15 items."
            )
    else:
        toc_score = 0
        feedback.append(
            "No standalone note found. In Juris-M, go to File > New Note (standalone) "
            "and create a 'Table of Contents' note listing all 15 items."
        )
    score += toc_score
    logger.info("ToC score: %d/15 (notes=%d)", toc_score, len(standalone_notes))

    # ------------------------------------------------------------------
    # 5. Citation style set to Chicago (10 pts)
    # ------------------------------------------------------------------
    quick_copy_style = result.get("quick_copy_style", "")
    if "chicago" in quick_copy_style.lower():
        cite_score = 10
        feedback.append(f"Chicago citation style set: '{quick_copy_style}' (+10)")
    else:
        cite_score = 0
        feedback.append(
            f"Chicago citation style NOT set (found: '{quick_copy_style}'). "
            "Go to Jurism Preferences > Export > Quick Copy and select "
            "'Chicago Manual of Style 17th edition (full note)'."
        )
    score += cite_score
    logger.info("Citation style score: %d/10 (style=%r)", cite_score, quick_copy_style)

    # ------------------------------------------------------------------
    # 6. 'tech-privacy-2024' tag on all items (10 pts)
    # ------------------------------------------------------------------
    total_tagged = result.get("total_items_with_tag", 0)
    if total_tagged >= 12:
        tag_score = 10
        feedback.append(f"{total_tagged} items tagged 'tech-privacy-2024' (+10)")
    elif total_tagged >= 8:
        tag_score = 5
        feedback.append(
            f"{total_tagged} items tagged 'tech-privacy-2024' (need 12 for full credit) (+5)"
        )
    else:
        tag_score = 0
        feedback.append(
            f"Only {total_tagged} items tagged 'tech-privacy-2024'. "
            "Select all items, right-click > Add Tag, type 'tech-privacy-2024'."
        )
    score += tag_score
    logger.info("Tag score: %d/10 (tagged=%d)", tag_score, total_tagged)

    # ------------------------------------------------------------------
    # 7. Classification roughly correct (10 pts)
    # Only award when the agent has actually assigned items to the Digital Search
    # Cases subcollection; an empty subcollection just means the work hasn't been
    # done yet and should not be rewarded.
    # ------------------------------------------------------------------
    digital_search_items = result.get("digital_search_items", [])
    misclassified_articles = _count_articles_in_digital_search(digital_search_items)
    if not result.get("digital_search_subcollection_exists", False):
        class_score = 0
        feedback.append("'Digital Search Cases' subcollection not created yet — classification not checked (0)")
    elif misclassified_articles == 0:
        class_score = 10
        feedback.append("Classification correct — no law review articles in Digital Search Cases (+10)")
    else:
        class_score = 0
        feedback.append(
            f"{misclassified_articles} law review article(s) incorrectly placed in "
            "'Digital Search Cases'. That subcollection is for court cases only."
        )
    score += class_score
    logger.info("Classification score: %d/10 (misclassified=%d)", class_score, misclassified_articles)

    # ------------------------------------------------------------------
    # Final result
    # ------------------------------------------------------------------
    score = min(score, 100)
    passed = score >= 60

    logger.info("Total score: %d/100, passed=%s", score, passed)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "score_breakdown": {
                "collection_hierarchy": hier_score,
                "items_assigned": assign_score,
                "abstracts_filled": abstract_score,
                "toc_note": toc_score,
                "citation_style": cite_score,
                "tagging": tag_score,
                "classification": class_score,
            },
            "raw_result": result,
        },
    }
