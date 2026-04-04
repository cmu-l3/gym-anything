"""
Verifier for open_data_government_spending_research task.

Scoring breakdown (100 points total):
- Criterion 1: USASpending.gov visited substantively (20 pts)
- Criterion 2: CSV data file downloaded (15 pts)
- Criterion 3: Research notes file created and fresh (15 pts)
- Criterion 4: Notes has dollar amount, contractor names, URLs (30 pts)
- Criterion 5: Bookmark folder "Government Spending Research" with USASpending URLs (20 pts)

Pass threshold: 60/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_open_data_government_spending_research(traj, env_info, task_info):
    """
    Verify that the agent researched DOD spending on USASpending.gov and produced
    research notes with findings, CSV data, and bookmarks.
    """
    copy_from_env = env_info.get("copy_from_env")

    result_json_path = "/tmp/open_data_government_spending_research_result.json"

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(result_json_path, tmp_path)
    except Exception as e:
        logger.warning(f"Could not copy result file: {e}")
        return {
            "score": 0,
            "passed": False,
            "feedback": "Could not retrieve result file from environment.",
            "subscores": {},
        }

    try:
        with open(tmp_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not parse result JSON: {e}")
        return {
            "score": 0,
            "passed": False,
            "feedback": "Could not parse result JSON.",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    subscores = {}
    feedback_parts = []

    usaspending_visits = int(data.get("usaspending_visits", 0) or 0)
    notes_exists = bool(data.get("notes_exists", False))
    csv_downloaded = bool(data.get("csv_downloaded", False))

    # --- Gate check ---
    if usaspending_visits == 0 and not notes_exists and not csv_downloaded:
        return {
            "score": 0,
            "passed": False,
            "feedback": "No evidence of task completion: no USASpending.gov visits, no CSV download, no research notes.",
            "subscores": {
                "usaspending_visits": 0,
                "csv_download": 0,
                "notes_file": 0,
                "notes_content": 0,
                "bookmarks": 0,
            },
        }

    # --- Criterion 1: USASpending.gov visits (20 pts) ---
    usaspending_search_visits = int(data.get("usaspending_search_visits", 0) or 0)
    gov_data_visits = int(data.get("gov_data_visits", 0) or 0)

    visit_score = 0
    if usaspending_search_visits >= 5:
        # Deep engagement: used search/agency/recipient/award pages
        visit_score = 20
        feedback_parts.append(
            f"Deep USASpending.gov research: {usaspending_search_visits} search/agency/recipient pages (+20)"
        )
    elif usaspending_search_visits >= 2:
        visit_score = 15
        feedback_parts.append(
            f"Used USASpending.gov search/agency features ({usaspending_search_visits} pages) (+15)"
        )
    elif usaspending_visits >= 3:
        visit_score = 10
        feedback_parts.append(f"Visited USASpending.gov ({usaspending_visits} pages) (+10)")
    elif usaspending_visits >= 1:
        visit_score = 5
        feedback_parts.append(f"Visited USASpending.gov ({usaspending_visits} page(s)) (+5)")
    else:
        feedback_parts.append("USASpending.gov not visited after task start (+0)")

    # Bonus for cross-referencing additional gov data sources
    if gov_data_visits > usaspending_visits and gov_data_visits >= usaspending_visits + 2:
        bonus = min(5, 20 - visit_score)
        visit_score += bonus
        feedback_parts.append(f"Cross-referenced additional gov data sources (+{bonus})")

    visit_score = min(visit_score, 20)
    subscores["usaspending_visits"] = visit_score

    # --- Criterion 2: CSV download (15 pts) ---
    csv_count = int(data.get("csv_count", 0) or 0)
    csv_score = 0
    if csv_downloaded and csv_count >= 1:
        csv_score = 15
        feedback_parts.append(f"CSV spending data downloaded ({csv_count} file(s) >1KB) (+15)")
    else:
        feedback_parts.append(
            "No CSV file downloaded to ~/Downloads/ after task start "
            "(use USASpending.gov download feature) (+0)"
        )

    subscores["csv_download"] = csv_score

    # --- Criterion 3: Notes file (15 pts) ---
    notes_fresh = bool(data.get("notes_fresh", False))
    notes_size = int(data.get("notes_size", 0) or 0)

    notes_score = 0
    if notes_exists and notes_fresh and notes_size >= 200:
        notes_score = 15
        feedback_parts.append(f"Research notes file created ({notes_size} bytes) (+15)")
    elif notes_exists and notes_fresh and notes_size > 0:
        notes_score = 8
        feedback_parts.append(
            f"Research notes file created but very short ({notes_size} bytes, need ≥200) (+8)"
        )
    elif notes_exists and not notes_fresh:
        notes_score = 4
        feedback_parts.append("Research notes file exists but was not created during this task (+4)")
    else:
        feedback_parts.append("No dod_spending_research.txt found at ~/Documents/ (+0)")

    subscores["notes_file"] = notes_score

    # --- Criterion 4: Notes content quality (30 pts) ---
    has_dollar = bool(data.get("has_dollar_amount", False))
    has_contractors = bool(data.get("has_contractor_names", False))
    has_urls = bool(data.get("has_urls", False))
    has_substantial = bool(data.get("has_substantial_content", False))
    has_dod_content = bool(data.get("has_dod_content", False))
    url_count = int(data.get("url_count", 0) or 0)
    contractor_names = data.get("contractor_names_found", []) or []

    content_score = 0
    content_details = []

    # DOD-specific content (replaces generic dollar check - 8 pts: ensures right agency)
    # Dollar amount within DOD context (10 pts total: 8 for DOD mention + 2 for dollar)
    if has_dod_content and has_dollar:
        content_score += 10
        content_details.append("DOD spending amount present")
    elif has_dod_content:
        content_score += 5
        content_details.append("DOD reference present (add dollar amount)")
    elif has_dollar:
        content_score += 3
        content_details.append("spending amount present (must reference DOD/defense)")
    else:
        content_details.append("no DOD/defense content or dollar amount (research Department of Defense spending)")

    # Contractor names (10 pts)
    if has_contractors:
        content_score += 10
        if contractor_names:
            content_details.append(f"contractors: {', '.join(contractor_names[:3])}")
        else:
            content_details.append("contractor names present")
    else:
        content_details.append("no defense contractor names found")

    # URLs as sources (10 pts)
    if url_count >= 2:
        content_score += 10
        content_details.append(f"{url_count} source URLs")
    elif url_count == 1:
        content_score += 5
        content_details.append("1 source URL (need ≥2)")
    else:
        content_details.append("no source URLs found in notes")

    subscores["notes_content"] = content_score
    if content_score == 30:
        feedback_parts.append(f"Research notes have complete content: {'; '.join(content_details)} (+{content_score})")
    elif content_score > 0:
        feedback_parts.append(f"Partial notes content: {'; '.join(content_details)} (+{content_score})")
    else:
        feedback_parts.append(
            f"Notes content missing key elements: {'; '.join(content_details)} (+0)"
        )

    # --- Criterion 5: Bookmark folder (20 pts) ---
    spending_folder_exists = bool(data.get("spending_folder_exists", False))
    spending_bm_count = int(data.get("spending_folder_bookmark_count", 0) or 0)
    has_usaspending_urls = bool(data.get("spending_folder_has_usaspending_urls", False))

    bookmark_score = 0
    if spending_folder_exists and spending_bm_count >= 3 and has_usaspending_urls:
        bookmark_score = 20
        feedback_parts.append(
            f"'Government Spending Research' bookmark folder with {spending_bm_count} bookmarks "
            f"including USASpending.gov URLs (+20)"
        )
    elif spending_folder_exists and spending_bm_count >= 3:
        bookmark_score = 14
        feedback_parts.append(
            f"Bookmark folder exists with {spending_bm_count} bookmarks "
            f"(but few USASpending.gov URLs) (+14)"
        )
    elif spending_folder_exists and spending_bm_count >= 1:
        bookmark_score = 8
        feedback_parts.append(
            f"Bookmark folder 'Government Spending Research' exists with {spending_bm_count} bookmark(s) "
            f"(need ≥3) (+8)"
        )
    elif spending_folder_exists:
        bookmark_score = 4
        feedback_parts.append("Bookmark folder exists but is empty (+4)")
    else:
        feedback_parts.append(
            "No 'Government Spending Research' Firefox bookmark folder found (+0). "
            "Create a folder by that exact name and bookmark USASpending.gov pages into it."
        )

    subscores["bookmarks"] = bookmark_score

    # --- Total score ---
    total_score = sum(subscores.values())
    passed = total_score >= 60

    if passed:
        feedback_parts.insert(
            0,
            f"PASSED ({total_score}/100): Government spending research completed successfully.",
        )
    else:
        feedback_parts.insert(
            0,
            f"FAILED ({total_score}/100): Government spending research incomplete. "
            f"Key steps: (1) use USASpending.gov search/agency pages, (2) download CSV, "
            f"(3) write notes with dollar amounts + contractor names + 2 source URLs, "
            f"(4) bookmark ≥3 pages in 'Government Spending Research' folder.",
        )

    return {
        "score": total_score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
