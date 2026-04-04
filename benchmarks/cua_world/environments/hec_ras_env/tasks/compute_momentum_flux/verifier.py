#!/usr/bin/env python3
import json
import os
import csv
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_momentum_flux(traj, env_info, task_info):
    """
    Verify the momentum flux calculation task.
    
    Checks:
    1. Files (Script, CSV, Report) created during task.
    2. CSV structure (columns).
    3. Physical validity of calculations (M approx rho*Q*V).
    4. Summary report content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_columns = set(c.lower() for c in metadata.get('expected_columns', []))
    
    score = 0
    feedback = []
    
    # 1. Retrieve metadata result
    task_result = {}
    with tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
        finally:
            try: os.unlink(tmp.name)
            except: pass

    # 2. Check file existence/creation (30 pts)
    files_created = 0
    if task_result.get('script_status') == 'created_during_task':
        score += 10
        files_created += 1
        feedback.append("Script created.")
    else:
        feedback.append("Script missing or not created during task.")

    if task_result.get('csv_status') == 'created_during_task':
        score += 10
        files_created += 1
        feedback.append("CSV created.")
    else:
        feedback.append("CSV missing or not created during task.")

    if task_result.get('report_status') == 'created_during_task':
        score += 10
        files_created += 1
        feedback.append("Report created.")
    else:
        feedback.append("Report missing or not created during task.")

    # If critical CSV is missing, fail early
    if task_result.get('csv_status') != 'created_during_task':
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 3. specific CSV content verification (40 pts)
    csv_valid = False
    row_count = 0
    
    with tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp_csv:
        try:
            copy_from_env("/tmp/export_momentum_flux.csv", tmp_csv.name)
            
            # Read CSV
            with open(tmp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                reader = csv.DictReader(f)
                
                # Check columns
                if reader.fieldnames:
                    found_cols = set(c.lower().strip() for c in reader.fieldnames)
                    missing = [c for c in expected_columns if c not in found_cols]
                    
                    if not missing:
                        score += 15
                        feedback.append("CSV columns correct.")
                    else:
                        feedback.append(f"CSV missing columns: {missing}")
                
                # Check rows and physics
                rows = list(reader)
                row_count = len(rows)
                
                if row_count >= 5:
                    score += 10
                    feedback.append(f"Found {row_count} rows of data.")
                    
                    # Check Physics: M = rho * Q * V
                    # We check if M / (Q*V) is roughly constant (approx 1.94 or 1000)
                    densities = []
                    valid_values = True
                    
                    for row in rows:
                        try:
                            # Handle potential whitespace or casting errors
                            q = float(row.get('Q_peak', row.get('q_peak', 0)))
                            v = float(row.get('Velocity', row.get('velocity', 0)))
                            m = float(row.get('M_dynamic', row.get('m_dynamic', 0)))
                            sf = float(row.get('Specific_Force', row.get('specific_force', 0)))
                            
                            if q <= 0 or v <= 0: continue
                            
                            calculated_rho = m / (q * v)
                            densities.append(calculated_rho)
                            
                            if m <= 0 or sf <= 0:
                                valid_values = False
                        except ValueError:
                            valid_values = False
                    
                    if valid_values and densities:
                        score += 5
                        feedback.append("Values are positive numerical data.")
                        
                        # Check consistency of density used
                        avg_rho = sum(densities) / len(densities)
                        # Standard deviation
                        variance = sum((x - avg_rho) ** 2 for x in densities) / len(densities)
                        std_dev = math.sqrt(variance)
                        
                        # Allow 10% variation (floating point or minor time alignment diffs)
                        if std_dev < (0.1 * avg_rho):
                            score += 10
                            feedback.append(f"Physics check passed: Consistent density used (~{avg_rho:.2f}).")
                            csv_valid = True
                        else:
                            feedback.append(f"Physics check warning: Inconsistent density calculations (Avg: {avg_rho:.2f}, StdDev: {std_dev:.2f}).")
                    else:
                        feedback.append("Data validation failed (non-numeric or non-positive values found).")
                else:
                    feedback.append("CSV has too few rows (expected > 5).")

        except Exception as e:
            feedback.append(f"Error analyzing CSV: {e}")
        finally:
            try: os.unlink(tmp_csv.name)
            except: pass

    # 4. Report Content (20 pts)
    with tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp_rpt:
        try:
            copy_from_env("/tmp/export_momentum_summary.txt", tmp_rpt.name)
            with open(tmp_rpt.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                
                if "max" in content and any(char.isdigit() for char in content):
                    score += 10
                    feedback.append("Report contains 'max' and numerical values.")
                else:
                    feedback.append("Report content missing expected keywords/numbers.")
                    
                # Bonus: Check if it mentions specific force or momentum
                if "force" in content or "momentum" in content:
                    score += 10
        except Exception as e:
            feedback.append(f"Error analyzing report: {e}")
        finally:
            try: os.unlink(tmp_rpt.name)
            except: pass
            
    # 5. Script Analysis (10 pts)
    with tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp_py:
        try:
            copy_from_env("/tmp/export_compute_script.py", tmp_py.name)
            with open(tmp_py.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                if "h5py" in content or "rashdf" in content:
                    score += 10
                    feedback.append("Script imports HDF5 library.")
        except:
            pass
        finally:
            try: os.unlink(tmp_py.name)
            except: pass

    return {
        "passed": score >= 60 and csv_valid,
        "score": score,
        "feedback": "\n".join(feedback)
    }