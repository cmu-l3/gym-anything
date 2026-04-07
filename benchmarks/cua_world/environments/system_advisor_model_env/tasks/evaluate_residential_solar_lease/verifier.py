#!/usr/bin/env python3
"""Verifier for evaluate_residential_solar_lease task.

Uses independent file verification, parameter extraction, and physics/finance cross-checks.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _physics_sanity_check(dc_size_kw, annual_kwh, location):
    """Check if reported energy is physically plausible for Denver."""
    if dc_size_kw <= 0 or annual_kwh <= 0:
        return False, "Missing or negative values"

    cf = annual_kwh / (dc_size_kw * 8760) * 100

    location_lower = location.lower()
    
    # Denver typically gets between 15% and 19% CF for fixed tilt
    cf_min, cf_max = 13.0, 21.0

    if cf_min <= cf <= cf_max:
        return True, f"CF={cf:.1f}% plausible for {location}"
    else:
        return False, f"CF={cf:.1f}% NOT plausible for {location} (expected {cf_min}-{cf_max}%)"

def _finance_consistency_check(annual_kwh, ppa_price_cents, year1_ppa_cost, year1_elec_value, year1_savings):
    """Check if the internal logic of the financial outputs is consistent."""
    messages = []
    consistent = True
    
    if any(v is None for v in [annual_kwh, ppa_price_cents, year1_ppa_cost, year1_elec_value, year1_savings]):
        return False, "Missing financial values"

    # 1. Check PPA cost = annual_energy * ppa_price
    expected_ppa_cost = annual_kwh * (ppa_price_cents / 100.0)
    if abs(expected_ppa_cost - year1_ppa_cost) > max(10, expected_ppa_cost * 0.05):
        consistent = False
        messages.append(f"PPA cost mismatch (Expected ~${expected_ppa_cost:.2f}, Got ${year1_ppa_cost:.2f})")
    
    # 2. Check Savings = Electricity Value - PPA Cost
    # Note: Utility value might have fixed charges affecting the net savings mathematically depending on module setup,
    # but strictly speaking: Net Savings = Without Solar Bill - With Solar Bill + PPA Cost... 
    # Usually year1_savings is roughly year1_elec_value - year1_ppa_cost.
    expected_savings = year1_elec_value - year1_ppa_cost
    if abs(expected_savings - year1_savings) > max(50, expected_savings * 0.1):
        # We allow a slightly larger margin here because utility rate fixed charges can distort the exact subtraction
        consistent = False
        messages.append(f"Savings logic mismatch (Expected ~${expected_savings:.2f}, Got ${year1_savings:.2f})")
        
    if consistent:
        return True, "Financial logic consistent"
    else:
        return False, " | ".join(messages)

def _independent_file_check(copy_from_env):
    """Copy the agent's actual output file and independently verify its contents."""
    path = "/home/ga/Documents/SAM_Projects/denver_solar_lease_results.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)
            
        return True, raw
    except Exception as e:
        logger.error(f"Failed to read/parse output JSON: {e}")
        return False, {}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

def verify_evaluate_residential_solar_lease(traj, env_info, task_info):
    """Verify residential solar lease evaluation was completed successfully.

    Scoring: 100 points max
    - File exists & valid JSON: 15
    - Created during task: 10
    - All required fields present: 10
    - Location & config params correct: 10
    - PPA input params correct: 5
    - Annual energy & CF in range (physics check): 20
    - Year 1 PPA cost consistent: 10
    - Year 1 savings consistent & positive: 10
    - NPV / LCOE plausible: 10
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Get basic export metadata
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: File exists and is valid JSON (15 pts)
    # We do this by pulling the actual file.
    file_valid, raw_json = _independent_file_check(copy_from_env)
    
    if file_valid and result.get('file_exists'):
        score += 15
        feedback_parts.append("File exists and is valid JSON")
    else:
        feedback_parts.append("File NOT found or invalid JSON")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: File created during task (10 pts)
    if result.get('file_modified'):
        score += 10
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("File not modified during task (possible gaming)")

    # Criterion 3: All required fields present (10 pts)
    if result.get('has_required_keys'):
        score += 10
        feedback_parts.append("All required fields present")
    else:
        missing = result.get('missing_keys', '')
        feedback_parts.append(f"Missing keys:{missing}")

    # Extract specific values safely
    def get_num(key, default=None):
        try:
            val = raw_json.get(key)
            return float(val) if val is not None else default
        except:
            return default

    loc = str(raw_json.get('location', '')).lower()
    lat = get_num('latitude')
    lon = get_num('longitude')
    sys_size = get_num('system_size_kw')
    tilt = get_num('tilt_deg')
    az = get_num('azimuth_deg')
    
    ppa_price = get_num('ppa_price_cents_per_kwh')
    ppa_esc = get_num('ppa_escalation_pct')
    
    ann_energy = get_num('annual_energy_kwh')
    cf = get_num('capacity_factor_pct')
    
    yr1_ppa_cost = get_num('year1_ppa_cost_usd')
    yr1_elec_value = get_num('year1_electricity_value_usd')
    yr1_savings = get_num('year1_savings_usd')
    npv = get_num('npv_of_savings_usd')
    lcoe = get_num('lcoe_nom_cents_per_kwh')

    # Criterion 4: Config params correct (10 pts)
    config_ok = True
    if not ('denver' in loc or (lat is not None and 39.0 < lat < 40.5 and lon is not None and -106.0 < lon < -104.0)):
        config_ok = False
        
    if not (sys_size is not None and 7.8 <= sys_size <= 8.2):
        config_ok = False
        
    if not (tilt is not None and 34 <= tilt <= 36):
        config_ok = False
        
    if not (az is not None and 175 <= az <= 185):
        config_ok = False
        
    if config_ok:
        score += 10
        feedback_parts.append("Config parameters correct")
    else:
        feedback_parts.append("Config parameters incorrect/missing")

    # Criterion 5: PPA inputs correct (5 pts)
    if (ppa_price is not None and 7.8 <= ppa_price <= 8.2) and \
       (ppa_esc is not None and 1.9 <= ppa_esc <= 2.1):
        score += 5
        feedback_parts.append("PPA parameters correct")
    else:
        feedback_parts.append("PPA parameters incorrect")

    # Criterion 6: Annual Energy & CF in range (20 pts)
    # Physically 8kW in Denver should be ~10,000 - 14,000 kWh
    if ann_energy is not None and sys_size is not None:
        phys_ok, phys_msg = _physics_sanity_check(sys_size, ann_energy, "Denver")
        if phys_ok:
            score += 20
            feedback_parts.append(phys_msg)
        else:
            feedback_parts.append(phys_msg)
    else:
        feedback_parts.append("Missing annual energy")

    # Criterion 7 & 8: Financial consistency (10 + 10 pts)
    if all(v is not None for v in [ann_energy, ppa_price, yr1_ppa_cost, yr1_elec_value, yr1_savings]):
        fin_ok, fin_msg = _finance_consistency_check(ann_energy, ppa_price, yr1_ppa_cost, yr1_elec_value, yr1_savings)
        if fin_ok:
            score += 10  # Cost consistency
            score += 10  # Savings consistency
            feedback_parts.append("Financial outputs mathematically consistent")
        else:
            feedback_parts.append(fin_msg)
            
        # Extra explicit check for positive savings
        if yr1_savings > 0:
            feedback_parts.append("Positive year 1 savings achieved")
    else:
        feedback_parts.append("Missing financial outputs for consistency check")

    # Criterion 9: NPV / LCOE plausible (10 pts)
    if npv is not None and lcoe is not None:
        if npv > -10000 and 2.0 <= lcoe <= 20.0:  # Loose bounds, just checking it computed successfully
            score += 10
            feedback_parts.append("NPV/LCOE present and plausible")
        else:
            feedback_parts.append("NPV/LCOE out of plausible bounds")
    else:
        feedback_parts.append("Missing NPV or LCOE")

    # Final logic
    key_criteria_met = file_valid and result.get('file_modified', False) and (ann_energy is not None and ann_energy > 0)
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }