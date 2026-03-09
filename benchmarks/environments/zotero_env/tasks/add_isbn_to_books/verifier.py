#!/usr/bin/env python3
import json
import tempfile
import os
import re

def normalize_isbn(isbn):
    """Remove hyphens and spaces from ISBN."""
    if not isbn:
        return ""
    return re.sub(r'[\-\s]', '', str(isbn))

def verify_add_isbn_to_books(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load Result JSON
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
            
    # Get expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_books = metadata.get('books', [])
    
    score = 0
    feedback = []
    
    # Check if result has error
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"DB Error: {result['error']}"}

    found_books = result.get('books', [])
    
    if not found_books:
        return {"passed": False, "score": 0, "feedback": "No books found in library"}
        
    # Match found books to expected books by title (fuzzy match)
    matched_count = 0
    correct_isbns = 0
    
    for expected in expected_books:
        exp_title = expected['title']
        exp_isbn = normalize_isbn(expected['isbn_13'])
        
        # Find corresponding book in result
        found_entry = None
        for fb in found_books:
            if fb['title'] and exp_title.lower() in fb['title'].lower():
                found_entry = fb
                break
        
        if found_entry:
            found_isbn_raw = found_entry.get('isbn')
            found_isbn = normalize_isbn(found_isbn_raw)
            
            if found_isbn == exp_isbn:
                score += 15
                correct_isbns += 1
                feedback.append(f"✓ {exp_title[:20]}...: Correct ISBN")
            elif found_isbn:
                feedback.append(f"✗ {exp_title[:20]}...: Wrong ISBN ({found_isbn_raw})")
            else:
                feedback.append(f"✗ {exp_title[:20]}...: No ISBN")
        else:
            feedback.append(f"✗ {exp_title[:20]}...: Book not found in DB")

    # Anti-gaming: Check if at least one ISBN was added (vs 0 initially)
    # The setup ensures 0 start, so if we have correct ISBNs, they must be new.
    if correct_isbns > 0:
        score += 10
        feedback.append("Anti-gaming: ISBNs successfully modified")
    
    final_score = min(100, score) # Cap at 100
    passed = final_score >= 55 # Threshold
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback)
    }