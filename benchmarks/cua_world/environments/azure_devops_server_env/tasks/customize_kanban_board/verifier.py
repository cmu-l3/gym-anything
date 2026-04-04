#!/usr/bin/env python3
"""
Verifier for customize_kanban_board task.

Verifies:
1. Column configuration (Names, Order, Mappings, WIP Limits)
2. Swimlane configuration (Expedite lane exists)
3. Card styling rules (Priority 1 = Red)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_kanban_board(traj, env_info, task_info):
    """
    Verify Azure DevOps Kanban board customization.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected state
    # Order matters: New -> Development -> Code Review -> Testing -> Closed
    EXPECTED_COLUMNS = [
        {"name": "New", "limit": 0, "state_mapping": "New"},
        {"name": "Development", "limit": 3, "state_mapping": "Active"},
        {"name": "Code Review", "limit": 2, "state_mapping": "Active"},
        {"name": "Testing", "limit": 3, "state_mapping": "Resolved"},
        {"name": "Closed", "limit": 0, "state_mapping": "Closed"}
    ]
    
    EXPECTED_SWIMLANE = "Expedite"
    EXPECTED_RULE_COLOR_TYPE = "red" # logic to check hex

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/task_results/customize_kanban_board_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Check 0: Anti-gaming (Do nothing)
    if result.get("is_default_state"):
        return {"passed": False, "score": 0, "feedback": "Board is in default state. No changes detected."}

    # Check 1: Columns (Total 60 points)
    columns = result.get("columns", [])
    
    # 1a. Column Count (6 pts)
    if len(columns) == 5:
        score += 6
    else:
        feedback.append(f"Expected 5 columns, found {len(columns)}.")

    # 1b. Check specific columns (Order and Config)
    # We will try to find columns by name to give partial credit even if out of order,
    # but give bonus for correct order.
    
    col_map = {c.get("name", "").lower(): c for c in columns}
    
    # "Development" (Renamed from Active) - 12 pts
    dev_col = col_map.get("development")
    if dev_col:
        score += 6 # Exists
        # Check mapping (Azure returns mappings as a dict, e.g., {'User Story': 'Active'})
        mappings = dev_col.get("stateMappings", {})
        if any(v == "Active" for v in mappings.values()):
            score += 3 # Correct mapping
        else:
            feedback.append("Development column has wrong state mapping.")
            
        if dev_col.get("itemLimit") == 3:
            score += 3 # Correct limit
        else:
            feedback.append(f"Development column limit expected 3, got {dev_col.get('itemLimit')}.")
    else:
        feedback.append("Column 'Development' not found.")

    # "Code Review" (New) - 12 pts
    cr_col = col_map.get("code review")
    if cr_col:
        score += 6
        mappings = cr_col.get("stateMappings", {})
        if any(v == "Active" for v in mappings.values()):
            score += 3
        else:
            feedback.append("Code Review column has wrong state mapping.")
            
        if cr_col.get("itemLimit") == 2:
            score += 3
        else:
            feedback.append(f"Code Review limit expected 2, got {cr_col.get('itemLimit')}.")
    else:
        feedback.append("Column 'Code Review' not found.")

    # "Testing" (Renamed from Resolved) - 12 pts
    test_col = col_map.get("testing")
    if test_col:
        score += 6
        mappings = test_col.get("stateMappings", {})
        if any(v == "Resolved" for v in mappings.values()):
            score += 3
        else:
            feedback.append("Testing column has wrong state mapping.")
            
        if test_col.get("itemLimit") == 3:
            score += 3
        else:
            feedback.append(f"Testing limit expected 3, got {test_col.get('itemLimit')}.")
    else:
        feedback.append("Column 'Testing' not found.")
        
    # Order Check (10 pts)
    if len(columns) >= 5:
        names = [c.get("name") for c in columns]
        # Allow case-insensitive match
        names_lower = [n.lower() for n in names]
        expected_order = ["new", "development", "code review", "testing", "closed"]
        
        # Check if the sequence exists in the columns list
        # We look for the subsequence to be robust against extra columns if we didn't penalize count strictly
        is_ordered = True
        for i, expected in enumerate(expected_order):
            if i >= len(names_lower) or names_lower[i] != expected:
                is_ordered = False
                break
        
        if is_ordered:
            score += 10
        else:
            feedback.append("Column order is incorrect.")

    # Check 2: Swimlanes (14 points)
    rows = result.get("rows", [])
    has_expedite = any(r.get("name", "").lower() == "expedite" for r in rows)
    if has_expedite:
        score += 14
    else:
        feedback.append("Swimlane 'Expedite' not found.")

    # Check 3: Card Rules (14 points)
    rules = result.get("rules", [])
    # Look for a rule regarding Priority
    # Rule structure from API: 
    # {'name': 'Rule1', 'isEnabled': True, 'filter': "System.Title = 'x'", 'settings': {'backgroundColor': '#FF0000'}}
    # The filter for priority usually looks like "Microsoft.VSTS.Common.Priority = 1"
    
    rule_found = False
    color_correct = False
    
    for rule in rules:
        clauses = rule.get("clauses", []) # API v7.0 structure might vary, usually 'clauses' or 'filter' string
        # If API returns detailed object
        filter_str = str(rule) # loose check for simplicity if structure varies
        
        # Check for Priority condition
        has_priority = False
        if "Priority" in filter_str and "1" in filter_str:
            has_priority = True
        
        if has_priority:
            rule_found = True
            # Check color
            settings = rule.get("settings", {})
            bg_color = settings.get("fill", "") or settings.get("background-color", "") # 'fill' is common in ADO API
            
            if not bg_color:
                # Try to find hex in string representation if structure is obscure
                import re
                hex_codes = re.findall(r'#[0-9a-fA-F]{6}', str(settings))
                if hex_codes:
                    bg_color = hex_codes[0]

            if bg_color:
                # Check if red-ish
                try:
                    h = bg_color.lstrip('#')
                    rgb = tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
                    # Red is dominant: R > G + 50 and R > B + 50
                    if rgb[0] > rgb[1] + 50 and rgb[0] > rgb[2] + 50:
                        color_correct = True
                except:
                    pass
            break
            
    if rule_found:
        score += 7
        if color_correct:
            score += 7
        else:
            feedback.append("Priority rule found but color is not Red.")
    else:
        feedback.append("Card styling rule for Priority=1 not found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "Task completed successfully."
    }