#!/usr/bin/env python3
"""
Verifier for financial_ledger_etl_transformation task.

Criteria:
1. Schema & Infrastructure (Schema, Tables created)
2. Chart of Accounts seeded correctly
3. Transformation Logic (Procedure created and executed)
4. Data Integrity (Balanced Journal Entries) - CRITICAL
5. Audit mechanisms (View created)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_financial_ledger_etl(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/financial_etl_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        
        # 1. Infrastructure (15 pts)
        schema_exists = result.get('schema_exists', False)
        gl_exists = result.get('gl_exists', False)
        coa_exists = result.get('coa_exists', False)
        
        if schema_exists and gl_exists and coa_exists:
            score += 15
            feedback_parts.append("Infrastructure created")
        elif schema_exists:
            score += 5
            feedback_parts.append("Partial infrastructure (missing tables)")
        else:
            feedback_parts.append("Schema/Tables missing")

        # 2. Chart of Accounts Seeding (10 pts)
        req_accounts = result.get('required_accounts_found', 0)
        if req_accounts >= 7:
            score += 10
            feedback_parts.append("Chart of Accounts seeded")
        elif req_accounts > 0:
            score += 5
            feedback_parts.append(f"Partial CoA seeding ({req_accounts}/7)")
        else:
            feedback_parts.append("CoA empty or missing required codes")

        # 3. Transformation Logic & Execution (45 pts)
        # Split into: Proc Exists (10), Rows Generated (10), Logic Check (15), Zero Handling (10)
        proc_exists = result.get('proc_exists', False)
        gl_row_count = result.get('gl_row_count', 0)
        logic_passed = result.get('logic_check_passed', False)
        zero_check = result.get('zero_val_check_passed', False)
        
        if proc_exists:
            score += 10
            feedback_parts.append("Stored Procedure exists")
        
        if gl_row_count > 100: # Expecting thousands, but >100 proves execution
            score += 10
            feedback_parts.append(f"Data populated ({gl_row_count} rows)")
        else:
            feedback_parts.append("Data not populated")
            
        if logic_passed:
            score += 15
            feedback_parts.append("Revenue mapping logic correct")
        else:
            feedback_parts.append("Revenue mapping logic failed (North America -> 4001)")
            
        if zero_check:
            score += 10
            feedback_parts.append("Zero-value handling correct")
        else:
            feedback_parts.append("Zero-value rows present (should be omitted)")

        # 4. Balance Integrity (15 pts) - CRITICAL
        # Must be exactly 0.00 difference
        balance_diff = float(result.get('balance_diff', 999.0))
        if balance_diff == 0.0:
            score += 15
            feedback_parts.append("Perfect Balance Integrity")
        elif balance_diff < 1.0:
            score += 5
            feedback_parts.append(f"Minor Balance Discrepancy ({balance_diff})")
        else:
            feedback_parts.append(f"CRITICAL: Ledger Imbalanced by {balance_diff}")

        # 5. Audit View (10 pts)
        view_exists = result.get('view_exists', False)
        view_returns_rows = result.get('view_returns_rows', True) # True means bad here (rows found)
        
        if view_exists:
            score += 5
            if not view_returns_rows:
                score += 5
                feedback_parts.append("Audit View validates data")
            else:
                feedback_parts.append("Audit View found unbalanced transactions")
        
        # 6. Constraints (5 pts)
        if result.get('constraints_exist', False):
            score += 5
            feedback_parts.append("Constraints check passed")

        passed = score >= 75 and balance_diff == 0.0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}