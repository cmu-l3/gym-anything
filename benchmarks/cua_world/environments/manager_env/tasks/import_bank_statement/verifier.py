#!/usr/bin/env python3
"""
Verifier for import_bank_statement task.

Verifies that:
1. The Cash on Hand account contains the imported transactions (via API scrape).
2. The descriptions and amounts match the CSV file.
3. VLM: Validates the agent used the 'Import Bank Statement' workflow.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Attempt to import VLM utils; mock if not available (for standalone testing)
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    def query_vlm(*args, **kwargs):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(*args, **kwargs):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_bank_statement(traj, env_info, task_info):
    """
    Verify the bank statement import.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_transaction_count', 8)
    
    # 1. Load programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Programmatic Checks (70 points) ---
    
    # Check 1: Account found (10 pts)
    if result.get("account_found"):
        score += 10
        feedback.append("Bank account accessed.")
    else:
        feedback.append("Could not find Cash on Hand account transactions.")

    # Check 2: Transaction Count (20 pts)
    # We expect at least some transactions. 
    # result['transaction_count'] is based on finding expected descriptions.
    found_count = len(result.get("found_descriptions", []))
    
    if found_count >= expected_count:
        score += 20
        feedback.append(f"All {found_count} transactions found.")
    elif found_count >= expected_count / 2:
        score += 10
        feedback.append(f"Partial transactions found ({found_count}/{expected_count}).")
    elif found_count > 0:
        score += 5
        feedback.append(f"Few transactions found ({found_count}).")
    else:
        feedback.append("No expected transactions found.")

    # Check 3: Amounts (20 pts)
    found_amounts = len(result.get("found_amounts", []))
    if found_amounts >= 6:
        score += 20
        feedback.append("Transaction amounts verified.")
    elif found_amounts > 0:
        score += 10
        feedback.append("Some transaction amounts verified.")

    # Check 4: Descriptions (20 pts)
    # Already partially covered by count, but explicit check for correct text
    desc_ratio = found_count / expected_count if expected_count > 0 else 0
    score += int(desc_ratio * 20)
    
    # --- VLM Checks (30 points) ---
    # We want to verify they used the IMPORT feature, not manual entry.
    # Manual entry of 8 items takes a lot of clicks. Import is distinct.
    
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=8)
    
    if frames:
        prompt = """
        Analyze these screenshots of a user interacting with Manager.io accounting software.
        I am looking for evidence that the user IMPORTED a bank statement (CSV file) rather than manually typing transactions.
        
        Look for:
        1. A file upload dialog or file selection screen.
        2. A screen titled "Import Bank Statement" or showing column mapping (e.g. "Date", "Description", "Amount" dropdowns).
        3. A list of transactions appearing all at once.
        
        Answer JSON:
        {
            "import_dialog_visible": boolean,
            "column_mapping_visible": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("import_dialog_visible") or parsed.get("column_mapping_visible"):
                vlm_score = 30
                feedback.append("VLM confirmed import workflow usage.")
            else:
                # Fallback: if they got 100% on programmatic, maybe VLM missed it, 
                # or maybe they are super fast typists. 
                # But manual entry of 8 complex items in 5 mins is hard.
                # We'll give partial credit if data is perfect.
                if score >= 60:
                    vlm_score = 10
                    feedback.append("VLM did not clearly see import dialog, but data is correct.")
                else:
                    feedback.append("VLM did not detect import workflow.")
        else:
            # If VLM fails, default to partial points if data is good
            if score >= 50:
                vlm_score = 15
                feedback.append("VLM unavailable, skipped workflow check.")

    score += vlm_score

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }