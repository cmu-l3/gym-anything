#!/usr/bin/env python3
"""
Verifier for automate_asset_inventory_export task.
Checks if the Python script exists, runs correctly, and produces a valid CSV
matching the Wazuh API data.
"""

import json
import os
import csv
import io
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_automate_asset_inventory_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # Criteria 1: Script exists and created during task (20 pts)
    if result.get("script_exists") and result.get("script_created_during_task"):
        score += 20
        feedback.append("Script 'agent_reporter.py' created successfully.")
    else:
        feedback.append("Script file missing or pre-existing.")
        
    # Criteria 2: Script runs successfully (Functional Test) (20 pts)
    if result.get("script_valid_execution"):
        score += 20
        feedback.append("Script executed successfully and generated CSV.")
    else:
        feedback.append("Script execution failed or did not produce output.")
        
    # Criteria 3: CSV Headers (20 pts)
    # Expected: "Agent ID,Hostname,IP Address,OS,Groups" (case insensitive/whitespace tolerant)
    raw_headers = result.get("csv_headers", "")
    # Parse the header string as CSV to handle potential quoting
    try:
        reader = csv.reader(io.StringIO(raw_headers.strip()))
        headers = next(reader)
        # Normalize
        headers = [h.strip().lower() for h in headers]
        expected = ["agent id", "hostname", "ip address", "os", "groups"]
        
        # Check intersection or exact match
        # We'll be slightly lenient on exact order if all are present, but strict on names
        missing = [e for e in expected if e not in headers]
        if not missing:
            score += 20
            feedback.append("CSV headers are correct.")
        else:
            feedback.append(f"Missing headers: {missing}")
            # Partial credit if some match
            score += int(20 * (len(expected) - len(missing)) / len(expected))
            
    except Exception:
        feedback.append("Could not parse CSV headers.")

    # Criteria 4: CSV Content & Group Handling (40 pts)
    # We compare the CSV sample content with the Ground Truth JSON
    ground_truth = result.get("ground_truth_json", {}).get("data", {}).get("affected_items", [])
    csv_sample_str = result.get("csv_content_sample", "").replace(';', '\n') # Revert the tr replace
    
    valid_rows = 0
    manager_found = False
    
    try:
        reader = csv.DictReader(io.StringIO(csv_sample_str))
        rows = list(reader)
        
        for agent in ground_truth:
            agent_id = agent.get("id")
            # Find this agent in CSV
            match = None
            for row in rows:
                # Handle varying header names if user mapped them slightly differently
                # But we enforced headers in description.
                # Look for ID in values
                if agent_id in row.values():
                    match = row
                    break
            
            if match:
                valid_rows += 1
                if agent_id == "000":
                    manager_found = True
                    # Check Group formatting
                    # API groups is list: ["default"] or []
                    api_groups = agent.get("group", [])
                    if isinstance(api_groups, list):
                        expected_group_str = ";".join(api_groups)
                    else:
                        expected_group_str = str(api_groups)
                        
                    # Find the group column (key containing 'group')
                    group_key = next((k for k in match.keys() if k and 'group' in k.lower()), None)
                    if group_key:
                        csv_groups = match[group_key]
                        if expected_group_str in csv_groups or (not expected_group_str and not csv_groups):
                            # Groups look good
                            pass
                        else:
                            feedback.append(f"Group formatting mismatch for Agent {agent_id}. Expected '{expected_group_str}', got '{csv_groups}'")
                            valid_rows -= 0.5 # Penalty
    
    except Exception as e:
        feedback.append(f"Error parsing CSV content: {e}")
        
    if manager_found:
        score += 20
        feedback.append("Manager agent found in CSV.")
    else:
        feedback.append("Manager agent (000) not found in CSV.")
        
    if valid_rows > 0:
        score += 20
        feedback.append("CSV contains valid agent data.")

    return {
        "passed": score >= 80,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }