#!/usr/bin/env python3
"""
Verifier for create_faq_entries task in Vtiger CRM.

Verifies the creation of multiple FAQ records, their rich text content,
dropdown fields (status/category), and anti-gaming constraints.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_faq_entries(traj, env_info, task_info):
    """
    Verify that three distinct FAQ entries were successfully created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_faqs = metadata.get('expected_faqs', [])

    if len(expected_faqs) != 3:
        return {"passed": False, "score": 0, "feedback": "Invalid metadata: Expected 3 FAQs"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_faq_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    faqs = result.get('faqs', [])
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    initial_max_id = result.get('initial_max_id', 0)

    score = 0
    feedback_parts = []
    
    newly_created_ids = []
    valid_ownership_count = 0

    # 1. Verification of the 3 FAQ entries
    for i, expected in enumerate(expected_faqs, start=1):
        q_match = expected['question_match'].lower()
        keywords = [kw.lower() for kw in expected['answer_keywords']]
        exp_category = expected['category']
        exp_status = expected['status']

        # Find matching FAQ in database dump
        matched_faq = None
        for faq in faqs:
            if q_match in faq.get('question', '').lower():
                matched_faq = faq
                break
        
        if matched_faq:
            score += 10
            feedback_parts.append(f"FAQ {i} question found")
            
            # Record for anti-gaming checks
            newly_created_ids.append(matched_faq['id'])
            if matched_faq['smownerid'] > 0:
                valid_ownership_count += 1

            # Check answer content
            answer_text = matched_faq.get('answer', '').lower()
            if all(kw in answer_text for kw in keywords):
                score += 10
                feedback_parts.append(f"FAQ {i} answer correct")
            else:
                missing = [kw for kw in keywords if kw not in answer_text]
                feedback_parts.append(f"FAQ {i} answer missing keywords: {missing}")

            # Check picklists
            actual_cat = matched_faq.get('category', '')
            actual_status = matched_faq.get('status', '')
            if actual_cat == exp_category and actual_status == exp_status:
                score += 5
                feedback_parts.append(f"FAQ {i} status/category correct")
            else:
                feedback_parts.append(f"FAQ {i} incorrect status/category (Got: {actual_status}/{actual_cat})")
        else:
            feedback_parts.append(f"FAQ {i} NOT found")

    # 2. Anti-gaming checks
    # Check net count increase
    if current_count >= initial_count + 3:
        score += 10
        feedback_parts.append("Net FAQ count increased by 3+")
    else:
        feedback_parts.append(f"FAQ count did not increase by 3 (Initial: {initial_count}, Current: {current_count})")

    # Check that matched records were created during this session (id > initial_max_id)
    new_records_count = sum(1 for cid in newly_created_ids if cid > initial_max_id)
    if new_records_count == 3:
        score += 10
        feedback_parts.append("Records verified as newly created")
    else:
        feedback_parts.append(f"Only {new_records_count}/3 records were newly created")

    # Check CRM ownership (proves it wasn't a raw sql injection)
    if valid_ownership_count == 3:
        score += 5
        feedback_parts.append("CRM ownership validated")
    else:
        feedback_parts.append(f"Invalid ownership on {3 - valid_ownership_count} records")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }