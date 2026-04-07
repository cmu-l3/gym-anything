#!/usr/bin/env python3
"""
Verifier for add_work_package_relation task.

Checks:
1. Valid relation exists between correct work packages (Type: follows, Lag: 2)
2. Correct comment exists on the source work package
3. Anti-gaming: Relation count increased, comment created during task time
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_work_package_relation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    container_data = result.get('container_data', {})
    initial_rel_count = int(result.get('initial_relation_count', 0))
    task_start_time = int(result.get('task_start_time', 0))
    
    # Metadata for content checks
    metadata = task_info.get('metadata', {})
    required_phrases = metadata.get('required_comment_phrases', ["Elasticsearch", "stabilized"])

    score = 0
    feedback = []
    
    # Check 1: Work Packages Found
    if not container_data.get('source_found') or not container_data.get('target_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Critical Error: Could not find required Work Packages in the database. Did the environment seed correctly?"
        }

    # Check 2: Relation Verification (50 points total)
    relations = container_data.get('relations', [])
    valid_relation_found = False
    lag_correct = False
    type_correct = False

    if not relations:
        feedback.append("No relation found between the two work packages.")
    else:
        # We look for a relation that implies "Source Follows Target"
        # In OpenProject:
        # If type is 'follows': from_id must be Source (Recommendation), to_id must be Target (Search)
        # If type is 'precedes': from_id must be Target (Search), to_id must be Source (Recommendation)
        
        for r in relations:
            r_type = r.get('type', '').lower()
            source_is_from = r.get('source_is_from')
            
            # Check directionality
            is_follows_direction = (r_type == 'follows' and source_is_from) or \
                                   (r_type == 'precedes' and not source_is_from)
            
            if is_follows_direction:
                type_correct = True
                score += 35  # Base score for correct relation existing
                feedback.append("Correct 'Follows' relation found.")
                
                # Check Lag
                lag = int(r.get('lag', 0))
                if lag == 2:
                    lag_correct = True
                    score += 15
                    feedback.append("Lag is correctly set to 2 days.")
                else:
                    feedback.append(f"Relation exists but Lag is {lag} days (expected 2).")
                
                valid_relation_found = True
                break
        
        if not valid_relation_found:
             feedback.append(f"Relation found but incorrect type or direction. Found types: {[r['type'] for r in relations]}")

    # Check 3: Comment Verification (45 points total)
    comments = container_data.get('comments', [])
    valid_comment_found = False
    
    # Filter comments created during task
    new_comments = [c for c in comments if c.get('created_at', 0) > task_start_time]
    
    if not new_comments:
        feedback.append("No new comments added to the work package during the task.")
    else:
        score += 20  # Points for adding ANY comment
        
        # Check content of the best matching comment
        best_match_score = 0
        best_comment = ""
        
        for comment in new_comments:
            text = comment.get('notes', '').lower()
            match_count = sum(1 for phrase in required_phrases if phrase.lower() in text)
            
            if match_count > best_match_score:
                best_match_score = match_count
                best_comment = text
        
        if best_match_score >= 2:
            score += 25
            feedback.append("Comment content matches requirements.")
            valid_comment_found = True
        elif best_match_score == 1:
            score += 10
            feedback.append("Comment partially matches requirements (missing some key details).")
        else:
            feedback.append("Comment exists but does not explain the dependency correctly.")

    # Check 4: Anti-Gaming (5 points)
    final_rel_count = int(container_data.get('final_relation_count', 0))
    if final_rel_count > initial_rel_count:
        score += 5
    else:
        # If we found the specific relation but count didn't increase, it might have existed before?
        # In this specific seed, it shouldn't.
        pass

    passed = (score >= 60 and valid_relation_found and valid_comment_found)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }