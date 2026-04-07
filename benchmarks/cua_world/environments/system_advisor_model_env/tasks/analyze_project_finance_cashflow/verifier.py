#!/usr/bin/env python3
"""
Verifier for analyze_project_finance_cashflow task.

Checks whether the PySAM Singleowner + Pvwattsv8 simulation was correctly parameterized
and written to JSON, verifying values are within expected financial/performance ranges.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_project_finance_cashflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    max_score = 100

    file_exists = result.get("file_exists", False)
    modified_during = result.get("modified_during_task", False)
    all_fields = result.get("all_fields_present", False)
    data = result.get("data", {})

    # 1. File exists (10 pts)
    if file_exists:
        score += 10
        feedback_parts.append("✅ File exists")
    else:
        feedback_parts.append("❌ File not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. File modified during task (10 pts)
    if modified_during:
        score += 10
        feedback_parts.append("✅ File created/modified during task")
    else:
        feedback_parts.append("❌ File not modified during task (possible gaming)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. All required fields present (10 pts)
    if all_fields:
        score += 10
        feedback_parts.append("✅ All required fields present")
    else:
        missing = [k for k, v in result.get("fields_present", {}).items() if not v]
        feedback_parts.append(f"❌ Missing fields: {', '.join(missing)}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    def safe_float(val, default=0.0):
        try:
            return float(val)
        except (ValueError, TypeError):
            return default

    # 4. Year 1 energy in range (10 pts)
    energy = safe_float(data.get("year1_energy_kwh"))
    if metadata["year1_energy_min"] <= energy <= metadata["year1_energy_max"]:
        score += 10
        feedback_parts.append(f"✅ Year 1 Energy valid ({energy:,.0f} kWh)")
    else:
        feedback_parts.append(f"❌ Year 1 Energy out of bounds ({energy:,.0f} kWh)")

    # 5. Capacity factor in range (5 pts)
    cf = safe_float(data.get("capacity_factor_percent"))
    if metadata["cf_min"] <= cf <= metadata["cf_max"]:
        score += 5
        feedback_parts.append(f"✅ Capacity Factor valid ({cf:.1f}%)")
    else:
        feedback_parts.append(f"❌ Capacity Factor out of bounds ({cf:.1f}%)")

    # 6. Real LCOE in range (10 pts)
    lcoe = safe_float(data.get("lcoe_real_cents_per_kwh"))
    if metadata["real_lcoe_min"] <= lcoe <= metadata["real_lcoe_max"]:
        score += 10
        feedback_parts.append(f"✅ Real LCOE valid ({lcoe:.2f} ¢/kWh)")
    else:
        feedback_parts.append(f"❌ Real LCOE out of bounds ({lcoe:.2f} ¢/kWh)")

    # 7. Project IRR in range (10 pts)
    irr = safe_float(data.get("project_irr_aftertax_percent"))
    if metadata["proj_irr_min"] <= irr <= metadata["proj_irr_max"]:
        score += 10
        feedback_parts.append(f"✅ Project IRR valid ({irr:.2f}%)")
    else:
        feedback_parts.append(f"❌ Project IRR out of bounds ({irr:.2f}%)")

    # 8. Min DSCR in range (10 pts)
    dscr = safe_float(data.get("min_dscr"))
    if metadata["dscr_min"] <= dscr <= metadata["dscr_max"]:
        score += 10
        feedback_parts.append(f"✅ Min DSCR valid ({dscr:.2f})")
    else:
        feedback_parts.append(f"❌ Min DSCR out of bounds ({dscr:.2f})")

    # 9. Cash flow array structure check (10 pts)
    cashflow = data.get("cashflow_aftertax", [])
    if isinstance(cashflow, list) and len(cashflow) == 26:
        try:
            cf_y0 = float(cashflow[0])
            if cf_y0 < -1000000:  # Large initial equity investment expected
                score += 10
                feedback_parts.append("✅ Cash flow valid (26 periods, Y0 < 0)")
            else:
                feedback_parts.append(f"❌ Cash flow Y0 not a large investment: {cf_y0}")
        except (ValueError, TypeError):
            feedback_parts.append("❌ Cash flow array contains non-numeric values")
    else:
        length = len(cashflow) if isinstance(cashflow, list) else 0
        feedback_parts.append(f"❌ Cash flow length invalid ({length} instead of 26)")

    # 10. Annual energy degradation check (5 pts)
    ann_energy = data.get("annual_energy_kwh", [])
    if isinstance(ann_energy, list) and len(ann_energy) == 25:
        try:
            if float(ann_energy[0]) > float(ann_energy[-1]): # Degradation over 25 years
                score += 5
                feedback_parts.append("✅ Annual energy valid (25 periods, degrading)")
            else:
                feedback_parts.append("❌ Annual energy does not show degradation")
        except (ValueError, TypeError):
            feedback_parts.append("❌ Annual energy array contains non-numeric values")
    else:
        length = len(ann_energy) if isinstance(ann_energy, list) else 0
        feedback_parts.append(f"❌ Annual energy length invalid ({length} instead of 25)")

    # 11. Input parameter echo verification (5 pts)
    ppa = safe_float(data.get("ppa_price_year1_cents_per_kwh"))
    debt = safe_float(data.get("debt_fraction_percent"))
    cost = safe_float(data.get("total_installed_cost_dollars"))
    
    # Allow small float discrepancies
    if abs(ppa - metadata["ppa_expected"]) < 0.1 and \
       abs(debt - metadata["debt_pct_expected"]) < 1.0 and \
       abs(cost - metadata["cost_expected"]) < 1000:
        score += 5
        feedback_parts.append("✅ Configuration inputs echoed correctly")
    else:
        feedback_parts.append(f"❌ Configuration mismatch (PPA:{ppa}, Debt:{debt}, Cost:{cost})")

    # 12. NPV in range (5 pts)
    npv = safe_float(data.get("npv_aftertax_dollars"))
    if metadata["npv_min"] <= npv <= metadata["npv_max"]:
        score += 5
        feedback_parts.append(f"✅ NPV valid (${npv:,.0f})")
    else:
        feedback_parts.append(f"❌ NPV out of bounds (${npv:,.0f})")

    passed = score >= 65 and file_exists and modified_during

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }