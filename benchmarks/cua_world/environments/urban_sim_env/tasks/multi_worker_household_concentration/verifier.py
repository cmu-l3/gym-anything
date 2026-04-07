#!/usr/bin/env python3
"""Verifier for multi_worker_household_concentration task."""

import json
import os
import re
import tempfile
import sys
import logging

# We import the provided utilities inside the function to ensure path availability, 
# or prepend the workspace path if needed.
sys.path.insert(0, '/workspace')
try:
    from utils.urbansim_verification_utils import (
        copy_file_from_env,
        validate_notebook_has_code,
        validate_csv_output,
        validate_png_file,
        build_verifier_result
    )
except ImportError:
    logging.warning("Could not import urbansim_verification_utils directly.")

def verify_worker_demographics(traj, env_info, task_info):
    """Verify multi_worker_household_concentration task.

    Scoring (100 points total):
    - Notebook Execution & Analysis (10 pts)
    - Citywide JSON Output (20 pts)
    - CSV Columns & Structure (20 pts)
    - CSV Data Filtering (20 pts)
    - Relational Accuracy / Data logic (15 pts)
    - Visualization Evidence (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_cols = metadata.get('expected_csv_columns', [])
    expected_json_keys = metadata.get('expected_json_keys', [])

    score = 0
    feedback = []

    # Helper wrapper for copy_file_from_env to handle missing files gracefully
    def fetch_file(remote_path, suffix='.tmp'):
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
            copy_from_env(remote_path, temp_file.name)
            if os.path.getsize(temp_file.name) == 0:
                os.unlink(temp_file.name)
                return None
            return temp_file.name
        except Exception:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
            return None

    # Fetch exported file metadata
    meta_json_path = fetch_file("/tmp/task_result.json", ".json")
    if meta_json_path:
        with open(meta_json_path, 'r') as f:
            export_meta = json.load(f)
        os.unlink(meta_json_path)
    else:
        export_meta = {"files": {}}

    # =======================================================
    # 1. Check Notebook (10 points)
    # =======================================================
    nb_path = fetch_file(metadata.get('expected_notebook_path'), '.ipynb')
    nb_score = 0
    if nb_path:
        # Check code patterns
        patterns = [
            ('has_pandas', r'import pandas|from pandas'),
            ('has_merge', r'\.merge\s*\(|\.join\s*\('),
            ('has_group', r'\.groupby\s*\('),
            ('has_to_csv', r'\.to_csv\s*\(')
        ]
        
        # Manual AST/Execution check (similar to urbansim_verification_utils)
        try:
            with open(nb_path, 'r') as f:
                nb_data = json.load(f)
            
            code_cells = [c for c in nb_data.get('cells', []) if c.get('cell_type') == 'code']
            num_exec = sum(1 for c in code_cells if c.get('execution_count') is not None)
            
            has_errors = False
            for cell in code_cells:
                for out in cell.get('outputs', []):
                    if out.get('output_type') == 'error':
                        has_errors = True
                        break

            if num_exec >= 4 and not has_errors:
                nb_score += 6
                feedback.append("Notebook executed successfully without errors.")
            elif num_exec > 0:
                nb_score += 3
                feedback.append(f"Notebook partially executed ({num_exec} cells).")
            else:
                feedback.append("Notebook has no executed cells.")
                
            code_text = "\n".join(["".join(c.get('source', [])) for c in code_cells])
            if "households" in code_text and "buildings" in code_text:
                nb_score += 4
        except Exception as e:
            feedback.append(f"Error parsing notebook: {e}")
        finally:
            os.unlink(nb_path)
    else:
        feedback.append("Notebook not found.")
    
    score += nb_score

    # =======================================================
    # 2. Check Citywide JSON Output (20 points)
    # =======================================================
    json_path = fetch_file(metadata.get('expected_json_path'), '.json')
    json_score = 0
    if json_path:
        try:
            with open(json_path, 'r') as f:
                city_data = json.load(f)
            
            keys_present = [k for k in expected_json_keys if k in city_data]
            if len(keys_present) == len(expected_json_keys):
                json_score += 10
                feedback.append("JSON output contains all required keys.")
                
                # Logical numerical validation
                try:
                    inc_0 = float(city_data['avg_income_zero_worker'])
                    inc_1 = float(city_data['avg_income_single_worker'])
                    inc_m = float(city_data['avg_income_multi_worker'])
                    total_hh = int(city_data['citywide_total_households'])
                    
                    if total_hh > 100000:  # SF has hundreds of thousands of households
                        json_score += 5
                    
                    if inc_m > inc_0: # logically, multi-worker HHs make more than 0-worker HHs
                        json_score += 5
                        feedback.append("Citywide income logic is sound (Multi > Zero).")
                except (ValueError, TypeError):
                    feedback.append("JSON values are not proper numbers.")
            else:
                feedback.append(f"JSON missing keys. Found: {keys_present}")
        except Exception as e:
            feedback.append(f"JSON output is invalid: {e}")
        finally:
            os.unlink(json_path)
    else:
        feedback.append("Citywide JSON output not found.")
        
    score += json_score

    # =======================================================
    # 3. Check CSV Columns & Structure (20 points)
    # 4. Check CSV Data Filtering (20 points)
    # 5. Check Relational Accuracy (15 points)
    # =======================================================
    csv_path = fetch_file(metadata.get('expected_csv_path'), '.csv')
    csv_col_score = 0
    csv_filter_score = 0
    csv_logic_score = 0
    
    if csv_path:
        try:
            import csv
            with open(csv_path, 'r') as f:
                reader = csv.DictReader(f)
                columns = reader.fieldnames or []
                rows = list(reader)
                
            # Column Check (20 pts)
            col_lower = [c.lower() for c in columns]
            expected_lower = [c.lower() for c in expected_csv_cols]
            missing_cols = set(expected_lower) - set(col_lower)
            
            if not missing_cols:
                csv_col_score += 20
                feedback.append("CSV contains all expected columns.")
            else:
                csv_col_score += max(0, 20 - (len(missing_cols) * 4))
                feedback.append(f"CSV missing columns: {missing_cols}")
                
            # Rows Check
            if len(rows) > 0:
                # Filtering Check (20 pts)
                # Check if filter condition (>=50 total_households) was applied
                valid_filter = True
                logic_math_ok = True
                
                for row in rows:
                    try:
                        # Find the correct column keys ignoring case
                        th_key = next((k for k in row.keys() if k.lower() == 'total_households'), None)
                        if th_key and float(row[th_key]) < 50:
                            valid_filter = False
                        
                        # Logic check: sum of categories == total
                        z_key = next((k for k in row.keys() if k.lower() == 'zero_worker_count'), None)
                        s_key = next((k for k in row.keys() if k.lower() == 'single_worker_count'), None)
                        m_key = next((k for k in row.keys() if k.lower() == 'multi_worker_count'), None)
                        p_key = next((k for k in row.keys() if k.lower() == 'pct_multi_worker'), None)
                        
                        if z_key and s_key and m_key and th_key:
                            total = float(row[th_key])
                            parts_sum = float(row[z_key]) + float(row[s_key]) + float(row[m_key])
                            if abs(total - parts_sum) > 1: # slight tolerance
                                logic_math_ok = False
                                
                        if p_key and m_key and th_key:
                            pct_calc = (float(row[m_key]) / float(row[th_key])) * 100
                            # allow fractional pct or 0-1 range if they didn't multiply by 100
                            pct_val = float(row[p_key])
                            if abs(pct_calc - pct_val) > 2.0 and abs((pct_calc/100) - pct_val) > 0.05:
                                logic_math_ok = False
                                
                    except (ValueError, TypeError):
                        pass

                if valid_filter:
                    csv_filter_score += 20
                    feedback.append("CSV successfully filtered to >= 50 households per zone.")
                else:
                    csv_filter_score += 5
                    feedback.append("CSV contains zones with < 50 households (filter not applied properly).")
                    
                if logic_math_ok:
                    csv_logic_score += 15
                    feedback.append("CSV relational aggregations and math calculations are accurate.")
                else:
                    csv_logic_score += 5
                    feedback.append("CSV aggregations have math/summation errors.")
                    
            else:
                feedback.append("CSV is empty.")
                
        except Exception as e:
            feedback.append(f"Error validating CSV: {e}")
        finally:
            os.unlink(csv_path)
    else:
        feedback.append("Zone worker profiles CSV not found.")
        
    score += csv_col_score + csv_filter_score + csv_logic_score

    # =======================================================
    # 6. Check Visualization Evidence (15 points)
    # =======================================================
    png_path = fetch_file(metadata.get('expected_plot_path'), '.png')
    plot_score = 0
    if png_path:
        try:
            # Basic validation
            size_kb = os.path.getsize(png_path) / 1024
            with open(png_path, 'rb') as f:
                header = f.read(8)
                is_png = header[:4] == b'\x89PNG'
                
            if is_png and size_kb >= 10:
                plot_score += 15
                feedback.append(f"Valid scatter plot found ({size_kb:.1f}KB).")
            elif is_png:
                plot_score += 8
                feedback.append(f"Plot found but suspiciously small ({size_kb:.1f}KB).")
            else:
                feedback.append("Plot file is not a valid PNG.")
        except Exception as e:
            feedback.append(f"Error reading plot file: {e}")
        finally:
            os.unlink(png_path)
    else:
        feedback.append("Scatter plot PNG not found.")
        
    score += plot_score

    # Anti-gaming: Ensure files were actually modified during task execution
    file_meta = export_meta.get('files', {})
    files_modified = any(v.get('modified_after_start', False) for v in file_meta.values())
    if not files_modified and score > 0:
        score = int(score * 0.5)
        feedback.append("PENALTY: Output files were not modified during this session (possible pre-existing files).")

    # Determine passing state
    passed = score >= 70

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "subscores": {
            "notebook": nb_score,
            "json": json_score,
            "csv_cols": csv_col_score,
            "csv_filter": csv_filter_score,
            "csv_logic": csv_logic_score,
            "plot": plot_score
        }
    }