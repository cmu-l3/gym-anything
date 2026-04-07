#!/usr/bin/env python3
"""Verifier for housing_typology_diversity task."""

import json
import tempfile
import os
import csv


def verify_housing_typology_diversity(traj, env_info, task_info):
    """Verify Housing Typology Diversity Analysis was completed.

    Scoring (100 points total):
    - Notebook Execution: 20 pts
    - CSV Structure: 20 pts
    - Index Calculation Accuracy: 25 pts
    - Filtering Logic: 10 pts
    - JSON Summary Output: 15 pts
    - Visualization Artifact: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_cols = metadata.get('expected_csv_columns', [
        "zone_id", "total_res_buildings", "total_res_units", "simpsons_diversity_index"
    ])
    expected_json_keys = metadata.get('expected_json_keys', [
        "citywide_average_sdi", "most_diverse_zone_id", "least_diverse_zone_id", "zones_analyzed_count"
    ])

    score = 0
    feedback = []

    # Part 1: Task result JSON
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Notebook Execution (20 pts)
    notebook_score = 0
    if result.get('notebook_exists') and result.get('notebook_modified'):
        notebook_score += 5
    
    nb_a = result.get('notebook_analysis', {})
    if nb_a.get('has_code'):
        notebook_score += 3
    if nb_a.get('has_pandas') and nb_a.get('has_hdf'):
        notebook_score += 4
    if nb_a.get('has_groupby') and nb_a.get('has_merge'):
        notebook_score += 4
    
    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec >= 3:
        notebook_score += 4
    elif num_exec > 0:
        notebook_score += 2
    
    score += notebook_score
    feedback.append(f"Notebook Execution: {notebook_score}/20")

    # CSV Structure & Content (20 + 25 + 10 = 55 pts)
    csv_structure_score = 0
    index_accuracy_score = 0
    filtering_logic_score = 0

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/zone_housing_diversity.csv'), temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            
            if header:
                header_clean = [h.strip().lower() for h in header]
                if all(col in header_clean for col in expected_csv_cols):
                    csv_structure_score += 20
                else:
                    csv_structure_score += 10 # Partial for having some expected headers
                
                rows = list(reader)
                if len(rows) > 0:
                    # Index Calculation Accuracy
                    valid_sdi_count = 0
                    non_zero_sdi = False
                    below_threshold_found = False
                    
                    try:
                        idx_bldgs = header_clean.index('total_res_buildings')
                        idx_sdi = header_clean.index('simpsons_diversity_index')
                        
                        for row in rows:
                            if len(row) > max(idx_bldgs, idx_sdi):
                                bldgs = float(row[idx_bldgs])
                                sdi = float(row[idx_sdi])
                                
                                if 0.0 <= sdi <= 1.0:
                                    valid_sdi_count += 1
                                if sdi > 0.0:
                                    non_zero_sdi = True
                                if bldgs < 10:
                                    below_threshold_found = True
                                    
                        if valid_sdi_count == len(rows):
                            index_accuracy_score += 15
                        elif valid_sdi_count > 0:
                            index_accuracy_score += 5
                            
                        if non_zero_sdi:
                            index_accuracy_score += 10
                            
                        if not below_threshold_found and len(rows) > 10:
                            filtering_logic_score += 10
                            
                    except (ValueError, IndexError):
                        pass

    except Exception as e:
        feedback.append(f"CSV Check Error: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    score += csv_structure_score
    feedback.append(f"CSV Structure: {csv_structure_score}/20")
    score += index_accuracy_score
    feedback.append(f"Index Accuracy: {index_accuracy_score}/25")
    score += filtering_logic_score
    feedback.append(f"Filtering Logic: {filtering_logic_score}/10")

    # JSON Summary (15 pts)
    json_score = 0
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(metadata.get('expected_json_path', '/home/ga/urbansim_projects/output/diversity_summary.json'), temp_json.name)
        with open(temp_json.name, 'r') as f:
            summary = json.load(f)
            keys_present = [k for k in expected_json_keys if k in summary]
            if len(keys_present) == len(expected_json_keys):
                json_score += 15
            else:
                json_score += len(keys_present) * 3
    except Exception:
        pass
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score += json_score
    feedback.append(f"JSON Summary: {json_score}/15")

    # Visualization Artifact (10 pts)
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_created'):
            plot_score += 3
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 2
    score += plot_score
    feedback.append(f"Visualization: {plot_score}/10")

    passed = score >= 70 and notebook_score >= 10 and csv_structure_score >= 20

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }