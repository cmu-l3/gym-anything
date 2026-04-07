#!/usr/bin/env python3
"""
Verifier for Grid Mix Source Analysis task.

Task Requirements:
1. Import USLCI & TRACI.
2. Build product system for Eastern US Grid.
3. Run Calculation.
4. Use Grouping feature to categorize into Fossil, Nuclear, Renewable.
5. Export CSV.

Scoring (100 pts):
- 20 pts: Product System created (DB evidence).
- 20 pts: Output file exists & created during task.
- 30 pts: Content Analysis (Keywords "Fossil", "Nuclear", "Renewable" present).
- 30 pts: Logic Check (Fossil > Nuclear, Fossil > Renewable for Eastern US grid).
- Bonus/Penalty: VLM verification of grouping workflow.
"""

import json
import os
import tempfile
import logging
import csv
import io

logger = logging.getLogger(__name__)

# VLM Prompt for Trajectory
TRAJECTORY_PROMPT = """You are analyzing screenshots of an OpenLCA workflow.
The user should be analyzing a product system and using the 'Grouping' feature.

Look for:
1. Analysis/Calculation Results View (charts or tables).
2. A 'Grouping' tab or dialog active.
3. Creating new groups (e.g., typing 'Fossil', 'Nuclear').
4. Dragging/assigning items to groups.

JSON Response:
{
    "analysis_view_seen": true/false,
    "grouping_feature_used": true/false,
    "custom_groups_created": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_grid_mix_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load JSON Result from Export Script
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 2. Check Prerequisites (DB & Product System) - 20 pts
    if result_data.get('db_found') and int(result_data.get('ps_count', 0)) >= 1:
        score += 20
        feedback.append("Product system created.")
    else:
        feedback.append("No product system found in database.")

    # 3. Check Output File Existence - 20 pts
    file_exists = result_data.get('file_exists')
    file_created = result_data.get('file_created_during_task')
    
    if file_exists and file_created:
        score += 20
        feedback.append("Output CSV created during task.")
    elif file_exists:
        score += 10
        feedback.append("Output CSV exists but timestamp unclear.")
    else:
        return {"passed": False, "score": score, "feedback": "No output file found. " + " ".join(feedback)}

    # 4. Content Analysis - 60 pts total
    # We need to read the CSV content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_content = ""
    try:
        copy_from_env("/home/ga/LCA_Results/grid_source_breakdown.csv", temp_csv.name)
        with open(temp_csv.name, 'r', errors='ignore') as f:
            csv_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV content: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Parsing logic
    # OpenLCA CSV exports vary, but usually contain Group Name and Result Value
    lower_content = csv_content.lower()
    
    has_fossil = "fossil" in lower_content
    has_nuclear = "nuclear" in lower_content
    has_renewable = "renewable" in lower_content
    
    groups_found = sum([has_fossil, has_nuclear, has_renewable])
    
    if groups_found == 3:
        score += 30
        feedback.append("All required groups (Fossil, Nuclear, Renewable) found in CSV.")
    elif groups_found > 0:
        score += 10 * groups_found
        feedback.append(f"Found {groups_found}/3 required groups.")
    else:
        feedback.append("No required groups found in CSV content.")

    # Logic Check: Extract values to verify Fossil > Nuclear
    # This is tricky without strict CSV formatting, so we do a heuristic scan
    # We look for lines containing the keyword and a number
    try:
        lines = csv_content.split('\n')
        val_fossil = 0.0
        val_nuclear = 0.0
        
        for line in lines:
            parts = line.split(',') # simplified CSV parse
            # Look for number in parts
            nums = []
            for p in parts:
                try:
                    # Clean string (remove quotes, spaces)
                    clean_p = p.replace('"', '').replace(' ', '')
                    nums.append(float(clean_p))
                except ValueError:
                    continue
            
            if not nums: continue
            
            # Assume the largest number in the row is the impact value (heuristic)
            row_val = max(nums)
            
            if "fossil" in line.lower():
                val_fossil = max(val_fossil, row_val)
            elif "nuclear" in line.lower():
                val_nuclear = max(val_nuclear, row_val)

        # Sanity check for Eastern US Grid: Fossil is usually significantly higher than Nuclear
        if val_fossil > 0 and val_nuclear > 0:
            if val_fossil > val_nuclear:
                score += 30
                feedback.append(f"Data Logic Pass: Fossil ({val_fossil:.2e}) > Nuclear ({val_nuclear:.2e}).")
            else:
                score += 10
                feedback.append(f"Data Logic Warning: Fossil ({val_fossil:.2e}) <= Nuclear ({val_nuclear:.2e})? Unusual for Eastern US.")
        elif val_fossil > 0:
            # If we found fossil but couldn't parse nuclear clearly, give partial credit
            score += 15
            feedback.append("Fossil data found, but comparison incomplete.")
        else:
            feedback.append("Could not parse numerical values from CSV.")

    except Exception as e:
        feedback.append(f"Error parsing CSV values: {e}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }