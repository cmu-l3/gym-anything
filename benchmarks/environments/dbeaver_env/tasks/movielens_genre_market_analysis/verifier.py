#!/usr/bin/env python3
"""
Verifier for movielens_genre_market_analysis task.

Scoring (100 points):
- DBeaver 'MovieLens' connection exists: 10 pts
- genre_analysis.csv exists with ~5 rows and correct columns: 20 pts
- Top genre in genre CSV matches ground truth: 20 pts
- hidden_gems.csv exists with ~10 rows and correct columns: 20 pts
- Hidden gems meet criteria (avg>=4.0, some validation): 15 pts
- SQL script saved: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

GENRE_CSV_PATH = "/home/ga/Documents/exports/genre_analysis.csv"
GEMS_CSV_PATH = "/home/ga/Documents/exports/hidden_gems.csv"
SQL_PATH = "/home/ga/Documents/scripts/market_analysis.sql"


def verify_movielens_genre_market_analysis(traj, env_info, task_info):
    """Verify MovieLens genre market analysis task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/movielens_market_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: DBeaver 'MovieLens' connection (10 pts) ---
    if result.get("movielens_conn_found"):
        score += 10
        subscores["connection"] = 10
        feedback.append("'MovieLens' DBeaver connection found")
    else:
        subscores["connection"] = 0
        feedback.append("MISSING: DBeaver 'MovieLens' connection not found")

    # --- Criterion 2: genre_analysis.csv exists with correct structure (20 pts) ---
    if result.get("genre_csv_exists"):
        genre_rows = result.get("genre_row_count", 0)
        has_genre = result.get("genre_has_genre_col", False)
        has_rating = result.get("genre_has_avg_rating", False)

        if 4 <= genre_rows <= 7 and has_genre and has_rating:
            score += 20
            subscores["genre_csv"] = 20
            feedback.append(f"genre_analysis.csv has {genre_rows} rows with correct columns")
        elif genre_rows >= 3 and (has_genre or has_rating):
            score += 12
            subscores["genre_csv"] = 12
            feedback.append(f"genre_analysis.csv exists with {genre_rows} rows (partial structure)")
        elif genre_rows >= 1:
            score += 6
            subscores["genre_csv"] = 6
            feedback.append(f"genre_analysis.csv exists but structure issues ({genre_rows} rows)")
        else:
            score += 3
            subscores["genre_csv"] = 3
            feedback.append("genre_analysis.csv exists but is empty")

        if not result.get("genre_csv_new"):
            feedback.append("Warning: genre CSV may be pre-existing")
    else:
        subscores["genre_csv"] = 0
        feedback.append(f"MISSING: genre_analysis.csv not found at {GENRE_CSV_PATH}")

    # --- Criterion 3: Top genre matches ground truth (20 pts) ---
    csv_top_genre = (result.get("genre_top_genre") or "").lower().strip()
    gt_top_genre = (result.get("gt_top_genre") or "").lower().strip()
    csv_top_avg = result.get("genre_top_avg", 0)
    gt_top_avg = result.get("gt_top_avg", 0)

    if csv_top_genre and gt_top_genre:
        if csv_top_genre == gt_top_genre:
            score += 20
            subscores["genre_accuracy"] = 20
            feedback.append(f"Top genre '{csv_top_genre}' matches ground truth")
        elif csv_top_avg > 0 and gt_top_avg > 0:
            # Check if the average rating is close (within 5%)
            pct_diff = abs(csv_top_avg - gt_top_avg) / gt_top_avg if gt_top_avg > 0 else 1
            if pct_diff <= 0.05:
                score += 15
                subscores["genre_accuracy"] = 15
                feedback.append(f"Top genre avg rating close to GT ('{csv_top_genre}' vs '{gt_top_genre}')")
            else:
                score += 5
                subscores["genre_accuracy"] = 5
                feedback.append(f"Top genre mismatch: got '{csv_top_genre}', expected '{gt_top_genre}'")
        else:
            score += 5
            subscores["genre_accuracy"] = 5
            feedback.append(f"Genre data present but accuracy check failed")
    elif result.get("genre_csv_exists") and csv_top_genre:
        score += 8
        subscores["genre_accuracy"] = 8
        feedback.append(f"Genre data present ('{csv_top_genre}') but GT not available for comparison")
    else:
        subscores["genre_accuracy"] = 0
        feedback.append("Genre accuracy check failed — no data")

    # --- Criterion 4: hidden_gems.csv exists with correct structure (20 pts) ---
    if result.get("gems_csv_exists"):
        gems_rows = result.get("gems_row_count", 0)
        has_movieid = result.get("gems_has_movieid", False)
        has_title = result.get("gems_has_title", False)
        has_rating = result.get("gems_has_rating", False)

        if 8 <= gems_rows <= 15 and has_movieid and has_title and has_rating:
            score += 20
            subscores["gems_csv"] = 20
            feedback.append(f"hidden_gems.csv has {gems_rows} rows with all required columns")
        elif gems_rows >= 5 and (has_movieid or has_title):
            score += 12
            subscores["gems_csv"] = 12
            feedback.append(f"hidden_gems.csv exists with {gems_rows} rows (partial structure)")
        elif gems_rows >= 1:
            score += 6
            subscores["gems_csv"] = 6
            feedback.append(f"hidden_gems.csv exists ({gems_rows} rows)")
        else:
            score += 3
            subscores["gems_csv"] = 3
            feedback.append("hidden_gems.csv exists but is empty")

        if not result.get("gems_csv_new"):
            feedback.append("Warning: gems CSV may be pre-existing")
    else:
        subscores["gems_csv"] = 0
        feedback.append(f"MISSING: hidden_gems.csv not found at {GEMS_CSV_PATH}")

    # --- Criterion 5: Hidden gems meet criteria (15 pts) ---
    gems_avg = result.get("gems_avg_rating", 0)
    gems_rows = result.get("gems_row_count", 0)

    if gems_avg >= 3.9 and gems_rows >= 5:
        # Average rating of gems should be well above 4.0
        score += 15
        subscores["gems_quality"] = 15
        feedback.append(f"Hidden gems avg rating {gems_avg:.2f} meets quality threshold")
    elif gems_avg >= 3.5 and gems_rows >= 3:
        score += 8
        subscores["gems_quality"] = 8
        feedback.append(f"Hidden gems avg rating {gems_avg:.2f} (slightly below expected >=4.0)")
    elif gems_avg > 0:
        score += 4
        subscores["gems_quality"] = 4
        feedback.append(f"Hidden gems present but avg rating {gems_avg:.2f} below threshold")
    else:
        subscores["gems_quality"] = 0
        if result.get("gems_csv_exists"):
            feedback.append("Hidden gems CSV exists but quality criteria not validated")
        else:
            feedback.append("Hidden gems quality check failed — no CSV")

    # --- Criterion 6: SQL script saved (15 pts) ---
    if result.get("sql_script_exists") and result.get("sql_script_size", 0) > 50:
        score += 15
        subscores["sql_script"] = 15
        feedback.append(f"SQL script saved at {SQL_PATH}")
    elif result.get("dbeaver_sql_exists"):
        score += 8
        subscores["sql_script"] = 8
        feedback.append("SQL found in DBeaver scripts folder (not at required path)")
    else:
        subscores["sql_script"] = 0
        feedback.append(f"SQL script not found at {SQL_PATH}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "genre_rows": result.get("genre_row_count"),
            "gems_rows": result.get("gems_row_count"),
            "top_genre": result.get("genre_top_genre"),
            "gt_top_genre": result.get("gt_top_genre"),
            "gems_avg_rating": result.get("gems_avg_rating")
        }
    }
