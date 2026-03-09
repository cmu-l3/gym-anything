#!/usr/bin/env python3
"""
Verifier for create_employee_payslip task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_employee_payslip(traj, env_info, task_info):
    """
    Verify the payroll setup and payslip creation in Manager.io.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Scoring Configuration
    score = 0
    feedback_parts = []
    
    modules = result.get("modules_enabled", {})
    employees = result.get("employees", [])
    payslip_items = result.get("payslip_items", [])
    payslips = result.get("payslips", [])

    # 1. Modules Enabled (20 pts)
    # Note: Our scraper checks if endpoints are accessible.
    if modules.get("employees"):
        score += 10
        feedback_parts.append("Employees module enabled")
    else:
        feedback_parts.append("Employees module NOT enabled")

    if modules.get("payslip_items") and modules.get("payslips"):
        score += 10
        feedback_parts.append("Payroll modules enabled")
    elif modules.get("payslip_items") or modules.get("payslips"):
        score += 5
        feedback_parts.append("Some payroll modules enabled")
    else:
        feedback_parts.append("Payroll modules NOT enabled")

    # 2. Payslip Items Created (20 pts)
    if "Gross Salary" in payslip_items:
        score += 10
        feedback_parts.append("Gross Salary item created")
    else:
        feedback_parts.append("Gross Salary item missing")
        
    # Check for "Income Tax Withholding" or partial match "Income Tax"
    has_tax = any("Income Tax" in item for item in payslip_items)
    if has_tax:
        score += 10
        feedback_parts.append("Income Tax item created")
    else:
        feedback_parts.append("Income Tax item missing")

    # 3. Employee Created (15 pts)
    if "Maria Anders" in employees:
        score += 15
        feedback_parts.append("Employee 'Maria Anders' created")
    else:
        feedback_parts.append("Employee 'Maria Anders' NOT found")

    # 4. Payslip Verification (45 pts)
    if payslips:
        ps = payslips[0] # Analyze the first/best match
        score += 15
        feedback_parts.append("Payslip created")
        
        if ps.get("date_found"):
            score += 5
            feedback_parts.append("Date correct (Jan 31)")
        else:
            feedback_parts.append("Date incorrect")
            
        if ps.get("gross_found"):
            score += 10
            feedback_parts.append("Gross amount correct (4,500.00)")
        else:
            feedback_parts.append("Gross amount incorrect")
            
        if ps.get("tax_found"):
            score += 5
            feedback_parts.append("Tax deduction correct (675.00)")
        else:
            feedback_parts.append("Tax deduction incorrect")
            
        if ps.get("net_found"):
            score += 10
            feedback_parts.append("Net pay correct (3,825.00)")
        else:
            feedback_parts.append("Net pay incorrect")
    else:
        feedback_parts.append("No payslip found for Maria Anders")

    # Final result
    passed = score >= 60
    
    # Critical failure check: Must have at least created the employee or payslip to pass
    if not employees and not payslips:
        passed = False
        feedback_parts.append("CRITICAL: No employee or payslip created")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }