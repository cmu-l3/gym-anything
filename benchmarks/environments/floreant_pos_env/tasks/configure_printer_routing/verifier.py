#!/usr/bin/env python3
"""
Verifier for configure_printer_routing task.

Criteria:
1. A Virtual Printer named "Bar Printer" exists in the database.
2. The "Beverages" menu category is linked to the "Bar Printer" ID.
3. Visual confirmation via VLM (optional but good for anti-gaming).
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_ij_output(output_text: str) -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    Parses the raw text output from Derby's ij tool.
    
    Returns:
        printers: Dict mapping Printer Name -> ID
        categories: Dict mapping Category Name -> Linked Printer ID
    """
    printers = {}
    categories = {}
    
    # Derby ij output format looks like:
    # ID         |NAME
    # ------------------------
    # 1          |Kitchen
    # 2          |Receipt
    
    # We look for lines containing IDs and Names.
    # Since we ran two queries, we need to process them sequentially.
    
    lines = output_text.splitlines()
    current_section = None # 'printer' or 'category'
    
    for line in lines:
        line = line.strip()
        
        # Detect section based on query echo or table headers
        if "SELECT ID, NAME FROM VIRTUAL_PRINTER" in line:
            current_section = 'printer'
            continue
        if "SELECT NAME, VIRTUAL_PRINTER_ID FROM MENU_CATEGORY" in line:
            current_section = 'category'
            continue
            
        # Skip headers and separators
        if "ID" in line and "NAME" in line: continue
        if "NAME" in line and "VIRTUAL_PRINTER_ID" in line: continue
        if line.startswith("--") or line == "": continue
        if "selected" in line: continue # "x rows selected"
        
        parts = [p.strip() for p in line.split('|')]
        if len(parts) < 2: continue
        
        if current_section == 'printer':
            # Format: ID | NAME
            p_id = parts[0]
            p_name = parts[1]
            printers[p_name] = p_id
            # Also handle extra spaces/case
            printers[p_name.lower()] = p_id
            
        elif current_section == 'category':
            # Format: NAME | VIRTUAL_PRINTER_ID
            c_name = parts[0]
            c_printer_id = parts[1]
            if c_printer_id == "NULL":
                c_printer_id = None
            categories[c_name] = c_printer_id
            categories[c_name.lower()] = c_printer_id
            
    return printers, categories

def verify_configure_printer_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON and DB Output
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        db_output_path = result_data.get("db_output_file")
        if db_output_path:
            copy_from_env(db_output_path, temp_db.name)
            with open(temp_db.name, 'r') as f:
                db_content = f.read()
        else:
            db_content = ""
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_db.name): os.unlink(temp_db.name)

    # 2. Parse Database Content
    printers, categories = parse_ij_output(db_content)
    
    score = 0
    feedback = []
    
    # Target values
    TARGET_PRINTER = "Bar Printer"
    TARGET_CATEGORY = "Beverages"
    
    # Check 1: App usage (10 pts)
    if result_data.get("app_was_running", False):
        score += 10
        feedback.append("Application was running.")
    else:
        feedback.append("Application was not running at end of task.")

    # Check 2: Printer Creation (30 pts)
    # Check case-insensitive, but prefer exact
    bar_printer_id = None
    
    # Check exact match first
    if TARGET_PRINTER in printers:
        bar_printer_id = printers[TARGET_PRINTER]
        score += 30
        feedback.append(f"Printer '{TARGET_PRINTER}' found (ID: {bar_printer_id}).")
    # Check case-insensitive match
    elif TARGET_PRINTER.lower() in printers:
        bar_printer_id = printers[TARGET_PRINTER.lower()]
        score += 25 # Slight penalty for wrong casing
        feedback.append(f"Printer found with case mismatch (ID: {bar_printer_id}).")
    else:
        feedback.append(f"Printer '{TARGET_PRINTER}' NOT found in database.")

    # Check 3: Category Configuration (60 pts)
    # Only possible if printer exists
    routing_correct = False
    if bar_printer_id:
        # Find category
        cat_printer_id = None
        if TARGET_CATEGORY in categories:
            cat_printer_id = categories[TARGET_CATEGORY]
        elif TARGET_CATEGORY.lower() in categories:
            cat_printer_id = categories[TARGET_CATEGORY.lower()]
        
        if cat_printer_id is None:
            feedback.append(f"Category '{TARGET_CATEGORY}' not found or has no printer assigned.")
        elif cat_printer_id == bar_printer_id:
            score += 60
            routing_correct = True
            feedback.append(f"Category '{TARGET_CATEGORY}' correctly routed to '{TARGET_PRINTER}'.")
        else:
            feedback.append(f"Category '{TARGET_CATEGORY}' is routed to ID {cat_printer_id}, expected {bar_printer_id}.")
    else:
        feedback.append("Cannot verify routing because printer was not found.")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }