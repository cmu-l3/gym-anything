#!/usr/bin/env python3
"""
Verifier for Parametric Yield Modeling task.

Criteria:
1. Process 'Dynamic Metal Stamping' created (DB check)
2. Parameter 'scrap_rate' defined (DB check)
3. Formulas using 'scrap_rate' present in exchanges (DB check - CRITICAL)
4. Result files exported for both 20% and 10% cases
5. Result values reflect the parameter change (logic check)

Scoring:
- Process exists: 10 pts
- Parameter exists: 20 pts
- Formulas used: 40 pts (Anti-gaming: must use formulas, not hardcoded values)
- Result CSVs exist: 20 pts (10 each)
- Logical consistency (20% file has higher impact than 10%): 10 pts
"""

import json
import os
import tempfile
import logging
import csv

logger = logging.getLogger(__name__)

def parse_first_numeric_value(file_path):
    """Finds the first numeric value in a CSV file (likely the GWP result)."""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            # Try parsing as CSV first
            reader = csv.reader(f)
            for row in reader:
                for cell in row:
                    try:
                        val = float(cell)
                        if val > 0: return val
                    except ValueError:
                        continue
            
            # Fallback: simple text scan
            f.seek(0)
            content = f.read()
            import re
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            for n in numbers:
                try:
                    val = float(n)
                    if val > 0: return val
                except ValueError:
                    continue
    except Exception as e:
        logger.warning(f"Error parsing file {file_path}: {e}")
    return None

def verify_parametric_yield_modeling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 1. DB Checks
    if result.get("process_found"):
        score += 10
        feedback.append("Process created")
    else:
        feedback.append("Process 'Dynamic Metal Stamping' not found")

    if result.get("parameter_found"):
        score += 20
        feedback.append("Parameter 'scrap_rate' defined")
    else:
        feedback.append("Parameter 'scrap_rate' not found")

    if result.get("formula_found"):
        score += 40
        feedback.append("Formulas used correctly")
    else:
        feedback.append("Formulas NOT found in exchanges (CRITICAL)")

    # 2. File Checks
    file_20_ok = result.get("file_20_exists") and result.get("file_20_size", 0) > 50
    file_10_ok = result.get("file_10_exists") and result.get("file_10_size", 0) > 50

    if file_20_ok: score += 10
    if file_10_ok: score += 10
    
    if file_20_ok and file_10_ok:
        feedback.append("Both result files exported")
        
        # 3. Logical Consistency Check
        # Download files to verify values
        temp_20 = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        temp_10 = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/home/ga/LCA_Results/yield_result_20.csv", temp_20.name)
            copy_from_env("/home/ga/LCA_Results/yield_result_10.csv", temp_10.name)
            
            val_20 = parse_first_numeric_value(temp_20.name)
            val_10 = parse_first_numeric_value(temp_10.name)
            
            if val_20 is not None and val_10 is not None:
                # With 20% scrap, input is 1.25. With 10% scrap, input is 1.11.
                # Result 20 should be > Result 10
                if val_20 > val_10 * 1.05: # Allow small margin, expect at least 5% diff
                    score += 10
                    feedback.append(f"Logic valid: 20% scrap result ({val_20:.2e}) > 10% result ({val_10:.2e})")
                else:
                    feedback.append(f"Logic suspicious: 20% result ({val_20:.2e}) not significantly higher than 10% ({val_10:.2e})")
            else:
                feedback.append("Could not parse numeric results from files")
        except Exception as e:
            feedback.append(f"Error checking file content: {e}")
        finally:
            if os.path.exists(temp_20.name): os.unlink(temp_20.name)
            if os.path.exists(temp_10.name): os.unlink(temp_10.name)
    else:
        feedback.append("One or both result files missing")

    # Pass threshold: Must have Process + Parameter + Formula (70 pts)
    # The files are secondary, but formula usage is critical for this specific task
    passed = (score >= 70) and result.get("formula_found")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }