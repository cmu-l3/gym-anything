#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import csv
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_fred_labor_market_analysis(traj, env_info, task_info):
    """
    Verifies the FRED Labor Market Analysis task.
    
    Scoring Criteria (100 pts):
    1. FRED Visited (10 pts)
    2. Bookmark Created (10 pts)
    3. Image Downloaded (15 pts)
    4. CSV Downloaded (15 pts)
    5. CSV Analysis (50 pts):
       - Combined Data (both UNRATE and CIVPART cols) (30 pts)
       - Correct Start Date (approx 2019-01-01) (10 pts)
       - Plausible Values (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    # 1. Retrieve Result JSON
    result_json_path = "/tmp/task_result.json"
    local_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    
    try:
        copy_from_env(result_json_path, local_json)
        with open(local_json, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        if os.path.exists(local_json): os.unlink(local_json)

    score = 0
    feedback = []

    # --- Criterion 1: FRED Visited (10 pts) ---
    if result.get('fred_visits', 0) > 0:
        score += 10
        feedback.append("FRED website visited.")
    else:
        feedback.append("No history of visiting FRED.")

    # --- Criterion 2: Bookmark Created (10 pts) ---
    if result.get('bookmark_found'):
        score += 10
        feedback.append(f"Bookmark found: '{result.get('bookmark_title')}'.")
    else:
        feedback.append("Required bookmark 'Labor Market Dashboard' not found.")

    # --- Criterion 3: Image Downloaded (15 pts) ---
    if result.get('img_exists') and result.get('img_size', 0) > 1000:
        score += 15
        feedback.append("Graph image downloaded successfully.")
    else:
        feedback.append("Graph image not found or empty.")

    # --- Criterion 4: CSV Downloaded (15 pts) ---
    csv_exists = result.get('csv_exists')
    csv_valid = False
    
    if csv_exists and result.get('csv_size', 0) > 100:
        score += 15
        feedback.append("Data CSV downloaded.")
        
        # Retrieve the CSV content for deep analysis
        remote_csv_path = result.get('csv_path')
        local_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv").name
        
        try:
            copy_from_env(remote_csv_path, local_csv)
            csv_valid = True
        except Exception as e:
            feedback.append(f"Failed to copy CSV for verification: {e}")
    else:
        feedback.append("Data CSV not found or too small.")

    # --- Criterion 5: CSV Analysis (50 pts total) ---
    if csv_valid:
        try:
            with open(local_csv, 'r', encoding='utf-8') as f:
                # FRED CSVs often have a header info section, skipping lines until 'DATE'
                lines = f.readlines()
            
            # Find the header line
            header_idx = -1
            for i, line in enumerate(lines):
                if "DATE" in line or "date" in line.lower():
                    header_idx = i
                    break
            
            if header_idx != -1:
                # Parse header
                headers = [h.strip() for h in lines[header_idx].split(',')]
                data_rows = lines[header_idx+1:]
                
                # A. Combined Data Check (30 pts)
                # We expect columns roughly like: DATE, UNRATE, CIVPART
                # Note: User might rename series, so we look for substrings or count columns > 2
                has_unrate = any("UNRATE" in h or "Unemployment" in h for h in headers)
                has_civpart = any("CIVPART" in h or "Participation" in h for h in headers)
                
                if has_unrate and has_civpart:
                    score += 30
                    feedback.append("CSV contains both Unemployment and Participation data.")
                elif len(headers) >= 3:
                     # Fallback: if headers are renamed but there are enough columns
                    score += 20 
                    feedback.append("CSV has multiple columns, likely correct (headers ambiguous).")
                else:
                    feedback.append("CSV missing required combined data columns.")

                # B. Start Date Check (10 pts)
                if data_rows:
                    first_row = data_rows[0].split(',')
                    date_str = first_row[0].strip()
                    try:
                        # FRED standard format YYYY-MM-DD
                        dt = datetime.strptime(date_str, "%Y-%m-%d")
                        if 2018 <= dt.year <= 2019:
                            score += 10
                            feedback.append(f"Data start date ({date_str}) matches 2019 requirement.")
                        else:
                            feedback.append(f"Data start date ({date_str}) incorrect (expected ~2019).")
                    except ValueError:
                        feedback.append("Could not parse date format in CSV.")

                # C. Plausible Values Check (10 pts)
                # Check middle row to ensure data isn't garbage
                if len(data_rows) > 5:
                    mid_row = data_rows[len(data_rows)//2].split(',')
                    try:
                        # Assuming col 1 and 2 are data. UNRATE ~3-14, CIVPART ~60-64
                        val1 = float(mid_row[1])
                        val2 = float(mid_row[2]) if len(mid_row) > 2 else 0
                        
                        # We don't know order, check if one is small and one is large
                        vals = [val1, val2]
                        has_rate = any(2.5 <= v <= 15.0 for v in vals)
                        has_part = any(55.0 <= v <= 70.0 for v in vals)
                        
                        if has_rate and has_part:
                            score += 10
                            feedback.append("Data values look plausible for labor stats.")
                        else:
                            feedback.append(f"Data values {vals} outside expected ranges.")
                    except (ValueError, IndexError):
                         pass # Skip value check if parsing fails
            else:
                feedback.append("Could not find header row in CSV.")

        except Exception as e:
            feedback.append(f"Error analyzing CSV content: {e}")
        finally:
            if os.path.exists(local_csv): os.unlink(local_csv)

    passed = (score >= 60)
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }