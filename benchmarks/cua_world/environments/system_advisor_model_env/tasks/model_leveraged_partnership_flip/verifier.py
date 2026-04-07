#!/usr/bin/env python3
"""Verifier for model_leveraged_partnership_flip task.

Evaluates the agent's ability to model a Leveraged Partnership Flip
utility-scale solar project via PySAM.
"""

import json
import tempfile
import os

def verify_model_leveraged_partnership_flip(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Read the summary from export_result.sh
    temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_summary.name)
        with open(temp_summary.name, 'r') as f:
            summary = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result summary: {e}"}
    finally:
        if os.path.exists(temp_summary.name):
            os.unlink(temp_summary.name)

    score = 0
    feedback_parts = []
    
    # Check file existence and modification
    if summary.get("json_exists"):
        score += 10
        feedback_parts.append("Results JSON exists")
    else:
        feedback_parts.append("Results JSON NOT found")

    if summary.get("json_modified") or summary.get("py_modified"):
        score += 10
        feedback_parts.append("Files created/modified during task")
    
    if summary.get("py_exists") and summary.get("pysam_imported"):
        score += 10
        feedback_parts.append("Script exists and uses PySAM")
    elif summary.get("py_exists"):
        feedback_parts.append("Script exists but PySAM imports not detected")
        score += 3
        
    # Read and validate the actual JSON results file
    agent_json_data = {}
    if summary.get("json_exists"):
        temp_agent_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/home/ga/Documents/SAM_Projects/levpartflip_results.json", temp_agent_json.name)
            with open(temp_agent_json.name, 'r') as f:
                agent_json_data = json.load(f)
        except Exception:
            feedback_parts.append("Agent JSON is malformed/unreadable")
        finally:
            if os.path.exists(temp_agent_json.name):
                os.unlink(temp_agent_json.name)
                
    # Read the agent's Python script for secondary validation (location)
    script_content = ""
    if summary.get("py_exists"):
        temp_agent_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env("/home/ga/Documents/SAM_Projects/levpartflip_model.py", temp_agent_py.name)
            with open(temp_agent_py.name, 'r') as f:
                script_content = f.read().lower()
            
            # Script references correct location (Daggett or lat/lon)
            if "daggett" in script_content or ("34.8" in script_content and "-116.7" in script_content):
                score += 4
                feedback_parts.append("Script location correct")
        except Exception:
            pass
        finally:
            if os.path.exists(temp_agent_py.name):
                os.unlink(temp_agent_py.name)

    # Required JSON fields validation
    required_keys = [
        "system_capacity_kw", "annual_energy_year1_kwh", "capacity_factor_pct",
        "lcoe_nominal_cents_per_kwh", "lcoe_real_cents_per_kwh", "ppa_price_year1_cents_per_kwh",
        "total_installed_cost_dollars", "flip_year", "tax_investor_irr_pct",
        "developer_irr_pct", "project_npv_dollars", "debt_fraction_pct"
    ]
    
    if agent_json_data:
        missing_keys = [k for k in required_keys if k not in agent_json_data or not isinstance(agent_json_data[k], (int, float))]
        if not missing_keys:
            score += 10
            feedback_parts.append("All 12 required JSON fields present")
        else:
            feedback_parts.append(f"Missing/invalid fields: {len(missing_keys)}")
            score += int((12 - len(missing_keys)) / 12 * 10)
            
        # Helper safely gets float or 0
        def safe_get(key):
            try:
                return float(agent_json_data.get(key, -9999))
            except (ValueError, TypeError):
                return -9999
        
        annual_energy = safe_get("annual_energy_year1_kwh")
        if metadata.get("annual_energy_min") <= annual_energy <= metadata.get("annual_energy_max"):
            score += 10
            feedback_parts.append("Annual energy in range")
            
        capacity_factor = safe_get("capacity_factor_pct")
        if metadata.get("cf_min") <= capacity_factor <= metadata.get("cf_max"):
            score += 8
            feedback_parts.append("CF in range")
            
        system_capacity = safe_get("system_capacity_kw")
        # Mathematical consistency: CF = energy / (capacity * 8760) * 100
        if system_capacity > 0:
            calc_cf = (annual_energy / (system_capacity * 8760)) * 100
            if abs(calc_cf - capacity_factor) <= 2.0:
                score += 7
                feedback_parts.append("CF consistent with energy")
                
        # System capacity check
        if abs(system_capacity - metadata.get("expected_capacity_kw")) <= 500:
            score += 3
            feedback_parts.append("System capacity correct")
            
        lcoe_nominal = safe_get("lcoe_nominal_cents_per_kwh")
        if metadata.get("lcoe_nominal_min") <= lcoe_nominal <= metadata.get("lcoe_nominal_max"):
            score += 8
            feedback_parts.append("LCOE nominal in range")
            
        installed_cost = safe_get("total_installed_cost_dollars")
        if abs(installed_cost - metadata.get("cost_target")) <= 1100000: # Within 5%
            score += 5
            feedback_parts.append("Installed cost correct")
            
        flip_year = safe_get("flip_year")
        if metadata.get("flip_year_min") <= flip_year <= metadata.get("flip_year_max"):
            score += 8
            feedback_parts.append("Flip year in range")
            
        tax_investor_irr = safe_get("tax_investor_irr_pct")
        if metadata.get("tax_investor_irr_min") <= tax_investor_irr <= metadata.get("tax_investor_irr_max"):
            score += 7
            feedback_parts.append("Tax Investor IRR in range")

    # Determine passing criteria
    # Must score >= 60 and have a valid results file
    key_criteria_met = summary.get("json_exists") and summary.get("py_exists")
    passed = (score >= 60) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }