#!/usr/bin/env python3
"""
Verifier for docker_postgres_migration task.

Scoring (100 points):
  - chinook-pg15 container is running: 20 pts
  - chinook database accessible in PG15 (pg_isready passes): 15 pts
  - Artist + Employee + Customer row counts match PG13: 30 pts (10 each)
  - All 11 expected tables present in PG15: 20 pts (partial: >=6 = 10 pts)
  - Container was created after task start (not pre-existing): 15 pts

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65

EXPECTED_TABLES = {
    "Artist", "Album", "Track", "Customer", "Employee",
    "Invoice", "InvoiceLine", "Playlist", "PlaylistTrack",
    "MediaType", "Genre",
}


def verify_docker_postgres_migration(traj, env_info, task_info):
    """Verify PostgreSQL 13 → 15 migration results."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/docker_migration_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: PG15 container running (20 pts) ───────────────────────────
    pg15_running = result.get("pg15_running", 0)

    if pg15_running:
        score += 20
        subscores["pg15_running"] = True
        feedback_parts.append("chinook-pg15 container is running (+20)")
    else:
        subscores["pg15_running"] = False
        feedback_parts.append("chinook-pg15 container not found or not running (0/20)")

    # ── Criterion 2: Database accessible (15 pts) ──────────────────────────────
    pg15_accessible = result.get("pg15_db_accessible", 0)

    if pg15_accessible:
        score += 15
        subscores["pg15_accessible"] = True
        feedback_parts.append("chinook database accessible in PG15 (+15)")
    elif pg15_running:
        subscores["pg15_accessible"] = False
        feedback_parts.append("PG15 container running but chinook database not accessible (0/15)")
    else:
        subscores["pg15_accessible"] = False
        feedback_parts.append("PG15 container not running (0/15)")

    # ── Criterion 3: Row count fidelity (30 pts, 10 each) ─────────────────────
    artist_match = result.get("artist_count_match", 0)
    employee_match = result.get("employee_count_match", 0)
    customer_match = result.get("customer_count_match", 0)

    pg13_artist = result.get("pg13_artist_count", 0)
    pg15_artist = result.get("pg15_artist_count", 0)
    pg13_employee = result.get("pg13_employee_count", 0)
    pg15_employee = result.get("pg15_employee_count", 0)
    pg13_customer = result.get("pg13_customer_count", 0)
    pg15_customer = result.get("pg15_customer_count", 0)

    if artist_match and pg13_artist > 0:
        score += 10
        subscores["artist_count"] = True
        feedback_parts.append(f"Artist count matches: {pg15_artist} rows (+10)")
    elif pg15_artist > 0 and pg13_artist > 0:
        subscores["artist_count"] = False
        feedback_parts.append(
            f"Artist count mismatch: PG13={pg13_artist} PG15={pg15_artist} (0/10)"
        )
    else:
        subscores["artist_count"] = False
        feedback_parts.append(f"Artist table empty or inaccessible in PG15 (0/10)")

    if employee_match and pg13_employee > 0:
        score += 10
        subscores["employee_count"] = True
        feedback_parts.append(f"Employee count matches: {pg15_employee} rows (+10)")
    elif pg15_employee > 0 and pg13_employee > 0:
        subscores["employee_count"] = False
        feedback_parts.append(
            f"Employee count mismatch: PG13={pg13_employee} PG15={pg15_employee} (0/10)"
        )
    else:
        subscores["employee_count"] = False
        feedback_parts.append(f"Employee table empty or inaccessible in PG15 (0/10)")

    if customer_match and pg13_customer > 0:
        score += 10
        subscores["customer_count"] = True
        feedback_parts.append(f"Customer count matches: {pg15_customer} rows (+10)")
    elif pg15_customer > 0 and pg13_customer > 0:
        subscores["customer_count"] = False
        feedback_parts.append(
            f"Customer count mismatch: PG13={pg13_customer} PG15={pg15_customer} (0/10)"
        )
    else:
        subscores["customer_count"] = False
        feedback_parts.append(f"Customer table empty or inaccessible in PG15 (0/10)")

    # ── Criterion 4: Tables present (20 pts) ───────────────────────────────────
    tables_matched = result.get("expected_tables_matched", 0)
    pg15_table_count = result.get("pg15_table_count", 0)
    total_expected = len(EXPECTED_TABLES)

    if tables_matched >= total_expected:
        score += 20
        subscores["tables_present"] = True
        feedback_parts.append(f"All {total_expected} expected tables present in PG15 (+20)")
    elif tables_matched >= 6:
        score += 10
        subscores["tables_present"] = "partial"
        feedback_parts.append(
            f"{tables_matched}/{total_expected} expected tables present in PG15 (10/20)"
        )
    elif tables_matched > 0:
        score += 5
        subscores["tables_present"] = "partial"
        feedback_parts.append(
            f"{tables_matched}/{total_expected} expected tables present — migration incomplete (5/20)"
        )
    else:
        subscores["tables_present"] = False
        feedback_parts.append(f"No expected tables found in PG15 (0/20)")

    # ── Criterion 5: Container created after task start (15 pts) ───────────────
    pg15_created_after_start = result.get("pg15_created_after_start", 0)
    task_start = result.get("task_start", 0)
    pg15_created_at = result.get("pg15_created_at", 0)

    if pg15_running and pg15_created_after_start:
        score += 15
        subscores["created_after_start"] = True
        feedback_parts.append("PG15 container was created during this task session (+15)")
    elif pg15_running and not pg15_created_after_start:
        subscores["created_after_start"] = False
        feedback_parts.append(
            "PG15 container appears to have existed before task start — may be pre-seeded (0/15)"
        )
    else:
        subscores["created_after_start"] = False
        feedback_parts.append("PG15 container not running (0/15)")

    # ── GATE: Database must be accessible to pass ──────────────────────────────
    if not pg15_accessible and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(
            f"Score capped at {PASS_THRESHOLD - 1}: chinook database must be accessible in PG15 to pass"
        )

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "details": {
            "pg15_running": pg15_running,
            "pg15_accessible": pg15_accessible,
            "pg13_artist_count": pg13_artist,
            "pg15_artist_count": pg15_artist,
            "pg13_employee_count": pg13_employee,
            "pg15_employee_count": pg15_employee,
            "pg13_customer_count": pg13_customer,
            "pg15_customer_count": pg15_customer,
            "expected_tables_matched": tables_matched,
            "pg15_table_count": pg15_table_count,
            "pg15_created_after_start": pg15_created_after_start,
        },
    }
