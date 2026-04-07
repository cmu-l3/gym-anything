#!/usr/bin/env python3
import json
import os
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scenario_catalog(traj, env_info, task_info):
    """
    Verify the scenario cataloging task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Extract Data
    catalog_exists = result.get('catalog_exists', False)
    checksum_exists = result.get('checksum_exists', False)
    report_exists = result.get('report_exists', False)
    
    ground_truth = result.get('ground_truth', [])
    agent_catalog_raw = result.get('agent_catalog_raw', '[]')
    agent_report = result.get('agent_report_content', '')
    agent_checksums = result.get('agent_checksum_sample', '')
    
    # 3. Verify Catalog JSON (45 points total)
    agent_catalog = []
    if catalog_exists:
        try:
            agent_catalog = json.loads(agent_catalog_raw)
            if isinstance(agent_catalog, list):
                score += 10 # JSON is valid and is a list
                feedback.append("Catalog is valid JSON array.")
                
                # Check Completeness (15 pts)
                if len(agent_catalog) == len(ground_truth):
                    score += 15
                    feedback.append(f"Catalog contains correct number of scenarios ({len(ground_truth)}).")
                else:
                    feedback.append(f"Catalog count mismatch: Agent={len(agent_catalog)}, Actual={len(ground_truth)}.")
                    # Partial credit for being close
                    if abs(len(agent_catalog) - len(ground_truth)) <= 2:
                        score += 5

                # Check Metadata Accuracy (20 pts)
                # We verify a few key fields for matching scenarios
                match_count = 0
                field_errors = 0
                
                # Convert ground truth to dict for easy lookup
                gt_map = {item['scenario_name']: item for item in ground_truth}
                
                for item in agent_catalog:
                    name = item.get('scenario_name')
                    if name in gt_map:
                        gt_item = gt_map[name]
                        
                        # Check key fields
                        # 1. World Model
                        if item.get('world_model') == gt_item.get('world_model'):
                            match_count += 1
                        else:
                            field_errors += 1
                            
                        # 2. Vessel Count
                        if str(item.get('traffic_vessel_count')) == str(gt_item.get('traffic_vessel_count')):
                            match_count += 1
                        else:
                            field_errors += 1
                            
                        # 3. Own Ship
                        if item.get('own_ship_name') == gt_item.get('own_ship_name'):
                            match_count += 1
                        else:
                            field_errors += 1
                            
                        # 4. Completeness
                        if item.get('is_complete') == gt_item.get('is_complete'):
                            match_count += 1
                        else:
                            field_errors += 1

                # Calculate accuracy score
                total_checks = len(agent_catalog) * 4
                if total_checks > 0:
                    accuracy = match_count / total_checks
                    if accuracy > 0.9:
                        score += 20
                        feedback.append("Metadata accuracy > 90%.")
                    elif accuracy > 0.7:
                        score += 10
                        feedback.append("Metadata accuracy > 70%.")
                    else:
                        feedback.append(f"Metadata accuracy low ({int(accuracy*100)}%).")
                
            else:
                feedback.append("Catalog is valid JSON but not a list.")
        except json.JSONDecodeError:
            feedback.append("Catalog file exists but is not valid JSON.")
    else:
        feedback.append("Catalog file not found.")

    # 4. Verify Checksums (20 points)
    if checksum_exists:
        score += 5
        lines = result.get('total_checksums_lines', 0)
        # Should be roughly > 3 files per scenario * num scenarios
        min_expected = len(ground_truth) * 3
        
        if lines >= min_expected:
            score += 5
            feedback.append(f"Checksum file has reasonable line count ({lines}).")
        
        # Check format of sample
        # Expected: "hash  /path/to/file"
        valid_format = False
        if re.search(r'^[a-f0-9]{64}\s+/', agent_checksums, re.MULTILINE):
            valid_format = True
            score += 10
            feedback.append("Checksums in valid SHA256 format.")
        else:
            feedback.append("Checksums format invalid (expected SHA256  /path).")
    else:
        feedback.append("Checksum file not found.")

    # 5. Verify Report (20 points)
    if report_exists:
        score += 5
        content = agent_report.lower()
        
        # Check for header
        if "preservation assessment report" in content:
            score += 5
            feedback.append("Report header found.")
            
        # Check for scenario count
        if str(len(ground_truth)) in content:
            score += 5
            feedback.append("Report mentions correct scenario count.")
            
        # Check for world models
        # Grab a world model from ground truth and see if it's there
        found_wm = False
        for gt in ground_truth:
            wm = gt.get('world_model')
            if wm and wm.lower() in content:
                found_wm = True
                break
        
        if found_wm:
            score += 5
            feedback.append("Report lists world models.")
    else:
        feedback.append("Report file not found.")

    # 6. Anti-Gaming / Final Logic (15 points)
    # Awarded if key files exist and seem generated during task (checked in export script via timestamp)
    if catalog_exists and checksum_exists and report_exists:
        score += 15
        feedback.append("All required files created during task session.")

    return {
        "passed": score >= 60 and catalog_exists,
        "score": score,
        "feedback": " ".join(feedback)
    }