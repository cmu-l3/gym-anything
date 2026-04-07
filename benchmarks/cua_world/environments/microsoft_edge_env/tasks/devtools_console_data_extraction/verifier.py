#!/usr/bin/env python3
"""
Verifier for DevTools Console Data Extraction task.

Verifies:
1. CSV file exists and was created during task.
2. CSV content structure (headers, rows, valid data).
3. Browser history indicates visit to source page (anti-gaming).
4. Log file exists.
"""

import json
import os
import tempfile
import logging
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_devtools_console_data_extraction(traj, env_info, task_info):
    """
    Verify the extraction of population data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_countries = metadata.get('validation_countries', ["China", "India", "United States"])
    min_rows = metadata.get('min_rows', 50)

    # Temporary files for copying out of container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    try:
        # 1. Load JSON Result
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

        score = 0
        feedback_parts = []
        
        # Unpack result data
        csv_info = result.get("csv_file", {})
        log_info = result.get("log_file", {})
        wikipedia_visited = result.get("wikipedia_visited", False)

        # ---------------------------------------------------------------------
        # CRITERION 1: CSV File Existence & Creation Time (10 pts)
        # ---------------------------------------------------------------------
        if csv_info.get("exists") and csv_info.get("created_during_task"):
            score += 10
            feedback_parts.append("CSV file created during task (10/10)")
            
            # Copy CSV content for further analysis
            try:
                copy_from_env("/home/ga/Desktop/country_populations.csv", temp_csv.name)
                with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                    csv_content = f.read()
            except Exception as e:
                csv_content = ""
                feedback_parts.append(f"Error reading CSV content: {e}")
        else:
            feedback_parts.append("CSV file missing or not created during task (0/10)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # ---------------------------------------------------------------------
        # CRITERION 2: CSV Structure & Headers (10 pts)
        # ---------------------------------------------------------------------
        rows = []
        try:
            # Handle potential variations in CSV format
            reader = csv.reader(io.StringIO(csv_content))
            rows = list(reader)
        except:
            pass

        has_header = False
        if rows:
            header = [h.lower() for h in rows[0]]
            if any("country" in h for h in header) and any("population" in h for h in header):
                score += 10
                has_header = True
                feedback_parts.append("CSV headers correct (10/10)")
            else:
                feedback_parts.append("CSV headers missing or incorrect (0/10)")
        else:
            feedback_parts.append("CSV file is empty (0/10)")

        # ---------------------------------------------------------------------
        # CRITERION 3: Data Quantity (>= 50 rows) (15 pts)
        # ---------------------------------------------------------------------
        data_rows = rows[1:] if has_header else rows
        if len(data_rows) >= min_rows:
            score += 15
            feedback_parts.append(f"Extracted {len(data_rows)} rows (>= {min_rows}) (15/15)")
        elif len(data_rows) > 0:
            score += 5
            feedback_parts.append(f"Extracted only {len(data_rows)} rows (< {min_rows}) (5/15)")
        else:
            feedback_parts.append("No data rows found (0/15)")

        # ---------------------------------------------------------------------
        # CRITERION 4: Data Quality - Real Countries (20 pts)
        # ---------------------------------------------------------------------
        # Identify columns
        country_col_idx = -1
        pop_col_idx = -1
        if has_header:
            header = [h.lower() for h in rows[0]]
            for i, h in enumerate(header):
                if "country" in h: country_col_idx = i
                if "population" in h: pop_col_idx = i
        
        real_countries_found = 0
        if country_col_idx != -1 and data_rows:
            extracted_countries = [r[country_col_idx] for r in data_rows if len(r) > country_col_idx]
            # Check for matches
            for valid in expected_countries:
                # Loose matching to handle "China[a]" or "United States (more info)"
                if any(valid.lower() in c.lower() for c in extracted_countries):
                    real_countries_found += 1
        
        # Need at least 10 matches for full points
        if real_countries_found >= 10:
            score += 20
            feedback_parts.append(f"Found {real_countries_found} valid country names (20/20)")
        elif real_countries_found > 0:
            score += 10
            feedback_parts.append(f"Found {real_countries_found} valid country names (10/20)")
        else:
            feedback_parts.append("No recognized country names found (0/20)")

        # ---------------------------------------------------------------------
        # CRITERION 5: Data Quality - Numeric Populations (15 pts)
        # ---------------------------------------------------------------------
        valid_nums = 0
        if pop_col_idx != -1 and data_rows:
            for r in data_rows:
                if len(r) > pop_col_idx:
                    val = r[pop_col_idx].replace(',', '').replace(' ', '').strip()
                    # Remove citations like [1]
                    import re
                    val = re.sub(r'\[.*?\]', '', val)
                    if val.isdigit() and int(val) > 1000: # Sanity check
                        valid_nums += 1
        
        if valid_nums >= 10:
            score += 15
            feedback_parts.append("Population data is numeric (15/15)")
        else:
            feedback_parts.append("Population data malformed or missing (0/15)")

        # ---------------------------------------------------------------------
        # CRITERION 6: History Verification (15 pts)
        # ---------------------------------------------------------------------
        if wikipedia_visited:
            score += 15
            feedback_parts.append("Browser history confirms visit to Wikipedia (15/15)")
        else:
            feedback_parts.append("No history of visiting Wikipedia found (0/15)")

        # ---------------------------------------------------------------------
        # CRITERION 7: Log File (10 pts)
        # ---------------------------------------------------------------------
        if log_info.get("exists") and log_info.get("created_during_task"):
            score += 10
            feedback_parts.append("Log file created (10/10)")
        else:
            feedback_parts.append("Log file missing (0/10)")

        # ---------------------------------------------------------------------
        # BONUS: Thoroughness (5 pts)
        # ---------------------------------------------------------------------
        if len(data_rows) >= 100:
            score += 5
            feedback_parts.append("Bonus: Extracted 100+ rows (5/5)")

        return {
            "passed": score >= 65,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)
        if os.path.exists(temp_log.name): os.unlink(temp_log.name)