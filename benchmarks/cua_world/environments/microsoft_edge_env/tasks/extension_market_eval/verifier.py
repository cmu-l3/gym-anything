#!/usr/bin/env python3
"""
Verifier for extension_market_eval@1

Criteria:
1. CSV file exists and was created during task.
2. CSV file has correct headers.
3. CSV file contains exactly 3 data rows.
4. Data content validation (Names look real, Ratings are numbers).
5. Browser history indicates research was performed.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extension_market_eval(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load task result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Timestamp (10 pts) ---
    file_info = result_data.get('output_file', {})
    if not file_info.get('exists'):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found on Desktop."}
    
    if not file_info.get('created_during_task'):
        feedback.append("File exists but was not modified during task time (anti-gaming check failed).")
        # We continue but max score is impacted
    else:
        score += 10
        feedback.append("Output file created during task.")

    # --- Retrieve CSV for Content Analysis ---
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(file_info['path'], temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as csvfile:
            # Detect format (sniffer handles delimiters/quoting)
            try:
                sample = csvfile.read(1024)
                csvfile.seek(0)
                dialect = csv.Sniffer().sniff(sample)
                has_header = csv.Sniffer().has_header(sample)
            except csv.Error:
                # Fallback to standard excel-csv if sniffer fails
                dialect = 'excel'
                has_header = True
                csvfile.seek(0)

            reader = csv.DictReader(csvfile, dialect=dialect)
            
            # --- Criterion 2: Headers (15 pts) ---
            # DictReader uses the first row as keys if fieldnames isn't provided.
            # We check if required columns exist in the identified fieldnames.
            required_headers = {'Name', 'Publisher', 'Rating', 'Users', 'Description'}
            headers_found = set(reader.fieldnames) if reader.fieldnames else set()
            
            # Case-insensitive header check
            headers_map = {h.lower(): h for h in headers_found}
            missing_headers = [h for h in required_headers if h.lower() not in headers_map]

            if not missing_headers:
                score += 15
                feedback.append("CSV headers are correct.")
            else:
                feedback.append(f"Missing or incorrect CSV headers: {missing_headers}")

            # --- Criterion 3 & 4: Data Validation (55 pts total) ---
            rows = list(reader)
            row_count = len(rows)
            
            if row_count == 3:
                score += 20
                feedback.append("Correct number of extensions (3) found.")
            else:
                feedback.append(f"Expected 3 rows of data, found {row_count}. (-{max(0, abs(3-row_count)*5)} pts)")
                # Partial credit logic: 20 pts base, lose 5 for each wrong count
                score += max(0, 20 - abs(3-row_count) * 5)

            # Analyze Row Content
            valid_rows = 0
            for i, row in enumerate(rows):
                # Normalize keys using the map from earlier
                r = {k.lower(): v for k, v in row.items()}
                
                # Check Name (should contain 'Color' or 'Picker')
                name = r.get('name', '')
                if 'color' in name.lower() or 'picker' in name.lower():
                    valid_rows += 1
                
                # Check Rating (should be number 0-5)
                try:
                    rating = float(r.get('rating', -1))
                    if 0 <= rating <= 5:
                        valid_rows += 1
                except ValueError:
                    pass
                
                # Check Users (should contain digits)
                users = r.get('users', '')
                if any(c.isdigit() for c in users):
                    valid_rows += 1
                
                # Check Description (not empty)
                if len(r.get('description', '')) > 5:
                    valid_rows += 1

            # Total possible content points: 3 rows * 4 checks = 12 checks.
            # Scale 35 points based on checks passed.
            # Ideally 12 checks.
            total_checks = row_count * 4
            if total_checks > 0:
                content_score = int((valid_rows / 12.0) * 35) # Normalize to target of 3 rows
                content_score = min(35, content_score) # Cap at 35
                score += content_score
                feedback.append(f"Data content validation score: {content_score}/35")
            
    except Exception as e:
        feedback.append(f"Failed to parse CSV file: {e}")
        # If file exists but is garbage, they get the 10 pts for existence but lose parsing points
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # --- Criterion 5: Browser History (20 pts) ---
    history = result_data.get('history', {})
    search_visits = history.get('search_visits', 0)
    detail_visits = history.get('detail_visits', 0)

    if search_visits > 0:
        score += 10
        feedback.append("Browser history confirms search performed.")
    else:
        feedback.append("No history of visiting Add-ons search page.")

    if detail_visits >= 3:
        score += 10
        feedback.append("Browser history confirms visited extension details pages.")
    elif detail_visits > 0:
        score += 5
        feedback.append(f"Only visited {detail_visits} extension detail pages (expected 3).")
    else:
        feedback.append("No history of visiting extension detail pages.")

    # Final tally
    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }