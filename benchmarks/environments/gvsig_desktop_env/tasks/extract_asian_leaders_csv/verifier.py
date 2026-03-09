#!/usr/bin/env python3
"""
Verifier for extract_asian_leaders_csv task.
Checks if the agent exported the top 5 Asian countries by GDP to a CSV file.
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_asian_leaders_csv(traj, env_info, task_info):
    """
    Verifies that the user created a CSV file with the top 5 Asian countries by GDP.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/gvsig_data/exports/asian_leaders.csv')
    required_countries = metadata.get('required_countries', ["China", "Japan", "India"])
    
    score = 0
    feedback = []
    
    # 1. Get the result JSON from the container
    # ----------------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=True) as tmp_json:
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            tmp_json.seek(0)
            task_result = json.load(tmp_json)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # 2. Check File Existence and Creation Time (Anti-gaming)
    # ----------------------------------------------------------------
    if not task_result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    score += 10
    feedback.append("File exists.")

    if task_result.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task session.")
    else:
        feedback.append("Warning: File timestamp suggests it was not created during this session.")

    if task_result.get("file_size_bytes", 0) > 0:
        score += 5
        feedback.append("File is not empty.")
    else:
        return {"passed": False, "score": score, "feedback": "File is empty."}

    # 3. Analyze CSV Content
    # ----------------------------------------------------------------
    # Retrieve the actual CSV file
    csv_content = []
    with tempfile.NamedTemporaryFile(suffix=".csv", delete=True) as tmp_csv:
        try:
            copy_from_env(expected_path, tmp_csv.name)
            # Read CSV - handle potential encoding or delimiter issues
            # gvSIG export usually uses comma or semicolon depending on locale, we'll try to sniff
            with open(tmp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
                
            # Basic delimiter sniffing
            delimiter = ','
            if ';' in content and content.count(';') > content.count(','):
                delimiter = ';'
                
            reader = csv.DictReader(content.splitlines(), delimiter=delimiter)
            csv_content = list(reader)
            
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read/parse CSV: {str(e)}"}

    # 4. Verify Data Logic
    # ----------------------------------------------------------------
    row_count = len(csv_content)
    
    # Criterion: Row Count (Should be 5)
    if row_count == 5:
        score += 20
        feedback.append("Correct number of records (5).")
    elif row_count > 0:
        # Partial credit if they exported something but wrong count
        score += 5
        feedback.append(f"Incorrect number of records: {row_count} (expected 5).")
    else:
        feedback.append("CSV contains no data rows.")

    # Criterion: Columns Exist
    if not csv_content:
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
        
    first_row = csv_content[0]
    keys = [k.upper() for k in first_row.keys()]
    
    # Check for critical columns (flexible matching)
    has_name = any("NAME" in k or "ADMIN" in k for k in keys)
    has_gdp = any("GDP" in k for k in keys)
    has_continent = any("CONTINENT" in k for k in keys)

    if has_name and has_gdp:
        score += 10
        feedback.append("Critical columns (Name, GDP) found.")
    else:
        feedback.append("Missing critical columns (Name or GDP).")

    # Criterion: Continent Filter (Asia)
    asian_count = 0
    names_found = []
    gdp_values = []

    for row in csv_content:
        # Normalize keys
        row_norm = {k.upper(): v for k, v in row.items()}
        
        # Find values using fuzzy key matching
        continent_val = ""
        name_val = ""
        gdp_val = 0.0

        for k, v in row_norm.items():
            if "CONTINENT" in k:
                continent_val = v
            if "NAME" in k or "ADMIN" in k:
                name_val = v
            if "GDP" in k:
                try:
                    gdp_val = float(v)
                except:
                    pass

        if "Asia" in continent_val:
            asian_count += 1
        
        names_found.append(name_val)
        gdp_values.append(gdp_val)

    if asian_count == row_count and row_count > 0:
        score += 20
        feedback.append("All exported records are from Asia.")
    elif asian_count > 0:
        score += 10
        feedback.append(f"Only {asian_count}/{row_count} records are from Asia.")
    else:
        feedback.append("No Asian records found.")

    # Criterion: Sorting (Descending GDP)
    is_sorted = False
    if len(gdp_values) > 1:
        # Check if sorted descending
        is_sorted = all(gdp_values[i] >= gdp_values[i+1] for i in range(len(gdp_values)-1))
        
    if is_sorted:
        score += 15
        feedback.append("Data is sorted by GDP (descending).")
    else:
        feedback.append("Data is NOT sorted by GDP.")

    # Criterion: Top Countries Present
    # Check if critical Asian economies are present
    found_leaders = 0
    for req in required_countries:
        if any(req in name for name in names_found):
            found_leaders += 1
    
    if found_leaders >= len(required_countries):
        score += 10
        feedback.append(f"Found all required leaders: {', '.join(required_countries)}.")
    elif found_leaders > 0:
        score += 5
        feedback.append(f"Found some leaders: {found_leaders}/{len(required_countries)}.")

    # Final Pass Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }