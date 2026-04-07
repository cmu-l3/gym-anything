#!/usr/bin/env python3
"""Verifier for gentrification_displacement_risk task."""

import json
import tempfile
import os
import re
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_displacement_risk(traj, env_info, task_info):
    """Verify displacement risk index was built successfully."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cols = metadata.get('expected_csv_columns', [])
    
    score = 0
    max_score = 100
    feedback = []
    
    # Files paths on the remote container
    remote_paths = {
        "manifest": "/tmp/task_result.json",
        "csv": "/home/ga/urbansim_projects/output/displacement_risk.csv",
        "json": "/home/ga/urbansim_projects/output/risk_summary.json",
        "notebook": "/home/ga/urbansim_projects/notebooks/displacement_risk.ipynb",
        "plot": "/home/ga/urbansim_projects/output/displacement_risk_plot.png"
    }
    
    local_files = {}

    # Copy all necessary files
    for name, remote_path in remote_paths.items():
        ext = os.path.splitext(remote_path)[1]
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
        try:
            copy_from_env(remote_path, temp_file.name)
            local_files[name] = temp_file.name
        except Exception as e:
            logger.warning(f"Failed to copy {name} from {remote_path}: {e}")
            local_files[name] = None
    
    try:
        # ==========================================
        # 1. Manifest / General File Check (10 pts)
        # ==========================================
        if local_files.get("manifest"):
            with open(local_files["manifest"], 'r') as f:
                manifest = json.load(f)
            
            files_meta = manifest.get('files', {})
            nb_meta = files_meta.get('notebook', {})
            if nb_meta.get('exists') and nb_meta.get('modified_after_start'):
                score += 10
                feedback.append("Notebook executed during task session.")
            else:
                feedback.append("Notebook not found or not modified during task.")
        
        # ==========================================
        # 2. Notebook Code Analysis (15 pts)
        # ==========================================
        if local_files.get("notebook"):
            with open(local_files["notebook"], 'r') as f:
                nb = json.load(f)
            
            code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
            all_code = ''
            executed_cells = 0
            has_errors = False

            for c in code_cells:
                if c.get('execution_count') is not None:
                    executed_cells += 1
                for out in c.get('outputs', []):
                    if out.get('output_type') == 'error':
                        has_errors = True
                src = c.get('source', '')
                if isinstance(src, list):
                    src = ''.join(src)
                # Strip comments
                lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
                all_code += '\n'.join(lines) + '\n'

            # Anti-gaming regex
            clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
            clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

            if executed_cells >= 3 and not has_errors:
                score += 5
            elif executed_cells > 0:
                score += 2

            if re.search(r'read_hdf|HDFStore', clean_code):
                score += 2
            if re.search(r'merge|join', clean_code):
                score += 3
            if re.search(r'rank\s*\(|percentile', clean_code):
                score += 5
                
            feedback.append(f"Notebook code analysis applied. Executed cells: {executed_cells}")
            
        # ==========================================
        # 3. CSV Validation (35 pts)
        # ==========================================
        csv_valid = False
        if local_files.get("csv"):
            with open(local_files["csv"], 'r') as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames or []
                rows = list(reader)
            
            missing_cols = [c for c in expected_cols if c not in headers]
            if not missing_cols:
                score += 10
                feedback.append("CSV has all required columns.")
                
                if len(rows) > 10:
                    score += 5
                    
                    # Math and logic verification
                    math_correct = True
                    sorted_correct = True
                    filtering_correct = True
                    
                    prev_score = float('inf')
                    for row in rows:
                        try:
                            # Types
                            hh = float(row['total_households'])
                            med_price = float(row['median_sales_price'])
                            pct_low = float(row['pct_low_income'])
                            li_score = float(row['low_income_score'])
                            mp_score = float(row['market_pressure_score'])
                            total_score = float(row['displacement_risk_score'])
                            
                            # Filtering Check
                            if hh < 50 or med_price == 0:
                                filtering_correct = False
                                
                            # Bounds Check
                            if not (0 <= li_score <= 1.0 and 0 <= mp_score <= 1.0):
                                math_correct = False
                                
                            # Sum Check
                            if abs(total_score - (li_score + mp_score)) > 0.01:
                                math_correct = False
                                
                            # Sorted Check (descending)
                            if total_score > prev_score + 0.01:  # small float tolerance
                                sorted_correct = False
                            prev_score = total_score
                                
                        except ValueError:
                            math_correct = False
                            break
                            
                    if filtering_correct:
                        score += 5
                        feedback.append("CSV correctly filtered >= 50 households and valid prices.")
                    else:
                        feedback.append("CSV filtering incorrect (found <50 hh or 0 price).")
                        
                    if math_correct:
                        score += 10
                        feedback.append("CSV calculations (percentiles bounds and sum) are correct.")
                    else:
                        feedback.append("CSV mathematical logic failed.")
                        
                    if sorted_correct:
                        score += 5
                        feedback.append("CSV is correctly sorted descending by displacement_risk_score.")
                        csv_valid = True
                    else:
                        feedback.append("CSV is not sorted descending.")
            else:
                feedback.append(f"CSV missing columns: {missing_cols}")
        else:
            feedback.append("CSV file not found.")

        # ==========================================
        # 4. JSON Summary Validation (20 pts)
        # ==========================================
        json_valid = False
        if local_files.get("json"):
            try:
                with open(local_files["json"], 'r') as f:
                    summary = json.load(f)
                    
                has_keys = all(k in summary for k in ['total_analyzed_zones', 'highest_risk_zone_id', 'mean_displacement_score'])
                if has_keys:
                    score += 10
                    
                    # Cross-validate JSON with CSV if CSV was valid
                    if csv_valid and len(rows) > 0:
                        highest_csv_zone = str(rows[0]['zone_id'])
                        if str(summary['highest_risk_zone_id']) == highest_csv_zone:
                            score += 10
                            json_valid = True
                            feedback.append("JSON highest risk zone matches CSV exactly.")
                        else:
                            feedback.append("JSON highest risk zone does not match top CSV row.")
                    else:
                        score += 5  # Partial credit if CSV was broken but JSON exists
                        feedback.append("JSON keys present.")
                else:
                    feedback.append("JSON missing required keys.")
            except Exception as e:
                feedback.append(f"JSON parsing error: {e}")
        else:
            feedback.append("JSON summary not found.")
            
        # ==========================================
        # 5. Plot Validation (10 pts)
        # ==========================================
        if local_files.get("plot"):
            plot_size = os.path.getsize(local_files["plot"]) / 1024.0
            if plot_size > 15:
                score += 10
                feedback.append(f"Plot valid (size: {plot_size:.1f}KB).")
            elif plot_size > 0:
                score += 5
                feedback.append(f"Plot found but suspiciously small (size: {plot_size:.1f}KB).")
        else:
            feedback.append("Plot file not found.")
            
        # ==========================================
        # 6. VLM Trajectory check (10 pts)
        # ==========================================
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """Look at these chronological screenshots of an agent using Jupyter Lab.
        Did the agent type Python code involving pandas, execute cells, and view a scatter plot or data tables?
        Respond with exactly 'YES' or 'NO'."""
        
        vlm_score = 0
        try:
            if frames:
                resp = query_vlm(images=frames, prompt=vlm_prompt)
                if resp and 'YES' in resp.get('result', '').upper():
                    score += 10
                    vlm_score = 10
                    feedback.append("VLM verified visual trajectory of task execution.")
                else:
                    feedback.append("VLM did not verify sufficient visual workflow progress.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Do not heavily penalize if VLM infrastructure fails, just note it
            feedback.append(f"VLM check skipped/failed: {e}")
            
    finally:
        # Cleanup temporary files
        for temp_path in local_files.values():
            if temp_path and os.path.exists(temp_path):
                os.unlink(temp_path)

    passed = score >= 75 and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }