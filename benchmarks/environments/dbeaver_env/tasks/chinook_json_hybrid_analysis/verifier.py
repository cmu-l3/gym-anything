#!/usr/bin/env python3
"""
Verifier for Chinook JSON Hybrid Analysis Task.

Verification Strategy:
1. Copy the SQLite database file (`chinook.db`) from the environment.
2. Inspect the DB locally using Python's sqlite3:
   - Check if `TrackFeatures` table exists and has data.
   - Check if `v_TrackExtended` view exists.
   - Execute a query against the view to verify JSON extraction works (BPM, Key, Danceability).
3. Copy the exported CSV file (`high_energy_tracks.csv`).
4. Validate CSV content against the criteria (BPM > 130, Dance > 0.7).
5. Check for SQL script existence.
"""

import json
import sqlite3
import pandas as pd
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_json_hybrid_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Files to retrieve
    db_remote_path = "/home/ga/Documents/databases/chinook.db"
    csv_remote_path = "/home/ga/Documents/exports/high_energy_tracks.csv"
    sql_remote_path = "/home/ga/Documents/scripts/json_analysis.sql"
    result_json_path = "/tmp/task_result.json"

    # Temporary local files
    temp_dir = tempfile.mkdtemp()
    db_local_path = os.path.join(temp_dir, "chinook.db")
    csv_local_path = os.path.join(temp_dir, "output.csv")
    result_local_path = os.path.join(temp_dir, "result.json")

    try:
        # 1. Read Task Result Metadata
        try:
            copy_from_env(result_json_path, result_local_path)
            with open(result_local_path, 'r') as f:
                task_result = json.load(f)
        except Exception:
            task_result = {}
            feedback.append("Warning: Could not read task result metadata.")

        # 2. Verify Database State (50 points)
        # We copy the DB to check schema and data integrity
        try:
            copy_from_env(db_remote_path, db_local_path)
            conn = sqlite3.connect(db_local_path)
            cursor = conn.cursor()

            # Check Table Creation (10 pts)
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='TrackFeatures'")
            if cursor.fetchone():
                score += 10
                feedback.append("Table `TrackFeatures` created successfully.")
                
                # Check Data Import (15 pts)
                cursor.execute("SELECT COUNT(*) FROM TrackFeatures")
                count = cursor.fetchone()[0]
                if count >= 90:  # Allow small margin of error (generated 100)
                    score += 15
                    feedback.append(f"Data import verified ({count} rows).")
                else:
                    feedback.append(f"Table `TrackFeatures` is empty or missing data (found {count} rows).")
            else:
                feedback.append("Table `TrackFeatures` NOT found.")

            # Check View Creation and Logic (25 pts)
            cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='view' AND name='v_TrackExtended'")
            view_row = cursor.fetchone()
            if view_row:
                score += 10
                feedback.append("View `v_TrackExtended` exists.")
                
                # Validate View Logic (JSON Extraction)
                # We try to select the specific columns. If json_extract wasn't used correctly, this might fail or return NULLs.
                try:
                    # Check for non-null values in extracted columns
                    cursor.execute("""
                        SELECT COUNT(*) FROM v_TrackExtended 
                        WHERE BPM IS NOT NULL AND Danceability IS NOT NULL
                    """)
                    valid_rows = cursor.fetchone()[0]
                    
                    if valid_rows > 0:
                        score += 15
                        feedback.append(f"View extraction logic works ({valid_rows} valid rows).")
                    else:
                        feedback.append("View exists but returns NULL for extracted JSON fields (Check JSON path syntax).")
                except Exception as e:
                    feedback.append(f"Error querying view: {e}")
            else:
                feedback.append("View `v_TrackExtended` NOT found.")
                
            conn.close()

        except Exception as e:
            feedback.append(f"Database verification failed: {e}")

        # 3. Verify Export File (40 points)
        if task_result.get("export_exists"):
            try:
                copy_from_env(csv_remote_path, csv_local_path)
                
                # Check if file is valid CSV and has content
                df = pd.read_csv(csv_local_path)
                
                if not df.empty:
                    # Check columns (approximate match)
                    cols = [c.lower() for c in df.columns]
                    if any('bpm' in c for c in cols) and any('dance' in c for c in cols) and any('name' in c for c in cols):
                        score += 10
                        feedback.append("Export CSV has correct columns.")
                        
                        # Check Filter Logic (BPM > 130 and Dance > 0.7)
                        # We find the specific column names to be safe
                        bpm_col = next(c for c in df.columns if 'bpm' in c.lower())
                        dance_col = next(c for c in df.columns if 'dance' in c.lower())
                        
                        # Validate data
                        # Note: CSV import might read as strings, convert to numeric
                        bpm_numeric = pd.to_numeric(df[bpm_col], errors='coerce')
                        dance_numeric = pd.to_numeric(df[dance_col], errors='coerce')
                        
                        # Check for violations
                        violations = df[ (bpm_numeric <= 130) | (dance_numeric <= 0.7) ]
                        
                        if len(violations) == 0 and len(df) > 0:
                            score += 30
                            feedback.append(f"Export data correctly filtered ({len(df)} rows).")
                        elif len(df) == 0:
                             feedback.append("Export file is empty.")
                        else:
                            score += 10 # Partial credit for format
                            feedback.append(f"Export data contains {len(violations)} rows that do not meet criteria (BPM>130, Dance>0.7).")
                    else:
                        feedback.append(f"Export CSV missing required columns. Found: {df.columns.tolist()}")
                else:
                    feedback.append("Export CSV is empty.")
                    
            except Exception as e:
                feedback.append(f"Failed to analyze CSV: {e}")
        else:
            feedback.append("Export file `high_energy_tracks.csv` NOT found.")

        # 4. Check SQL Script (10 points)
        if task_result.get("sql_exists"):
            score += 10
            feedback.append("SQL script file saved.")
        else:
            feedback.append("SQL script file missing.")

    finally:
        # Cleanup
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }