#!/usr/bin/env python3
"""
Verifier for imdb_genre_trends task.

Scoring (100 points total):
1. File Saved (10 pts): IMDB_Analysis.pbix exists.
2. CSV Evidence Exists (15 pts): genre_stats.csv exists.
3. Genre Split (30 pts): Primary_Genre column in CSV does NOT contain '|'.
4. Decade Binning (20 pts): Column headers in CSV look like decades (ends in 0).
5. Matrix Visual (15 pts): 'pivotTable' visual type found in PBIX.
6. Scatter Visual (10 pts): 'scatterChart' visual type found in PBIX.

Pass Threshold: 70 points.
"""

import json
import os
import tempfile
import csv
import logging
import io

logger = logging.getLogger(__name__)

def verify_imdb_genre_trends(traj, env_info, task_info):
    """Verify IMDB analysis task via exported artifacts."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    try:
        copy_from_env("C:/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Exported CSV for Content Verification
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_csv.close()
    csv_content_valid = False
    csv_rows = []
    
    if result_data.get("csv_exists"):
        try:
            # Power BI exports are often UTF-16LE with BOM
            copy_from_env("C:/Users/Docker/Documents/TaskData/genre_stats.csv", temp_csv.name)
            
            # Try reading with different encodings common in Windows
            content = None
            for encoding in ['utf-16-le', 'utf-8-sig', 'utf-8', 'cp1252']:
                try:
                    with open(temp_csv.name, 'r', encoding=encoding) as f:
                        content = f.read()
                        # If we read something that looks like CSV, stop
                        if "," in content and len(content) > 10:
                            break
                except:
                    continue
            
            if content:
                # Parse CSV
                reader = csv.reader(io.StringIO(content))
                csv_rows = list(reader)
                if len(csv_rows) > 1:
                    csv_content_valid = True
        except Exception as e:
            logger.warning(f"Failed to read CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    # --- Scoring ---
    score = 0
    feedback = []

    # Criterion 1: File Saved (10 pts)
    if result_data.get("pbix_exists") and result_data.get("created_during_task"):
        score += 10
        feedback.append("PBIX file saved.")
    else:
        feedback.append("PBIX file missing or not saved during task.")

    # Criterion 2: CSV Evidence (15 pts)
    if csv_content_valid:
        score += 15
        feedback.append("Matrix data exported successfully.")
    else:
        feedback.append("CSV export missing or empty.")

    # Criterion 3: Genre Split (30 pts)
    # Check rows (excluding header) for '|' character in the first column
    split_success = False
    if csv_content_valid:
        # Assume first column is Genre (standard matrix export behavior)
        # Check first 5 rows of data
        pipe_found = False
        row_count = 0
        for i, row in enumerate(csv_rows[1:10]): # Check first few data rows
            if not row: continue
            row_count += 1
            if '|' in row[0]:
                pipe_found = True
                break
        
        # Also check unique count - if they didn't split, unique count will be very high (>100)
        # If split correctly, unique genres usually < 30
        
        if not pipe_found and row_count > 0:
            score += 30
            split_success = True
            feedback.append("Genres split correctly (no pipes found).")
        else:
            feedback.append("Genres NOT split correctly ('|' found or empty data).")

    # Criterion 4: Decade Binning (20 pts)
    # Check headers (or data) for decade-like numbers (1980, 1990, 2000)
    binning_success = False
    if csv_content_valid:
        # In a matrix export, columns are usually the 2nd dimension.
        # Header row: "Primary_Genre, 1980, 1990, 2000..."
        header = csv_rows[0]
        decade_cols = 0
        for col in header:
            clean_col = col.strip()
            # Check if it looks like a decade (4 digits, ends in 0, starts with 19 or 20)
            if len(clean_col) == 4 and clean_col.isdigit() and clean_col.endswith('0') and (clean_col.startswith('19') or clean_col.startswith('20')):
                decade_cols += 1
        
        if decade_cols >= 3:
            score += 20
            binning_success = True
            feedback.append("Decade binning detected in columns.")
        else:
            feedback.append("Decade binning not detected in CSV headers.")

    # Criterion 5 & 6: Visual Types (15 + 10 pts)
    visuals = result_data.get("visual_types", [])
    has_matrix = any(v in ['pivotTable', 'matrix'] for v in visuals)
    has_scatter = any('scatter' in v.lower() for v in visuals)

    if has_matrix:
        score += 15
        feedback.append("Matrix visual found.")
    else:
        feedback.append("Matrix visual NOT found.")

    if has_scatter:
        score += 10
        feedback.append("Scatter chart found.")
    else:
        feedback.append("Scatter chart NOT found.")

    return {
        "passed": score >= 70 and split_success,
        "score": score,
        "feedback": " ".join(feedback)
    }