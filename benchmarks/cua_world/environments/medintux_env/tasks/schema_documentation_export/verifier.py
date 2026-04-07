#!/usr/bin/env python3
"""
Verifier for schema_documentation_export task.
Compares agent's generated JSON schema against actual database state.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schema_documentation_export(traj, env_info, task_info):
    """
    Verify the schema documentation task.
    
    Criteria:
    1. Output file exists and is valid JSON (10 pts)
    2. File created during task (anti-gaming) (10 pts)
    3. JSON structure matches requirements (10 pts)
    4. Table count and list accuracy (20 pts)
    5. Row count accuracy for top tables (20 pts)
    6. Detailed column schema accuracy for key tables (30 pts)
    
    Total: 100 pts
    Threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result Metadata & Ground Truth
    # ------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check existence
    if not result_meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file ~/Documents/drtuxtest_schema.json not found."}

    score += 10 # File exists
    
    # Check timestamp
    if result_meta.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("Warning: File timestamp suggests it was not created during this session.")

    # 2. Retrieve & Parse Agent Output
    # --------------------------------
    agent_file_path = result_meta.get("agent_output_path")
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_json = {}
    valid_json = False
    
    try:
        copy_from_env(agent_file_path, temp_agent.name)
        with open(temp_agent.name, 'r') as f:
            agent_json = json.load(f)
        valid_json = True
    except json.JSONDecodeError:
        feedback_parts.append("File is not valid JSON.")
    except Exception as e:
        feedback_parts.append(f"Failed to read output file: {e}")
    finally:
        if os.path.exists(temp_agent.name):
            os.unlink(temp_agent.name)
            
    if not valid_json:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Retrieve Ground Truth
    # ------------------------
    gt_path = result_meta.get("ground_truth_path")
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    
    try:
        copy_from_env(gt_path, temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 4. Verify Structure & Content
    # -----------------------------
    
    # Structure Check (10 pts)
    has_keys = all(k in agent_json for k in ["database", "tables", "top_5_largest_tables", "summary"])
    if has_keys:
        score += 10
        feedback_parts.append("JSON structure valid.")
    else:
        feedback_parts.append("Missing required top-level keys in JSON.")

    # Table Accuracy (20 pts)
    agent_tables = {t.get("name") for t in agent_json.get("tables", [])}
    gt_tables = set(ground_truth.get("table_names", []))
    
    if len(gt_tables) > 0:
        intersection = agent_tables.intersection(gt_tables)
        coverage = len(intersection) / len(gt_tables)
        if coverage >= 0.9:
            score += 20
            feedback_parts.append(f"Table list accurate ({len(intersection)}/{len(gt_tables)}).")
        elif coverage >= 0.5:
            score += 10
            feedback_parts.append(f"Table list partial ({len(intersection)}/{len(gt_tables)}).")
        else:
            feedback_parts.append(f"Table list poor coverage ({int(coverage*100)}%).")
    
    # Row Count Accuracy (20 pts)
    # Check top 5 tables from GT
    gt_top5 = ground_truth.get("top_5", [])
    row_score = 0
    checked_count = 0
    
    agent_table_map = {t.get("name"): t for t in agent_json.get("tables", [])}
    
    for item in gt_top5:
        t_name = item['name']
        gt_count = item['row_count']
        
        if t_name in agent_table_map:
            agent_count = agent_table_map[t_name].get("row_count", -1)
            # Allow 10% tolerance or +/- 5 rows for small tables
            tolerance = max(5, gt_count * 0.1)
            if abs(agent_count - gt_count) <= tolerance:
                row_score += 4
            checked_count += 1
            
    if checked_count > 0 and row_score > 0:
        score += row_score
        feedback_parts.append(f"Row counts checked for top tables (+{row_score} pts).")

    # Column Schema Accuracy (30 pts)
    # Check 'IndexNomPrenom' and 'fchpat'
    schema_score = 0
    gt_schemas = ground_truth.get("schemas", {})
    
    for t_name, gt_cols in gt_schemas.items():
        if t_name not in agent_table_map:
            continue
            
        agent_cols = agent_table_map[t_name].get("columns", [])
        agent_col_map = {c.get("name"): c for c in agent_cols}
        
        # Check if agent found at least 80% of columns
        matched_cols = 0
        type_matches = 0
        
        for gt_col in gt_cols:
            c_name = gt_col['name']
            if c_name in agent_col_map:
                matched_cols += 1
                # Rough type check (e.g. 'varchar' in 'varchar(50)')
                if gt_col['type'].lower() in agent_col_map[c_name].get("type", "").lower():
                    type_matches += 1
        
        total_gt = len(gt_cols)
        if total_gt > 0:
            if matched_cols / total_gt >= 0.8:
                schema_score += 10 # Found the columns
            if type_matches / total_gt >= 0.8:
                schema_score += 5 # Types look correct
                
    score += schema_score
    if schema_score > 0:
        feedback_parts.append(f"Schema details validated (+{schema_score} pts).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }