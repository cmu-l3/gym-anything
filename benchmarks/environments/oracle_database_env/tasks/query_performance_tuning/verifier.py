"""
Verifier for query_performance_tuning task.

Scoring breakdown (100 pts total):
- Data integrity: AIRPORTS >= 14,000 rows and FLIGHT_ROUTES >= 67,000 rows (5 pts)
- Index creation: at least 4 NEW indexes created on AIRPORTS/FLIGHT_ROUTES (30 pts total)
  + 1st new index: 10 pts
  + 2nd new index: 8 pts
  + 3rd new index: 7 pts
  + 4th new index: 5 pts
- Index relevance: at least one index covers 'country' or 'altitude_ft' on AIRPORTS (10 pts)
- Index relevance: at least one index covers 'src_iata', 'dst_iata', or 'codeshare' on FLIGHT_ROUTES (10 pts)
- optimized_queries.sql exists on Desktop (10 pts)
- File contains at least 5 SQL statements (separated by semicolons) (15 pts)
- File references key indexed columns (country, src_iata, dst_iata, codeshare, altitude_ft) (10 pts)
- EXPLAIN PLAN shows index access (not full table scan) for country filter (10 pts — bonus)

Pass threshold: 55 pts
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_query_performance_tuning(traj, env_info, task_info):
    """
    Verifies query performance tuning task: index creation + optimized_queries.sql.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "score": 0.0,
            "passed": False,
            "feedback": "copy_from_env not available"
        }

    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "query_performance_tuning_result.json")
        try:
            copy_from_env("/tmp/query_performance_tuning_result.json", result_path)
        except Exception as e:
            return {
                "score": 0.0,
                "passed": False,
                "feedback": f"Could not retrieve result file: {e}"
            }

        if not os.path.exists(result_path):
            return {"score": 0.0, "passed": False, "feedback": "Result file not found after copy."}

        try:
            with open(result_path, "r") as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {"score": 0.0, "passed": False, "feedback": f"Result JSON malformed: {e}"}

    score = 0
    feedback_parts = []

    # --- Data sanity check (5 pts) ---
    airport_count = result.get("airport_count", 0)
    route_count = result.get("route_count", 0)
    if airport_count >= 14000 and route_count >= 67000:
        score += 5
        feedback_parts.append(f"Data intact: {airport_count} airports, {route_count} routes (+5)")
    else:
        feedback_parts.append(f"Data issue: {airport_count} airports, {route_count} routes (expected 14k+, 67k+)")

    # --- Index creation scoring (30 pts) ---
    new_index_count = result.get("new_index_count", 0)
    index_points = [10, 8, 7, 5]  # points for each new index
    total_index_pts = 0
    for i, pts in enumerate(index_points):
        if new_index_count > i:
            total_index_pts += pts
    score += total_index_pts
    feedback_parts.append(f"New indexes created: {new_index_count} (+{total_index_pts} pts)")

    # --- Index relevance on AIRPORTS (10 pts) ---
    index_columns = result.get("index_columns", {})
    airport_indexed_cols = set()
    route_indexed_cols = set()
    for idx_name, idx_info in index_columns.items():
        cols = {c.upper() for c in idx_info.get("columns", [])}
        if idx_info.get("table") == "AIRPORTS":
            airport_indexed_cols.update(cols)
        elif idx_info.get("table") == "FLIGHT_ROUTES":
            route_indexed_cols.update(cols)

    relevant_airport_cols = {"COUNTRY", "ALTITUDE_FT", "IATA_CODE", "AIRPORT_ID"}
    if airport_indexed_cols & relevant_airport_cols:
        score += 10
        matched = airport_indexed_cols & relevant_airport_cols
        feedback_parts.append(f"AIRPORTS index covers relevant column(s): {matched} (+10)")
    else:
        feedback_parts.append(f"AIRPORTS: no index on relevant columns (country/altitude_ft/iata_code) (0 pts)")

    # --- Index relevance on FLIGHT_ROUTES (10 pts) ---
    relevant_route_cols = {"SRC_IATA", "DST_IATA", "CODESHARE", "SRC_AIRPORT_ID", "DST_AIRPORT_ID"}
    if route_indexed_cols & relevant_route_cols:
        score += 10
        matched = route_indexed_cols & relevant_route_cols
        feedback_parts.append(f"FLIGHT_ROUTES index covers relevant column(s): {matched} (+10)")
    else:
        feedback_parts.append(f"FLIGHT_ROUTES: no index on relevant columns (src_iata/dst_iata/codeshare) (0 pts)")

    # --- optimized_queries.sql existence (10 pts) ---
    if result.get("optimized_queries_file_exists"):
        file_size = result.get("optimized_queries_file_size", 0)
        score += 10
        feedback_parts.append(f"optimized_queries.sql: exists ({file_size} bytes) (+10)")
    else:
        feedback_parts.append("optimized_queries.sql: NOT found at /home/ga/Desktop/ (0 pts)")

    # --- Query count in file (15 pts) ---
    query_count = result.get("query_count_in_file", 0)
    if query_count >= 5:
        score += 15
        feedback_parts.append(f"optimized_queries.sql: {query_count} statements found (>=5) (+15)")
    elif query_count >= 3:
        score += 8
        feedback_parts.append(f"optimized_queries.sql: only {query_count} statements (need 5) (+8 partial)")
    elif query_count >= 1:
        score += 3
        feedback_parts.append(f"optimized_queries.sql: only {query_count} statement(s) (+3 partial)")
    else:
        feedback_parts.append("optimized_queries.sql: no SQL statements found (0 pts)")

    # --- Content references key columns (10 pts) ---
    content = result.get("optimized_queries_content", "").upper()
    key_terms = ["COUNTRY", "SRC_IATA", "DST_IATA", "CODESHARE", "ALTITUDE_FT", "AIRPORTS", "FLIGHT_ROUTES"]
    found_terms = [t for t in key_terms if t in content]
    if len(found_terms) >= 4:
        score += 10
        feedback_parts.append(f"Content references key columns: {found_terms[:5]} (+10)")
    elif len(found_terms) >= 2:
        score += 4
        feedback_parts.append(f"Content references some key terms: {found_terms} (+4 partial)")
    else:
        feedback_parts.append(f"Content does not reference expected columns (0 pts)")

    # --- EXPLAIN PLAN bonus: index access detected (10 pts) ---
    plan = result.get("explain_plan_samples", {}).get("q1_country_filter", [])
    uses_index = any("INDEX" in str(row.get("op", "")).upper() for row in plan)
    if uses_index:
        score += 10
        feedback_parts.append("EXPLAIN PLAN: country filter uses index access (+10 bonus)")
    else:
        feedback_parts.append("EXPLAIN PLAN: country filter still using full table scan (0 bonus pts)")

    max_score = 100
    normalized = round(min(score, max_score) / max_score, 4)
    passed = score >= 55

    return {
        "score": normalized,
        "passed": passed,
        "raw_score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts)
    }
