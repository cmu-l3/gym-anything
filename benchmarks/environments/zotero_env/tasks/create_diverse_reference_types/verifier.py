#!/usr/bin/env python3
"""
Verifier for create_diverse_reference_types task.
Checks for existence and correctness of 4 specific bibliographic items.
"""

import json
import tempfile
import os

def verify_create_diverse_reference_types(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- 1. THESIS CHECK (20 pts) ---
    thesis = result.get('thesis')
    if thesis:
        item_score = 0
        title = thesis.get('title', '') or ''
        
        if "Non-Cooperative Games".lower() in title.lower():
            item_score += 8
            
            # Author check
            creators = thesis.get('creators', [])
            has_nash = any("Nash" in c.get('lastName', '') for c in creators)
            if has_nash: item_score += 4
            
            # Field checks
            uni = thesis.get('university', '') or ''
            if "Princeton" in uni: item_score += 4
            
            ttype = thesis.get('type', '') or ''
            if "PhD" in ttype or "Dissertation" in ttype: item_score += 2
            
            date = thesis.get('date', '') or ''
            if "1950" in date: item_score += 2
            
            score += item_score
            feedback_parts.append(f"Thesis: Found ({item_score}/20)")
        else:
            feedback_parts.append(f"Thesis: Found but wrong title '{title}'")
    else:
        feedback_parts.append("Thesis: Not found")

    # --- 2. PATENT CHECK (25 pts) ---
    patent = result.get('patent')
    if patent:
        item_score = 0
        title = patent.get('title', '') or ''
        
        if "Cryptographic" in title and "communications" in title:
            item_score += 8
            
            # Inventors check (Rivest, Shamir, Adleman)
            creators = patent.get('creators', [])
            last_names = [c.get('lastName', '') for c in creators]
            inventors_found = sum(1 for name in ["Rivest", "Shamir", "Adleman"] if any(name in ln for ln in last_names))
            item_score += (inventors_found * 2) # max 6
            
            # Field checks
            num = patent.get('patentNumber', '') or ''
            if "4405829" in num: item_score += 4
            
            assignee = patent.get('assignee', '') or ''
            if "MIT" in assignee or "Massachusetts" in assignee: item_score += 3
            
            date = patent.get('date', '') or ''
            if "1983" in date: item_score += 2
            
            # Place check implicit in remaining points or bonus? 
            # Original rubric says Place=US. Let's add it if we are short on points logic, 
            # but matching 25 is: 8+6+4+3+2 = 23. Let's add 2 for place.
            place = patent.get('place', '') or ''
            if "United States" in place or "US" in place: item_score += 2
            
            score += item_score
            feedback_parts.append(f"Patent: Found ({item_score}/25)")
        else:
            feedback_parts.append(f"Patent: Found but wrong title '{title}'")
    else:
        feedback_parts.append("Patent: Not found")

    # --- 3. REPORT CHECK (20 pts) ---
    report = result.get('report')
    if report:
        item_score = 0
        title = report.get('title', '') or ''
        
        if "History of the ARPANET" in title:
            item_score += 8
            
            # Number
            num = report.get('reportNumber', '') or ''
            if "4799" in num: item_score += 4
            
            # Institution
            inst = report.get('institution', '') or ''
            if "Defense" in inst or "DARPA" in inst: item_score += 4
            
            # Date
            date = report.get('date', '') or ''
            if "1981" in date: item_score += 2
            
            # Author (BBN)
            creators = report.get('creators', [])
            has_bbn = any("Bolt" in c.get('lastName', '') or "Bolt" in c.get('firstName', '') for c in creators)
            if has_bbn: item_score += 2
            
            score += item_score
            feedback_parts.append(f"Report: Found ({item_score}/20)")
        else:
            feedback_parts.append(f"Report: Found but wrong title '{title}'")
    else:
        feedback_parts.append("Report: Not found")

    # --- 4. BOOK SECTION CHECK (25 pts) ---
    section = result.get('bookSection')
    if section:
        item_score = 0
        title = section.get('title', '') or ''
        
        if "Computing Machinery" in title:
            item_score += 8
            
            # Author Turing
            creators = section.get('creators', [])
            has_turing = any("Turing" in c.get('lastName', '') and c.get('creatorType') == 'author' for c in creators)
            if has_turing: item_score += 4
            
            # Editor Newman
            has_newman = any("Newman" in c.get('lastName', '') and c.get('creatorType') == 'editor' for c in creators)
            if has_newman: item_score += 4
            
            # Book title
            book_title = section.get('publicationTitle', '') or ''
            if "World of Mathematics" in book_title: item_score += 5
            
            # Publisher
            pub = section.get('publisher', '') or ''
            if "Simon" in pub: item_score += 2
            
            # Pages
            pages = section.get('pages', '') or ''
            if "2099" in pages: item_score += 2
            
            score += item_score
            feedback_parts.append(f"Book Section: Found ({item_score}/25)")
        else:
            feedback_parts.append(f"Book Section: Found but wrong title '{title}'")
    else:
        feedback_parts.append("Book Section: Not found")

    # --- 5. OVERALL CHECK (10 pts) ---
    # Anti-gaming: Ensure total new items is reasonable (approx 4)
    total_new = result.get('total_new_items', 0)
    if total_new >= 4:
        score += 10
        feedback_parts.append("Item count delta correct")
    elif total_new > 0:
        score += 5
        feedback_parts.append(f"Partial item count delta ({total_new})")
    
    # Cap score at 100
    score = min(score, 100)
    
    # Pass threshold 60
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }