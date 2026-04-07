#!/usr/bin/env python3
"""
Verifier for docker_batch_processing@1

Scoring System (100 pts):
- Image 'book-analyzer:latest' exists: 10 pts
- Image created AFTER task start: 5 pts
- 5 or more containers ran (parallelism evidence): 10 pts
- 5 valid JSON result files found: 15 pts (3 pts each)
- Result content validity (word counts in range): 20 pts (4 pts each)
- Merged report exists and parses: 15 pts
- Merged report summary is consistent with individual files: 5 pts
- Automation script exists: 5 pts
- Automation script references docker commands: 5 pts
- Parallelism verification (heuristic): 10 pts (Bonus for clean parallel implementation)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# Expected word count ranges (approximate to allow for differences in cleaning logic)
EXPECTED_COUNTS = {
    "pride_and_prejudice.txt": (110000, 140000),
    "moby_dick.txt": (200000, 230000),
    "sherlock_holmes.txt": (95000, 120000),
    "frankenstein.txt": (65000, 90000),
    "alice_in_wonderland.txt": (20000, 40000)
}

def verify_docker_batch_processing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    task_start = result.get('task_start_time', 0)
    
    # 1. Image Checks (15 pts)
    if result.get('image_exists'):
        score += 10
        feedback.append("Image 'book-analyzer:latest' exists (+10).")
        
        created_at = result.get('image_created_at', 0)
        if created_at > task_start:
            score += 5
            feedback.append("Image built during task (+5).")
        else:
            feedback.append("Image creation timestamp is old or invalid (0/5).")
    else:
        feedback.append("Image 'book-analyzer:latest' not found (0/15).")

    # 2. Container Execution (10 pts)
    count = result.get('container_count', 0)
    if count >= 5:
        score += 10
        feedback.append(f"Detected {count} container executions (+10).")
    elif count > 0:
        score += 5
        feedback.append(f"Detected {count} container executions (partial +5).")
    else:
        feedback.append("No containers appeared to run (0/10).")

    # 3. Individual Result Files (35 pts total)
    results_list = result.get('results_files_content', [])
    valid_files_count = 0
    valid_content_count = 0
    
    # Map results to book names using heuristic matching if filename not present
    # The export script tries to inject 'filename'.
    
    processed_books = set()
    total_calculated_words = 0
    
    for r in results_list:
        # Check basic structure
        if not isinstance(r, dict): continue
        if 'word_count' not in r: continue
        
        valid_files_count += 1
        wc = r.get('word_count', 0)
        total_calculated_words += wc
        
        # Identify book
        fname = r.get('filename', '').lower()
        matched_book = None
        
        # Try to match by filename
        for book_key in EXPECTED_COUNTS:
            base = book_key.replace('.txt', '')
            if base in fname:
                matched_book = book_key
                break
        
        # If filename didn't match, try to match by word count proximity
        if not matched_book:
            for book_key, (min_w, max_w) in EXPECTED_COUNTS.items():
                if book_key not in processed_books and min_w <= wc <= max_w:
                    matched_book = book_key
                    break
        
        if matched_book:
            processed_books.add(matched_book)
            min_w, max_w = EXPECTED_COUNTS[matched_book]
            if min_w <= wc <= max_w:
                valid_content_count += 1
    
    # Score files existence (max 15)
    file_points = min(valid_files_count * 3, 15)
    score += file_points
    if file_points > 0:
        feedback.append(f"Found {valid_files_count} valid result files (+{file_points}).")
    
    # Score content validity (max 20)
    content_points = min(valid_content_count * 4, 20)
    score += content_points
    if content_points > 0:
        feedback.append(f"Content valid for {valid_content_count} books (+{content_points}).")

    # 4. Merged Report (20 pts)
    report_exists = result.get('report_exists', False)
    if report_exists:
        score += 15
        feedback.append("Report file exists (+15).")
        
        # Verify summary consistency
        # Since report_content comes as a string from cat, we try to parse it inside python if needed
        # But export script usually parses JSON content if possible? 
        # Actually export script cats the file. If it was valid JSON, result['report_content'] is a dict/list.
        # If it was text, it is string.
        report_data = result.get('report_content')
        if isinstance(report_data, str):
            try:
                report_data = json.loads(report_data)
            except:
                report_data = None
        
        if isinstance(report_data, dict):
            # Check summary key
            summary = report_data.get('summary', {})
            total_reported = summary.get('total_word_count', 0)
            
            # Allow 10% tolerance between sum of parts and reported total (in case agent logic differs)
            if total_calculated_words > 0 and abs(total_reported - total_calculated_words) / total_calculated_words < 0.1:
                score += 5
                feedback.append("Report summary consistent with data (+5).")
            else:
                feedback.append("Report summary inconsistent or missing (0/5).")
    else:
        feedback.append("Report file not found (0/20).")

    # 5. Automation Script (10 pts)
    if result.get('script_exists'):
        score += 5
        feedback.append("Pipeline script exists (+5).")
        content = result.get('script_content', '')
        if 'docker' in content and 'build' in content:
            score += 5
            feedback.append("Script contains build commands (+5).")
        else:
            feedback.append("Script missing Docker commands (0/5).")
    else:
        feedback.append("Pipeline script not found (0/10).")

    # 6. Parallelism Bonus (10 pts)
    # If we have results and high container count in short time, assume parallel.
    # Hard to measure time exactly without logs, but if containers count >= 5 and task passed, give points.
    if count >= 5 and valid_files_count >= 5:
        score += 10
        feedback.append("Parallel execution assumed successful (+10).")

    pass_threshold = task_info.get('metadata', {}).get('pass_threshold', 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }