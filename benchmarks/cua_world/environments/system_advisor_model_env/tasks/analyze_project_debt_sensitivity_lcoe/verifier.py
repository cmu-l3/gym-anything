#!/usr/bin/env python3
"""Verifier for analyze_project_debt_sensitivity_lcoe task.

Validates the existence of the python script and JSON output.
Crucially, validates the financial logic inside the JSON to ensure the PySAM simulation was actually run and reflects realistic sensitivity impacts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debt_sensitivity(traj, env_info, task_info):
    """Verify debt sensitivity analysis was completed successfully.

    Scoring: 100 points max
    - Files exist and modified during task: 20
    - Script contains PySAM references: 10
    - JSON Schema and Base Config valid: 30
    - Financial Logic: Monotonicity (LCOE increases with interest rate): 25
    - Financial Logic: Leverage Amplification (Spread wider at high debt): 15
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_script = metadata.get('expected_script_path', '/home/ga/Documents/SAM_Projects/debt_sensitivity.py')
    expected_json = metadata.get('expected_json_path', '/home/ga/Documents/SAM_Projects/lcoe_sensitivity.json')
    expected_cap = metadata.get('expected_capacity', 50000)
    expected_cost = metadata.get('expected_cost', 50000000)

    score = 0
    feedback_parts = []
    
    # 1. Check basic file stats exported by bash
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            stats = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read basic stats: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    script_ok = stats.get('script_exists') and stats.get('script_modified_during_task')
    json_ok = stats.get('json_exists') and stats.get('json_modified_during_task')
    
    if script_ok and json_ok:
        score += 20
        feedback_parts.append("Output files created successfully")
    elif json_ok:
        score += 10
        feedback_parts.append("JSON created but script missing/old")
    else:
        feedback_parts.append("Required output files not found or not modified")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Python script contents
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    script_valid = False
    try:
        copy_from_env(expected_script, temp_script.name)
        with open(temp_script.name, 'r') as f:
            content = f.read()
            if 'import PySAM' in content or 'from PySAM' in content:
                script_valid = True
                score += 10
                feedback_parts.append("Script contains PySAM imports")
            else:
                feedback_parts.append("Script missing PySAM imports")
    except Exception:
        feedback_parts.append("Could not read python script")
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # 3. Read and validate the actual JSON results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(expected_json, temp_json.name)
        with open(temp_json.name, 'r') as f:
            sim_data = json.load(f)
    except Exception as e:
        feedback_parts.append("Result JSON is invalid or unreadable")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate schema and base config
    try:
        cap = sim_data.get('system_capacity_kw')
        cost = sim_data.get('total_installed_cost')
        results = sim_data.get('sensitivity_results', {})
        
        config_correct = True
        if cap != expected_cap:
            config_correct = False
            feedback_parts.append(f"Wrong capacity: {cap}")
        if cost != expected_cost:
            config_correct = False
            feedback_parts.append(f"Wrong installed cost: {cost}")
            
        # Check presence of all required keys
        required_debts = ['debt_40_pct', 'debt_60_pct', 'debt_80_pct']
        required_ints = ['int_4.0_pct', 'int_5.0_pct', 'int_6.0_pct', 'int_7.0_pct']
        
        schema_valid = True
        for d in required_debts:
            if d not in results:
                schema_valid = False
                break
            for i in required_ints:
                if i not in results[d] or not isinstance(results[d][i], (int, float)):
                    schema_valid = False
                    break
                    
        if config_correct and schema_valid:
            score += 30
            feedback_parts.append("JSON schema & configuration valid")
        elif schema_valid:
            score += 15
            feedback_parts.append("JSON schema valid but config wrong")
        else:
            feedback_parts.append("JSON schema invalid/missing keys")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
    except Exception as e:
        feedback_parts.append("Error parsing JSON schema")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Financial Logic Verification
    try:
        monotonic_ok = True
        for d in required_debts:
            lcoos = [
                results[d]['int_4.0_pct'],
                results[d]['int_5.0_pct'],
                results[d]['int_6.0_pct'],
                results[d]['int_7.0_pct']
            ]
            # Check strict monotonic increase
            if not (lcoos[0] < lcoos[1] < lcoos[2] < lcoos[3]):
                monotonic_ok = False
                break
        
        if monotonic_ok:
            score += 25
            feedback_parts.append("Financial logic (monotonicity) correct")
        else:
            feedback_parts.append("Failed financial monotonicity check (LCOE must rise with interest rate)")

        # Leverage amplification check: The impact of an interest rate hike is worse when leverage is higher
        spread_40 = results['debt_40_pct']['int_7.0_pct'] - results['debt_40_pct']['int_4.0_pct']
        spread_80 = results['debt_80_pct']['int_7.0_pct'] - results['debt_80_pct']['int_4.0_pct']
        
        # We allow a small tolerance for floating point / model convergence quirks, but it should be distinctly larger
        if spread_80 > spread_40 * 1.05:
            score += 15
            feedback_parts.append("Leverage amplification check passed")
        else:
            feedback_parts.append("Failed leverage amplification check (spread at 80% should be > 40%)")

    except Exception as e:
        feedback_parts.append(f"Error during financial logic checks: {e}")

    # Final scoring evaluation
    passed = score >= 75 and monotonic_ok and schema_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }