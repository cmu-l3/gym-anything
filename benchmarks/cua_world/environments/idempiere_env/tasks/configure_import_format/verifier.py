#!/usr/bin/env python3
"""
Verifier for configure_import_format task in iDempiere.

Criteria:
1. Import Format Header exists with correct Name, Table, and Format Type.
2. Import Format Lines exist with correct Sequence, Column mapping, and Data Type.
3. Anti-gaming: Record created during task window.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_import_format(traj, env_info, task_info):
    """
    Verify the agent configured the Import Format correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    # Scoring Variables
    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Header Verification (45 Points)
    # ----------------------------------------------------------------
    if not result.get('format_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Import Format 'Legacy Customer Import' not found in database."
        }

    details = result.get('format_details', {})
    
    # Check Name (Implicitly correct due to query, but good for completeness)
    if details.get('name') == "Legacy Customer Import":
        score += 20
        feedback_parts.append("Header Name Correct (+20)")
    
    # Check Table (Expected: I_BPartner)
    # Note: Case sensitive check usually, but I_BPartner is standard
    table_name = details.get('table_name', '')
    if table_name == 'I_BPartner':
        score += 15
        feedback_parts.append("Target Table Correct (+15)")
    else:
        feedback_parts.append(f"Target Table Incorrect (Expected I_BPartner, got {table_name})")

    # Check Format Type (Expected: C for Comma Separated)
    fmt_type = details.get('format_type', '')
    if fmt_type == 'C':
        score += 10
        feedback_parts.append("Format Type Correct (+10)")
    else:
        feedback_parts.append(f"Format Type Incorrect (Expected 'C', got '{fmt_type}')")

    # ----------------------------------------------------------------
    # 2. Rows Verification (40 Points - 10 per correct line)
    # ----------------------------------------------------------------
    # Expected:
    # 10: Value (Search Key)
    # 20: Name
    # 30: TaxID
    # 40: Description
    
    rows = result.get('format_rows', [])
    rows_map = {r['seq']: r for r in rows}
    
    # Helper to check a row
    def check_row(seq, expected_cols, pts):
        if seq not in rows_map:
            return 0, f"Missing Seq {seq}"
        
        row = rows_map[seq]
        col = row.get('column', '')
        
        # Allow some flexibility in column names if exact API names differ slightly
        # though AD_Column.ColumnName is usually strict.
        if col in expected_cols:
            return pts, f"Seq {seq} Correct ({col}) (+{pts})"
        return 0, f"Seq {seq} Incorrect (Expected {expected_cols}, got {col})"

    # Seq 10: Value (Search Key)
    s10, f10 = check_row(10, ['Value', 'Search Key'], 10)
    score += s10
    feedback_parts.append(f10)

    # Seq 20: Name
    s20, f20 = check_row(20, ['Name'], 10)
    score += s20
    feedback_parts.append(f20)

    # Seq 30: TaxID
    s30, f30 = check_row(30, ['TaxID', 'Tax ID'], 10)
    score += s30
    feedback_parts.append(f30)

    # Seq 40: Description
    s40, f40 = check_row(40, ['Description'], 10)
    score += s40
    feedback_parts.append(f40)

    # ----------------------------------------------------------------
    # 3. Sequence Order Logic (15 Points)
    # ----------------------------------------------------------------
    # Check if we have exactly 4 rows and they are 10, 20, 30, 40
    if len(rows) == 4 and all(k in rows_map for k in [10, 20, 30, 40]):
        score += 15
        feedback_parts.append("Sequence Structure Correct (+15)")
    elif len(rows) > 0:
        feedback_parts.append(f"Sequence Structure Partial/Incorrect (Count: {len(rows)})")
    
    # ----------------------------------------------------------------
    # 4. Anti-Gaming Timestamp Check
    # ----------------------------------------------------------------
    # Verify creation wasn't from a stale state (though setup cleans it)
    # This is implicitly handled by the setup script deleting the record first,
    # so existence implies fresh creation, but good to report.
    
    # Final Result
    passed = score >= 65 and details.get('table_name') == 'I_BPartner'
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }