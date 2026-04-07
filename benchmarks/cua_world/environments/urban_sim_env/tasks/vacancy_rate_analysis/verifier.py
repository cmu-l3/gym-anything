#!/usr/bin/env python3
"""Verifier for the Zone-Level Residential Vacancy Rate Analysis task."""

import json
import os
import tempfile
import re
import csv


def copy_json_from_env(env_info, remote_path):
    """Helper to copy a JSON file from the environment and parse it."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return None

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        if os.path.getsize(temp_file.name) > 0:
            with open(temp_file.name, 'r') as f:
                return json.load(f)
        return None
    except Exception:
        return None
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)


def copy_raw_from_env(env_info, remote_path, suffix='.tmp'):
    """Helper to copy a raw file from the environment, returning the local path."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return None

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        copy_from_env(remote_path, temp_file.name)
        if os.path.getsize(temp_file.name) > 0:
            return temp_file.name
    except Exception:
        pass
    
    if os.path.exists(temp_file.name):
        os.unlink(temp_file.name)
    return None


def verify_vacancy_analysis(traj, env_info, task_info):
    """
    Verify that the vacancy rate analysis was completed correctly.
    """
    score = 0
    feedback = []
    max_score = 100

    metadata = task_info.get('metadata', {})
    nb_path = metadata.get('expected_notebook_path')
    csv_path = metadata.get('expected_csv_path')
    json_path = metadata.get('expected_json_path')
    png_path = metadata.get('expected_png_path')
    gt_path = metadata.get('ground_truth_path')

    # 1. Fetch File Metadata & Ground Truth
    task_metadata = copy_json_from_env(env_info, '/tmp/task_metadata.json')
    gt_data = copy_json_from_env(env_info, gt_path)

    if not task_metadata:
        return {"passed": False, "score": 0, "feedback": "Failed to read task metadata from container"}
    if not gt_data:
        return {"passed": False, "score": 0, "feedback": "Ground truth data missing or unreadable"}

    task_start = task_metadata.get('task_start_time', 0)

    # 2. Check Timestamps (Anti-gaming) (10 points)
    files_created_during_task = 0
    for file_key in ['csv', 'json', 'png']:
        file_info = task_metadata.get(file_key, {})
        if file_info.get('exists') and file_info.get('mtime', 0) > task_start:
            files_created_during_task += 1
    
    if files_created_during_task == 3:
        score += 10
        feedback.append("All output files created during task (+10)")
    elif files_created_during_task > 0:
        score += 5
        feedback.append(f"Some outputs created during task ({files_created_during_task}/3) (+5)")
    else:
        feedback.append("No required outputs were created during the task timeframe")

    # 3. Verify CSV Output (20 points)
    csv_local = copy_raw_from_env(env_info, csv_path, '.csv')
    if csv_local:
        try:
            with open(csv_local, 'r') as f:
                reader = csv.DictReader(f)
                columns = [c.lower() for c in (reader.fieldnames or [])]
                rows = list(reader)
            
            req_cols = ['zone_id', 'total_units', 'occupied_units', 'vacant_units', 'vacancy_rate', 'market_condition']
            if all(c in columns for c in req_cols):
                score += 10
                feedback.append("CSV has all required columns (+10)")
            else:
                feedback.append(f"CSV missing columns. Expected: {req_cols}")

            expected_zones = gt_data.get('num_zones_analyzed', -1)
            if abs(len(rows) - expected_zones) <= 5:
                score += 10
                feedback.append(f"CSV row count ({len(rows)}) matches expected ({expected_zones}) (+10)")
            elif abs(len(rows) - expected_zones) <= 15:
                score += 5
                feedback.append(f"CSV row count ({len(rows)}) close to expected (+5)")
            else:
                feedback.append(f"CSV row count mismatch: got {len(rows)}, expected ~{expected_zones}")

        except Exception as e:
            feedback.append(f"Failed to parse CSV: {e}")
        finally:
            os.unlink(csv_local)
    else:
        feedback.append("CSV file not found")

    # 4. Verify JSON Summary (40 points)
    json_local = copy_raw_from_env(env_info, json_path, '.json')
    if json_local:
        try:
            with open(json_local, 'r') as f:
                summary = json.load(f)
            
            required_keys = ['citywide_vacancy_rate', 'num_zones_analyzed', 'highest_vacancy_zone_id', 
                             'lowest_vacancy_zone_id', 'num_tight_zones', 'num_healthy_zones', 'num_soft_zones']
            
            if all(k in summary for k in required_keys):
                score += 10
                feedback.append("JSON has all required keys (+10)")
            else:
                feedback.append("JSON missing required keys")

            # Check Values
            if 'citywide_vacancy_rate' in summary:
                agent_rate = float(summary['citywide_vacancy_rate'])
                gt_rate = gt_data['citywide_vacancy_rate']
                if abs(agent_rate - gt_rate) <= 0.02:
                    score += 10
                    feedback.append(f"Citywide vacancy rate correct (~{gt_rate:.3f}) (+10)")
                elif abs(agent_rate - gt_rate) <= 0.05:
                    score += 5
                    feedback.append("Citywide vacancy rate partially correct (+5)")

            if 'highest_vacancy_zone_id' in summary and int(summary['highest_vacancy_zone_id']) == gt_data['highest_vacancy_zone_id']:
                score += 5
                feedback.append("Highest vacancy zone correct (+5)")
                
            if 'lowest_vacancy_zone_id' in summary and int(summary['lowest_vacancy_zone_id']) == gt_data['lowest_vacancy_zone_id']:
                score += 5
                feedback.append("Lowest vacancy zone correct (+5)")

            # Check classifications
            class_ok = True
            for k in ['num_tight_zones', 'num_healthy_zones', 'num_soft_zones']:
                if k in summary and abs(int(summary[k]) - gt_data[k]) > 5:
                    class_ok = False
            
            if class_ok and all(k in summary for k in ['num_tight_zones', 'num_healthy_zones', 'num_soft_zones']):
                score += 10
                feedback.append("Zone classification counts match (+10)")
            else:
                feedback.append("Zone classification counts inaccurate")

        except Exception as e:
            feedback.append(f"Failed to parse JSON: {e}")
        finally:
            os.unlink(json_local)
    else:
        feedback.append("JSON summary file not found")

    # 5. Verify PNG Plot (10 points)
    png_local = copy_raw_from_env(env_info, png_path, '.png')
    if png_local:
        try:
            with open(png_local, 'rb') as f:
                header = f.read(8)
            if header[:4] == b'\x89PNG':
                if os.path.getsize(png_local) >= 5120:  # >= 5KB
                    score += 10
                    feedback.append("Valid PNG visualization created (+10)")
                else:
                    score += 5
                    feedback.append("PNG created but size is suspiciously small (+5)")
            else:
                feedback.append("File is not a valid PNG image")
        except Exception:
            feedback.append("Failed to validate PNG")
        finally:
            os.unlink(png_local)
    else:
        feedback.append("PNG visualization not found")

    # 6. Verify Notebook Code Execution (20 points)
    nb_local = copy_raw_from_env(env_info, nb_path, '.ipynb')
    if nb_local:
        try:
            with open(nb_local, 'r') as f:
                nb = json.load(f)
            
            code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
            num_executed = sum(1 for c in code_cells if c.get('execution_count') is not None)
            
            all_code = ""
            for cell in code_cells:
                src = cell.get('source', '')
                if isinstance(src, list):
                    src = ''.join(src)
                all_code += src + '\n'
            
            # Clean string literals to prevent regex gaming
            clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
            clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

            has_pandas = bool(re.search(r'read_hdf|HDFStore', clean_code))
            has_merge = bool(re.search(r'\.merge|\.join', clean_code))
            has_group = bool(re.search(r'\.groupby', clean_code))
            has_exports = bool(re.search(r'\.to_csv|\.dump|\.to_json', clean_code))

            if num_executed >= 3:
                score += 10
                feedback.append(f"Notebook shows good execution ({num_executed} cells) (+10)")
                
            code_score = sum([has_pandas, has_merge, has_group, has_exports]) * 2.5
            score += code_score
            feedback.append(f"Notebook code structures found: {code_score}/10")
            
        except Exception as e:
            feedback.append(f"Failed to parse Notebook: {e}")
        finally:
            os.unlink(nb_local)
    else:
        feedback.append("Notebook file not found")

    passed = score >= 60 and files_created_during_task >= 2
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": "; ".join(feedback)
    }