#!/usr/bin/env python3
"""
Verifier for summarize_gdp_by_continent task.

Verifies:
1. Output CSV file exists.
2. File is valid CSV format.
3. File contains Continent and GDP columns.
4. Values for key continents (Africa, South America) are within expected ranges.
5. File was created during the task session.
"""

import json
import os
import csv
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_summarize_gdp(traj, env_info, task_info):
    """
    Verify the GDP summary CSV.
    """
    # 1. Setup and copy files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_continents = metadata.get('expected_continents', ["Africa", "South America"])
    gdp_ranges = metadata.get('gdp_ranges', {})

    # Create temp files for artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    score = 0
    max_score = 100
    feedback = []
    
    try:
        # Copy result JSON
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
            
        # Check existence (20 pts)
        if not result_meta.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
        
        score += 20
        feedback.append("Output CSV exists.")

        # Check timestamp (20 pts)
        if result_meta.get('created_during_task', False):
            score += 20
            feedback.append("File created during task session.")
        else:
            feedback.append("File timestamp is invalid (old file?).")

        # Copy CSV content
        try:
            copy_from_env(result_meta['output_path'], temp_csv.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve CSV file: {str(e)}"}

        # Analyze CSV content (60 pts total)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # Detect header
            sample = f.read(1024)
            f.seek(0)
            has_header = csv.Sniffer().has_header(sample)
            reader = csv.reader(f)
            
            rows = list(reader)
            
            if len(rows) < 2:
                return {"passed": False, "score": score, "feedback": "CSV is empty or has no data rows."}
            
            # Identify columns
            header = rows[0] if has_header else []
            data_rows = rows[1:] if has_header else rows
            
            # Try to find index of continent and gdp
            # Strategy: Look for text column with continent names, numeric column with large numbers
            continent_idx = -1
            gdp_idx = -1
            
            # Heuristic for columns
            for i, col in enumerate(header):
                col_lower = col.lower()
                if "continent" in col_lower:
                    continent_idx = i
                if "gdp" in col_lower or "sum" in col_lower:
                    gdp_idx = i
            
            # Fallback scan data if header not clear
            if continent_idx == -1 or gdp_idx == -1:
                # Check first data row
                if data_rows:
                    first_row = data_rows[0]
                    for i, val in enumerate(first_row):
                        val_str = str(val).lower()
                        # Check for continent names
                        if any(c.lower() in val_str for c in expected_continents):
                            continent_idx = i
                        # Check for numeric GDP-like values (numeric and > 1000)
                        try:
                            num = float(val.replace(',', '').replace('$', ''))
                            if num > 1000:
                                gdp_idx = i
                        except:
                            pass

            if continent_idx == -1:
                feedback.append("Could not identify 'Continent' column.")
            if gdp_idx == -1:
                feedback.append("Could not identify 'GDP' column.")
            
            if continent_idx != -1 and gdp_idx != -1:
                score += 20
                feedback.append("Identified Continent and GDP columns.")
                
                # Verify Values (40 pts)
                valid_rows = 0
                correct_values = 0
                
                parsed_data = {}
                for row in data_rows:
                    if len(row) > max(continent_idx, gdp_idx):
                        try:
                            cont = row[continent_idx].strip()
                            gdp_raw = row[gdp_idx].replace(',', '').replace('$', '').strip()
                            gdp = float(gdp_raw)
                            parsed_data[cont] = gdp
                        except:
                            continue

                # Check specific continents
                checks_passed = 0
                checks_total = 0
                
                for cont, r_range in gdp_ranges.items():
                    checks_total += 1
                    # Fuzzy match continent name
                    found_val = None
                    for key in parsed_data:
                        if cont.lower() in key.lower():
                            found_val = parsed_data[key]
                            break
                    
                    if found_val is not None:
                        if r_range[0] <= found_val <= r_range[1]:
                            checks_passed += 1
                            feedback.append(f"GDP for {cont} is within expected range.")
                        else:
                            feedback.append(f"GDP for {cont} ({found_val}) is outside expected range ({r_range}).")
                    else:
                        feedback.append(f"Continent '{cont}' not found in output.")

                if checks_total > 0:
                    val_score = (checks_passed / checks_total) * 40
                    score += val_score
            else:
                feedback.append("Cannot verify values due to column identification failure.")

    except Exception as e:
        feedback.append(f"Verification error: {str(e)}")
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }