#!/usr/bin/env python3
"""
Verifier for create_financial_voice_tool task.

Uses programmatic execution inside the container to test the AST/logic of the Python
module and regex matching for the Talon commands. Completely avoids gaming by testing
against the actual downloaded dataset.
"""

import os
import json
import csv
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def clean_company_name(name):
    """Applies the strict sanitization rules exactly as requested in the prompt."""
    # 1. Lowercase
    n = name.lower()
    # 2. Remove commas
    n = n.replace(",", "")
    # 3. Remove exact suffixes
    for suffix in [" inc.", " corp.", " ltd.", " company"]:
        n = n.replace(suffix, "")
    # 4. Strip whitespace
    return n.strip()

def verify_financial_voice_tool(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Get the execution results from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve test results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Early check for basic file creation (10 points max)
    if result.get("py_exists"):
        score += 5
        feedback_parts.append("Python file created")
    else:
        feedback_parts.append("Python file missing")
        
    if result.get("talon_exists"):
        score += 5
        feedback_parts.append("Talon file created")
    else:
        feedback_parts.append("Talon file missing")
        
    if not (result.get("py_exists") or result.get("talon_exists")):
        return {"passed": False, "score": 0, "feedback": "Neither required file was created."}

    # 2. Check Talon commands (20 points max)
    talon_content = result.get("talon_content", "")
    commands_found = 0
    
    if re.search(r'company price\s+\{user\.company_ticker\}:', talon_content, re.IGNORECASE):
        commands_found += 1
    if re.search(r'company valuation\s+\{user\.company_ticker\}:', talon_content, re.IGNORECASE):
        commands_found += 1
    if re.search(r'company multiple\s+\{user\.company_ticker\}:', talon_content, re.IGNORECASE):
        commands_found += 1
        
    if "insert_finance_metric" in talon_content:
        commands_found += 1
        
    command_score = (commands_found / 4.0) * 20
    score += command_score
    if command_score == 20:
        feedback_parts.append("All Talon voice commands correct")
    else:
        feedback_parts.append(f"Talon commands incomplete ({commands_found}/4 elements found)")

    # 3. Download the CSV to ground-truth the data parsing
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    ground_truth_mappings = {}
    ground_truth_aapl_price = None
    
    try:
        copy_from_env("C:\\workspace\\data\\sp500_financials.csv", temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                symbol = row.get("Symbol")
                name = row.get("Name")
                if symbol and name:
                    cleaned = clean_company_name(name)
                    ground_truth_mappings[cleaned] = symbol
                if symbol == "AAPL":
                    ground_truth_aapl_price = row.get("Price")
    except Exception as e:
        logger.warning(f"Could not retrieve CSV for ground-truthing: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Check Python load and Data Sanitization (40 points max)
    parsing_score = 0
    if result.get("error"):
        feedback_parts.append(f"Python execution error: {result['error'].splitlines()[-1]}")
    elif result.get("py_loads") and result.get("list_populated"):
        agent_mapping = result.get("agent_mapping", {})
        
        if len(agent_mapping) > 0 and len(ground_truth_mappings) > 0:
            # Check overlap of keys
            correct_keys = 0
            keys_to_check = list(ground_truth_mappings.keys())[:20]  # sample 20 keys
            
            for k in keys_to_check:
                if k in agent_mapping and agent_mapping[k] == ground_truth_mappings[k]:
                    correct_keys += 1
                    
            match_ratio = correct_keys / len(keys_to_check)
            
            if match_ratio >= 0.9:
                parsing_score = 40
                feedback_parts.append("Perfect string sanitization")
            elif match_ratio >= 0.5:
                parsing_score = 20
                feedback_parts.append("Partial string sanitization success")
            else:
                feedback_parts.append("Data parsing failed sanitization rules")
        else:
            feedback_parts.append("Dictionary list was empty")
    else:
        feedback_parts.append("Failed to populate company_ticker list")
        
    score += parsing_score

    # 5. Check Action Implementation (30 points max)
    action_score = 0
    if ground_truth_aapl_price is not None and result.get("action_test_price") is not None:
        agent_price = str(result.get("action_test_price", "")).strip()
        gt_price = str(ground_truth_aapl_price).strip()
        
        if agent_price == gt_price:
            action_score = 30
            feedback_parts.append("Action insert_finance_metric works perfectly")
        elif agent_price != "None" and len(agent_price) > 0:
            action_score = 10
            feedback_parts.append("Action called insert but retrieved wrong metric")
    else:
        if result.get("action_test_price") is None:
            feedback_parts.append("Action lookup failed to trigger actions.insert()")
            
    score += action_score

    # Passing criteria
    passed = score >= 70 and parsing_score > 0
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }