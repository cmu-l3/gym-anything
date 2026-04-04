#!/usr/bin/env python3
"""
Verifier for url_rewrite_migration_simulation task.
"""

import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_url_rewrite_migration_simulation(traj, env_info, task_info):
    """
    Verifies that the agent configured URL rewriting correctly and exported the results.
    
    Criteria:
    1. Output CSV exists and was created during task (20 pts).
    2. CSV contains 'Address' column with URLs (10 pts).
    3. Rewritten URLs (/store/) are present in the Address column (40 pts).
    4. Original URLs (/catalogue/) are NOT present in the Address column (30 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Params
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/SEO/exports/migration_simulation.csv')
    rewrite_from = metadata.get('rewrite_from', 'catalogue')
    rewrite_to = metadata.get('rewrite_to', 'store')
    min_rewritten = metadata.get('min_rewritten_urls', 10)

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Export file not found."}
    
    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Export file exists but was not created during this task."}

    score += 20
    feedback_parts.append("File created successfully")

    # 3. Analyze CSV Content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(result['file_path'], temp_csv.name)
        
        rewritten_count = 0
        original_count = 0
        total_checked = 0
        has_address_col = False
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            
            # Normalize column names (handle BOM or case)
            headers = [h.strip() for h in reader.fieldnames] if reader.fieldnames else []
            address_col = next((h for h in headers if h.lower() in ['address', 'url']), None)
            
            if address_col:
                has_address_col = True
                score += 10 # CSV structure valid
                
                for row in reader:
                    url = row.get(address_col, '')
                    if 'books.toscrape.com' in url:
                        total_checked += 1
                        # Check rewrite logic
                        # Note: We look for path segments. 
                        # Original: .../catalogue/...
                        # Rewritten: .../store/...
                        
                        if f"/{rewrite_to}/" in url:
                            rewritten_count += 1
                        
                        if f"/{rewrite_from}/" in url:
                            original_count += 1
            else:
                feedback_parts.append("CSV missing 'Address' or 'URL' column")

        # Scoring Logic
        
        # Rewritten Presence (40 pts)
        if rewritten_count >= min_rewritten:
            score += 40
            feedback_parts.append(f"Found {rewritten_count} rewritten URLs (/{rewrite_to}/)")
        elif rewritten_count > 0:
            partial = int(40 * (rewritten_count / min_rewritten))
            score += partial
            feedback_parts.append(f"Found {rewritten_count} rewritten URLs (partial credit)")
        else:
            feedback_parts.append(f"No URLs found with '/{rewrite_to}/'")

        # Original Absence (30 pts)
        # We only penalize if we saw valid rows but they weren't rewritten
        if total_checked > 0:
            if original_count == 0:
                score += 30
                feedback_parts.append(f"No original URLs (/{rewrite_from}/) found - Clean rewrite")
            else:
                # Deduct points proportional to failure? Or just 0.
                # If they have 100 originals and 0 rewrites, they get 0 here.
                # If they have 5 originals and 95 rewrites, maybe partial?
                # Let's keep it strict: verifying the rewrite worked implies the old one is gone for those rows.
                # However, if they just exported the "Inlinks" tab, they might see source URLs?
                # The task asked for "Internal > HTML" export. The "Address" column should be the rewritten one.
                feedback_parts.append(f"Found {original_count} URLs still containing '/{rewrite_from}/' - Rewrite incomplete or wrong export")
        else:
            feedback_parts.append("No books.toscrape.com URLs found to check")

    except Exception as e:
        feedback_parts.append(f"Error analyzing CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }