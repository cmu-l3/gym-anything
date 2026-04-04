#!/usr/bin/env python3
"""
Verifier for northwind_territory_performance task.

Scoring (100 points):
- Northwind DBeaver connection exists (exact name): 15 pts
- territory_report.csv exists at correct path: 15 pts
- CSV has all required columns: 20 pts
- CSV row count between 40-60 territories: 15 pts
- Top territory revenue within 10% of ground truth: 20 pts
- SQL script saved at correct path: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_CSV_PATH = "/home/ga/Documents/exports/territory_report.csv"
EXPECTED_SQL_PATH = "/home/ga/Documents/scripts/territory_analysis.sql"
REQUIRED_COLUMNS = ["territoryid", "territorydescription", "regiondescription",
                    "totalrevenue", "ordercount", "avgordervalue", "employeecount"]


def verify_northwind_territory_performance(traj, env_info, task_info):
    """Verify territory performance analysis task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/northwind_territory_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: DBeaver 'Northwind' connection (15 pts) ---
    if result.get("northwind_conn_found"):
        score += 15
        subscores["northwind_connection"] = 15
        feedback.append("Northwind DBeaver connection found")
        conn_path = result.get("northwind_conn_path", "")
        if "northwind" not in conn_path.lower():
            feedback.append(f"Warning: connection path '{conn_path}' may not point to northwind.db")
    else:
        subscores["northwind_connection"] = 0
        feedback.append("MISSING: DBeaver 'Northwind' connection not found")

    # --- Criterion 2: CSV exists at exact path (15 pts) ---
    if result.get("csv_exists"):
        score += 15
        subscores["csv_exists"] = 15
        feedback.append(f"territory_report.csv exists")
        if not result.get("csv_created_after_start"):
            feedback.append("Warning: CSV may be pre-existing (timestamp check failed)")
            score -= 10
            subscores["csv_exists"] = 5
    else:
        subscores["csv_exists"] = 0
        feedback.append(f"MISSING: territory_report.csv not found at {EXPECTED_CSV_PATH}")

    # --- Criterion 3: CSV has all required columns (20 pts) ---
    has_terrid = result.get("csv_has_territory_id", False)
    has_revenue = result.get("csv_has_revenue", False)
    has_region = result.get("csv_has_region", False)
    col_count = result.get("csv_column_count", 0)

    if has_terrid and has_revenue and has_region and col_count >= 5:
        score += 20
        subscores["csv_columns"] = 20
        feedback.append(f"CSV has required columns ({col_count} columns total)")
    elif has_revenue and (has_terrid or has_region):
        score += 10
        subscores["csv_columns"] = 10
        feedback.append(f"CSV partially has required columns ({col_count} columns)")
    else:
        subscores["csv_columns"] = 0
        feedback.append(f"CSV missing required columns (found {col_count} columns)")

    # --- Criterion 4: Row count between 40-60 territories (15 pts) ---
    row_count = result.get("csv_row_count", 0)
    gt_count = result.get("gt_territory_count", 53)  # Northwind has ~53 territories

    if 40 <= row_count <= 60:
        score += 15
        subscores["row_count"] = 15
        feedback.append(f"Row count {row_count} is in expected range [40, 60]")
    elif 30 <= row_count <= 70:
        score += 7
        subscores["row_count"] = 7
        feedback.append(f"Row count {row_count} is close to expected range")
    else:
        subscores["row_count"] = 0
        feedback.append(f"Row count {row_count} outside expected territory range (expect 40-60)")

    # --- Criterion 5: Top territory revenue matches ground truth within 10% (20 pts) ---
    csv_top_revenue = result.get("csv_top_revenue", 0)
    gt_top_revenue = result.get("gt_top_revenue", 0)

    if csv_top_revenue > 0 and gt_top_revenue > 0:
        pct_diff = abs(csv_top_revenue - gt_top_revenue) / gt_top_revenue
        if pct_diff <= 0.10:
            score += 20
            subscores["revenue_accuracy"] = 20
            feedback.append(f"Top territory revenue ${csv_top_revenue:,.2f} matches GT ${gt_top_revenue:,.2f} "
                            f"(within {pct_diff*100:.1f}%)")
        elif pct_diff <= 0.25:
            score += 10
            subscores["revenue_accuracy"] = 10
            feedback.append(f"Top territory revenue ${csv_top_revenue:,.2f} is close to GT (diff {pct_diff*100:.1f}%)")
        else:
            subscores["revenue_accuracy"] = 0
            feedback.append(f"Revenue mismatch: CSV=${csv_top_revenue:,.2f}, GT=${gt_top_revenue:,.2f} "
                            f"(diff {pct_diff*100:.1f}%)")
    elif csv_top_revenue > 0 and gt_top_revenue == 0:
        # Ground truth unavailable — award partial credit if revenue is non-zero
        score += 10
        subscores["revenue_accuracy"] = 10
        feedback.append(f"Revenue present (${csv_top_revenue:,.2f}), GT unavailable")
    else:
        subscores["revenue_accuracy"] = 0
        feedback.append("Revenue data missing or zero in CSV")

    # --- Criterion 6: SQL script saved (15 pts) ---
    if result.get("sql_script_exists") and result.get("sql_script_size", 0) > 50:
        score += 15
        subscores["sql_script"] = 15
        feedback.append(f"SQL script saved at {EXPECTED_SQL_PATH}")
    elif result.get("dbeaver_sql_in_scripts"):
        score += 8
        subscores["sql_script"] = 8
        feedback.append("SQL found in DBeaver scripts folder (not at required path)")
    else:
        subscores["sql_script"] = 0
        feedback.append(f"SQL script not found at {EXPECTED_SQL_PATH}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "csv_row_count": result.get("csv_row_count", 0),
            "csv_top_revenue": result.get("csv_top_revenue", 0),
            "gt_top_revenue": result.get("gt_top_revenue", 0),
            "northwind_conn_found": result.get("northwind_conn_found", False)
        }
    }
