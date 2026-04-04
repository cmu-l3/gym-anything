#!/usr/bin/env python3
"""
Verifier for fulltext_search_setup task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fulltext_search_setup(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created the correct Lucene FULLTEXT indexes in OrientDB.
    2. Generated the expected JSON output file with correct search results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the task result (DB state info)
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve the agent's output file
    agent_output = {}
    output_valid = False
    output_exists = task_result.get("output_exists", False)
    
    if output_exists:
        temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/home/ga/Documents/fulltext_search_results.json", temp_output.name)
            with open(temp_output.name, 'r') as f:
                agent_output = json.load(f)
            output_valid = True
        except json.JSONDecodeError:
            pass # Invalid JSON
        except Exception:
            pass # Failed to read
        finally:
            if os.path.exists(temp_output.name):
                os.unlink(temp_output.name)

    # === Scoring Logic ===
    score = 0
    feedback = []
    
    # Criterion 1: Hotels Index (20 pts)
    if task_result.get("hotels_lucene_index_exists"):
        score += 20
        feedback.append("Hotels Lucene index verified.")
    else:
        feedback.append("Missing Lucene index on Hotels.Name.")

    # Criterion 2: Restaurants Index (20 pts)
    if task_result.get("restaurants_lucene_index_exists"):
        score += 20
        feedback.append("Restaurants Lucene index verified.")
    else:
        feedback.append("Missing Lucene index on Restaurants.Name.")

    # Criterion 3: File Validity & Creation (10 pts)
    if output_valid and task_result.get("file_created_during_task"):
        score += 10
        feedback.append("Output JSON file created and is valid.")
    elif output_valid:
        score += 5
        feedback.append("Output JSON file exists but timestamp check inconclusive.")
    else:
        feedback.append("Output JSON file missing or invalid.")

    # Criterion 4: Content Verification (15 pts per section = 45 pts)
    if output_valid:
        # Check 'palace_plaza_hotels'
        pp_hotels = agent_output.get("palace_plaza_hotels", [])
        pp_names = [str(h.get("Name", "")) for h in pp_hotels]
        has_plaza = any("Plaza" in n for n in pp_names)
        has_palace = any("Palace" in n for n in pp_names)
        
        if len(pp_hotels) > 0 and (has_plaza or has_palace):
            score += 15
            feedback.append("Search 1 (Palace/Plaza) results appear correct.")
        else:
            feedback.append("Search 1 results empty or missing keywords.")

        # Check 'trattoria_restaurants'
        trat_rests = agent_output.get("trattoria_restaurants", [])
        trat_names = [str(r.get("Name", "")) for r in trat_rests]
        has_trattoria = any("Trattoria" in n for n in trat_names)
        
        if len(trat_rests) > 0 and has_trattoria:
            score += 15
            feedback.append("Search 2 (Trattoria) results appear correct.")
        else:
            feedback.append("Search 2 results empty or missing keywords.")

        # Check 'luxury_chain_hotels'
        lux_hotels = agent_output.get("luxury_chain_hotels", [])
        lux_names = [str(h.get("Name", "")) for h in lux_hotels]
        has_hyatt = any("Hyatt" in n for n in lux_names)
        has_fs = any("Four Seasons" in n for n in lux_names)
        
        if len(lux_hotels) > 0 and (has_hyatt or has_fs):
            score += 15
            feedback.append("Search 3 (Luxury) results appear correct.")
        else:
            feedback.append("Search 3 results empty or missing keywords.")
            
    # Consistency Bonus (5 pts)
    if score >= 95:
        score += 5
        feedback.append("Perfect execution.")

    # Pass Condition
    # Must have both indexes (40) + valid file (10) + at least one correct search (15) = 65
    passed = score >= 60 and task_result.get("hotels_lucene_index_exists") and task_result.get("restaurants_lucene_index_exists")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }