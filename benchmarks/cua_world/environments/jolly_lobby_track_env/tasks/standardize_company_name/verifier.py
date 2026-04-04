#!/usr/bin/env python3
"""
Verifier for standardize_company_name task.

Verification Strategy:
1. File-based: Check if the database file was modified.
2. Content-based: specific text replacement in the DB binary.
   - We search for the byte sequences of "Innova GmbH" and "Innova Global".
   - Success: "Innova Global" count > 0 AND "Innova GmbH" count == 0 (or reduced).
   - We check both ASCII and UTF-16LE encodings as Windows apps often use the latter.
3. Visual: VLM check on trajectory to confirm edit actions.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, though we use gym_anything usually
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback mock for local testing
    def query_vlm(*args, **kwargs): return {"success": False, "error": "ImportError"}
    def sample_trajectory_frames(*args, **kwargs): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def count_occurrences_in_binary(file_path, search_str):
    """
    Counts occurrences of a string in a binary file.
    Checks ASCII, UTF-16LE, and UTF-16BE encodings.
    """
    if not os.path.exists(file_path):
        return 0
    
    count = 0
    with open(file_path, 'rb') as f:
        content = f.read()
        
        # Check ASCII/UTF-8
        count += content.count(search_str.encode('utf-8'))
        
        # Check UTF-16LE (Windows native)
        count += content.count(search_str.encode('utf-16-le'))
        
        # Check UTF-16BE
        count += content.count(search_str.encode('utf-16-be'))
        
    return count

def verify_standardize_company_name(traj, env_info, task_info):
    """
    Verifies that 'Innova GmbH' was changed to 'Innova Global'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task metadata
    metadata = task_info.get('metadata', {})
    old_name = metadata.get('old_company_name', 'Innova GmbH')
    new_name = metadata.get('new_company_name', 'Innova Global')
    
    # 1. Retrieve Result JSON and Database File
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.bin')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        # Try to copy DB file
        db_exists = result.get("db_exists", False)
        if db_exists:
            try:
                copy_from_env("/tmp/task_result_db.bin", temp_db.name)
            except Exception as e:
                logger.warning(f"Could not copy DB file: {e}")
                db_exists = False
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Database Modification Check (Anti-gaming)
    if result.get("db_modified", False):
        score += 10
        feedback.append("Database file was modified.")
    else:
        feedback.append("Warning: Database file was NOT modified.")
        
    # 3. Content Verification (Byte search)
    # This is the most reliable check. If the string "Innova Global" is in the binary, it was written.
    if db_exists:
        old_count = count_occurrences_in_binary(temp_db.name, old_name)
        new_count = count_occurrences_in_binary(temp_db.name, new_name)
        
        logger.info(f"String counts - Old ('{old_name}'): {old_count}, New ('{new_name}'): {new_count}")
        
        if new_count > 0:
            score += 40
            feedback.append(f"Found '{new_name}' in database ({new_count} occurrences).")
            
            if old_count == 0:
                score += 30
                feedback.append(f"Successfully removed all traces of '{old_name}'.")
            elif old_count < 2: # Tolerance for log entries or backup tables
                score += 20
                feedback.append(f"Mostly removed '{old_name}' (remaining: {old_count}).")
            else:
                feedback.append(f"Still found {old_count} occurrences of '{old_name}'. Incomplete update.")
        else:
            feedback.append(f"Did not find '{new_name}' in the database.")
            
    # Cleanup DB temp file
    if os.path.exists(temp_db.name):
        os.unlink(temp_db.name)
        
    # 4. VLM Verification (Trajectory)
    # Essential fallback if DB format is obscure or compressed
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = f"""
    Review these screenshots of a user interacting with Jolly Lobby Track visitor management software.
    The goal was to change a visitor's company from '{old_name}' to '{new_name}'.
    
    Look for:
    1. A search or list showing '{old_name}'.
    2. An 'Edit Visitor' or properties dialog.
    3. The user typing or selecting '{new_name}'.
    4. Saving the record.
    
    Did the user perform these actions?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get("success", False):
        # Interpret VLM answer simply (this is a simplified logic, real implementation would parse JSON)
        # Assuming VLM returns a boolean or "yes" in analysis
        # Here we assume the framework handles scoring details, or we parse a simple yes/no
        analysis = vlm_result.get("result", "").lower()
        if "yes" in analysis or "successfully" in analysis:
            score += 20
            feedback.append("Visual evidence confirms the update workflow.")
        else:
            feedback.append("Visual evidence is inconclusive.")
            
    # Final Scoring
    passed = score >= 70  # Requires at least New Name present (40+10) + VLM(20) or Clean Removal(30)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }