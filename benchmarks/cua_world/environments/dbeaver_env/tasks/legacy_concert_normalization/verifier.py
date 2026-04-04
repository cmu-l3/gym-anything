#!/usr/bin/env python3
"""
Verifier for legacy_concert_normalization task.

Criteria:
1. Database Creation (10 pts): concert_bookings.db exists and is valid.
2. Connection (10 pts): DBeaver connection created with correct name.
3. Schema Structure (20 pts): Tables Venues, Artists, Concerts exist with reasonable columns.
4. Normalization Logic (40 pts):
   - Venues/Artists counts match distinct counts (no duplicates).
   - Concerts count matches total rows.
   - Reference integrity checks (reconstruction possible).
5. Cleanup (5 pts): No staging table remains.
6. Data Integrity (15 pts): Reconstructed data count matches original.

Pass Threshold: 75/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_concert_normalization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/final_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Database Creation (10 pts)
    if result.get("db_exists") and result.get("db_created_during_task"):
        score += 10
        feedback.append("Database file created successfully.")
    else:
        feedback.append("Database file not found or not created during task.")

    # 2. DBeaver Connection (10 pts)
    if result.get("connection_created"):
        score += 5
        feedback.append("DBeaver connection exists.")
        if result.get("connection_name_match"):
            score += 5
            feedback.append("Connection name 'ConcertBookings' matches.")
        else:
            feedback.append("Connection name incorrect (expected 'ConcertBookings').")
    else:
        feedback.append("DBeaver connection not found in config.")

    # 3. Schema Structure (20 pts)
    tables = [t.lower() for t in result.get("tables_found", [])]
    required_tables = {"venues", "artists", "concerts"}
    missing_tables = required_tables - set(tables)
    
    if not missing_tables:
        score += 20
        feedback.append("All required tables (Venues, Artists, Concerts) exist.")
        
        # Bonus check for columns (soft check)
        venues_cols = [c.lower() for c in result.get("venues_columns", [])]
        if "venuecity" in venues_cols or "city" in venues_cols:
            feedback.append("Venues table structure looks correct.")
    else:
        feedback.append(f"Missing tables: {', '.join(missing_tables)}")

    # 4. Normalization Logic (40 pts)
    gt_venues = result.get("gt_distinct_venues", 0)
    gt_artists = result.get("gt_distinct_artists", 0)
    gt_total = result.get("gt_total_rows", 0)

    actual_venues = result.get("venues_count", 0)
    actual_artists = result.get("artists_count", 0)
    actual_concerts = result.get("concerts_count", 0)

    # Venues normalization
    if actual_venues == gt_venues:
        score += 15
        feedback.append(f"Venues normalized correctly ({actual_venues}).")
    elif actual_venues > gt_venues:
        feedback.append(f"Venues table contains duplicates ({actual_venues} > {gt_venues}).")
    else:
        feedback.append(f"Venues table missing data ({actual_venues} < {gt_venues}).")

    # Artists normalization
    if actual_artists == gt_artists:
        score += 15
        feedback.append(f"Artists normalized correctly ({actual_artists}).")
    elif actual_artists > gt_artists:
        feedback.append(f"Artists table contains duplicates ({actual_artists} > {gt_artists}).")
    else:
        feedback.append(f"Artists table missing data ({actual_artists} < {gt_artists}).")

    # Concerts population
    if actual_concerts == gt_total:
        score += 10
        feedback.append(f"Concerts table populated correctly ({actual_concerts}).")
    else:
        feedback.append(f"Concerts table row count mismatch ({actual_concerts} vs {gt_total}).")

    # 5. Cleanup (5 pts)
    if not result.get("staging_table_exists"):
        score += 5
        feedback.append("Staging tables cleaned up.")
    else:
        feedback.append("Staging table (raw_import/csv) still exists.")

    # 6. Data Integrity / Reconstruction (15 pts)
    reconstructed = result.get("reconstructed_count", 0)
    if reconstructed == gt_total:
        score += 15
        feedback.append("Data integrity verified: Joins successfully reconstruct all rows.")
    elif reconstructed > 0:
        score += 5
        feedback.append(f"Partial data integrity: Reconstructed {reconstructed} of {gt_total} rows.")
    else:
        feedback.append("Data integrity failed: Could not join tables to reconstruct data.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }