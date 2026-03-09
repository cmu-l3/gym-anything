#!/usr/bin/env python3
"""
Verifier for xfoil_polar_analysis task.

Checks:
1. Polar output file exists, is valid tabular data, and covers requested alpha range.
2. Summary file exists and contains extracted metrics (Cl_max, Cd_min, L/D_max).
3. Data consistency: Metrics in summary match the polar data.
4. Physics sanity check: Values are within realistic ranges for airfoils at Re=500k.
5. Anti-gaming: Files created during task session.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_polar_file(content):
    """
    Parses QBlade/XFoil polar export format.
    Expected columns usually include: Alpha, Cl, Cd, Cm, etc.
    Returns a list of dicts: [{'alpha': float, 'Cl': float, 'Cd': float}, ...]
    """
    data = []
    lines = content.splitlines()
    
    # Simple heuristic to find data start: look for line starting with number
    # QBlade exports often have headers with variables names
    
    header_found = False
    headers = []
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Try to detect header line
        if 'Alpha' in line or 'Cl' in line or 'Cd' in line:
            # Normalize headers
            parts = re.split(r'\s+', line)
            headers = [h.strip() for h in parts]
            header_found = True
            continue
            
        # Parse data lines
        if re.match(r'^-?\d', line):
            parts = re.split(r'\s+', line)
            if len(parts) >= 3:
                try:
                    row = {}
                    # If we found headers, try to map them. 
                    # Otherwise assume standard XFoil order: Alpha, Cl, Cd, Cdp, Cm...
                    values = [float(p) for p in parts]
                    
                    if header_found and len(headers) == len(values):
                        for i, h in enumerate(headers):
                            row[h] = values[i]
                            # Normalized keys
                            if 'Alpha' in h: row['alpha'] = values[i]
                            if 'Cl' == h or 'CL' == h: row['Cl'] = values[i]
                            if 'Cd' == h or 'CD' == h: row['Cd'] = values[i]
                    else:
                        # Fallback to index based (standard XFoil)
                        # 0: Alpha, 1: Cl, 2: Cd
                        row['alpha'] = values[0]
                        row['Cl'] = values[1]
                        row['Cd'] = values[2]
                    
                    data.append(row)
                except ValueError:
                    continue
                    
    return data

def parse_summary_file(content):
    """
    Parses the user-generated summary file.
    Expected format: Key=<value> at alpha=<value>
    Returns a dict: {'Cl_max': {'val': v, 'alpha': a}, ...}
    """
    result = {}
    patterns = {
        'Cl_max': r'Cl_max\s*=\s*([\d\.-]+).*alpha\s*=\s*([\d\.-]+)',
        'Cd_min': r'Cd_min\s*=\s*([\d\.-]+).*alpha\s*=\s*([\d\.-]+)',
        'L/D_max': r'L/D_max\s*=\s*([\d\.-]+).*alpha\s*=\s*([\d\.-]+)'
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, content, re.IGNORECASE)
        if match:
            try:
                result[key] = {
                    'value': float(match.group(1)),
                    'alpha': float(match.group(2))
                }
            except ValueError:
                pass
    return result

def verify_xfoil_polar_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Check Polar File Existence & Creation (20 pts)
    polar_path = task_result.get('polar_path', '')
    if task_result.get('polar_file_exists') and task_result.get('polar_created_during_task'):
        score += 20
        feedback.append("Polar file created successfully.")
        
        # Retrieve content
        polar_content = ""
        temp_polar = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(polar_path, temp_polar.name)
            with open(temp_polar.name, 'r') as f:
                polar_content = f.read()
        except Exception as e:
            feedback.append(f"Error reading polar file: {e}")
        finally:
            if os.path.exists(temp_polar.name):
                os.unlink(temp_polar.name)
        
        # 3. Analyze Polar Data (30 pts)
        data = parse_polar_file(polar_content)
        if len(data) > 10:
            score += 10
            feedback.append(f"Polar file contains {len(data)} data points.")
            
            # Check Alpha Range (-5 to 15 requested)
            alphas = [r['alpha'] for r in data if 'alpha' in r]
            if alphas:
                min_a, max_a = min(alphas), max(alphas)
                if min_a <= -4.0 and max_a >= 14.0:
                    score += 10
                    feedback.append(f"Alpha range covers {min_a:.1f} to {max_a:.1f} (Target: -5 to 15).")
                else:
                    feedback.append(f"Alpha range incomplete: {min_a:.1f} to {max_a:.1f}.")
            
            # Check Physics (Re=500k typical values)
            # Cl should be roughly -1.0 to 2.0
            # Cd should be positive
            cls = [r['Cl'] for r in data if 'Cl' in r]
            cds = [r['Cd'] for r in data if 'Cd' in r]
            
            valid_physics = True
            if cls and (max(cls) > 2.5 or min(cls) < -1.5): valid_physics = False
            if cds and (min(cds) < 0 or max(cds) > 1.0): valid_physics = False
            
            if valid_physics and cls and cds:
                score += 10
                feedback.append("Aerodynamic coefficients are within physical bounds.")
            else:
                feedback.append("Aerodynamic data values seem unrealistic.")
        else:
            feedback.append("Polar file contains insufficient data.")
            data = [] # Reset for consistency check
    else:
        feedback.append("Polar output file not found or not created during task.")
        data = []

    # 4. Check Summary File (20 pts)
    summary_path = task_result.get('summary_path', '')
    summary_data = {}
    if task_result.get('summary_file_exists'):
        score += 10
        feedback.append("Summary file exists.")
        
        temp_sum = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(summary_path, temp_sum.name)
            with open(temp_sum.name, 'r') as f:
                summary_content = f.read()
                summary_data = parse_summary_file(summary_content)
        except Exception as e:
            feedback.append(f"Error reading summary file: {e}")
        finally:
            if os.path.exists(temp_sum.name):
                os.unlink(temp_sum.name)
        
        if len(summary_data) == 3:
            score += 10
            feedback.append("Summary file format correct (found 3 metrics).")
        else:
            feedback.append(f"Summary file format issue: found {len(summary_data)}/3 metrics.")
    else:
        feedback.append("Summary file not found.")

    # 5. Consistency Check (30 pts)
    # Compare summary values against calculated values from polar file
    if data and summary_data:
        # Calculate actual max/min from data
        try:
            actual_cl_max_row = max(data, key=lambda x: x['Cl'])
            actual_cd_min_row = min(data, key=lambda x: x['Cd'])
            
            # Calculate L/D
            for r in data:
                r['L_D'] = r['Cl'] / r['Cd'] if r['Cd'] != 0 else 0
            actual_ld_max_row = max(data, key=lambda x: x['L_D'])
            
            # Check Cl_max (10 pts)
            rep_cl = summary_data.get('Cl_max', {})
            if rep_cl:
                cl_err = abs(rep_cl['value'] - actual_cl_max_row['Cl'])
                alpha_err = abs(rep_cl['alpha'] - actual_cl_max_row['alpha'])
                if cl_err < 0.05 and alpha_err < 1.0:
                    score += 10
                    feedback.append("Cl_max matches polar data.")
                else:
                    feedback.append(f"Cl_max mismatch: Reported {rep_cl['value']} vs Actual {actual_cl_max_row['Cl']}.")

            # Check Cd_min (10 pts)
            rep_cd = summary_data.get('Cd_min', {})
            if rep_cd:
                cd_err = abs(rep_cd['value'] - actual_cd_min_row['Cd'])
                if cd_err < 0.005: # Stricter for small number
                    score += 10
                    feedback.append("Cd_min matches polar data.")
                else:
                    feedback.append(f"Cd_min mismatch: Reported {rep_cd['value']} vs Actual {actual_cd_min_row['Cd']}.")

            # Check L/D max (10 pts)
            rep_ld = summary_data.get('L/D_max', {})
            if rep_ld:
                ld_err = abs(rep_ld['value'] - actual_ld_max_row['L_D'])
                if ld_err < 5.0: # Allow some tolerance for ratio
                    score += 10
                    feedback.append("L/D_max matches polar data.")
                else:
                    feedback.append(f"L/D_max mismatch: Reported {rep_ld['value']} vs Actual {actual_ld_max_row['L_D']:.1f}.")

        except KeyError as e:
            feedback.append(f"Consistency check failed due to missing data columns: {e}")
    elif score >= 50:
        feedback.append("Skipping consistency check (missing data).")

    # Final tally
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }