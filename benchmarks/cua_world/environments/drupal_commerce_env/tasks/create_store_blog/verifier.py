#!/usr/bin/env python3
"""
Verifier for Create Store Blog task in Drupal Commerce.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_store_blog(traj, env_info, task_info):
    """
    Verify the creation of blog content type, vocabulary, post, and view.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_terms = set([t.lower() for t in metadata.get('expected_terms', [])])
    sample_title = metadata.get('sample_post_title', '').lower()
    target_prod_sku = metadata.get('target_product_sku', '') # Note: Verifier gets title from export
    
    # We expect the Sony headphones title
    expected_prod_title = "Sony WH-1000XM5 Wireless Headphones".lower() 
    expected_term_ref = "Product News".lower()

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # Criterion 1: Vocabulary exists (10 pts)
    if result.get('vocabulary_exists'):
        score += 10
        feedback_parts.append("Vocabulary 'Blog Categories' created")
    else:
        feedback_parts.append("Vocabulary 'Blog Categories' NOT found")

    # Criterion 2: Terms exist (10 pts)
    found_terms_str = result.get('terms_found', '')
    found_terms = set([t.strip().lower() for t in found_terms_str.split(',') if t.strip()])
    
    # Check if all expected terms are present
    missing_terms = expected_terms - found_terms
    if not missing_terms and expected_terms:
        score += 10
        feedback_parts.append("All taxonomy terms found")
    elif len(found_terms) > 0:
        score += 5
        feedback_parts.append(f"Some terms found, missing: {list(missing_terms)}")
    else:
        feedback_parts.append("No taxonomy terms found")

    # Criterion 3: Content Type exists (15 pts)
    if result.get('content_type_exists'):
        score += 15
        feedback_parts.append("Content Type 'Store Blog Post' created")
    else:
        feedback_parts.append("Content Type 'Store Blog Post' NOT found")

    # Criterion 4: Fields exist (25 pts total)
    fields_score = 0
    if result.get('field_featured_product_exists'):
        fields_score += 15
        feedback_parts.append("Featured Product field exists")
    else:
        feedback_parts.append("Featured Product field missing")

    if result.get('field_blog_category_exists'):
        fields_score += 10
        feedback_parts.append("Blog Category field exists")
    else:
        feedback_parts.append("Blog Category field missing")
    score += fields_score

    # Criterion 5: Blog Post created correctly (25 pts total)
    node_score = 0
    if result.get('node_found'):
        # Check Title
        actual_title = result.get('node_title', '').lower()
        if sample_title in actual_title:
            node_score += 10
            feedback_parts.append("Blog post created with correct title")
        else:
            feedback_parts.append(f"Blog post found but title mismatch ('{actual_title}')")
            node_score += 5

        # Check References
        ref_prod = result.get('referenced_product', '').lower()
        ref_term = result.get('referenced_category', '').lower()
        
        if expected_prod_title in ref_prod:
            node_score += 10
            feedback_parts.append("Product correctly referenced")
        else:
            feedback_parts.append(f"Product reference mismatch ('{ref_prod}')")
            
        if expected_term_ref in ref_term:
            node_score += 5
            feedback_parts.append("Category correctly referenced")
        else:
            feedback_parts.append(f"Category reference mismatch ('{ref_term}')")
            
        # Check published status
        if str(result.get('node_status')) == "1":
            feedback_parts.append("Post is published")
        else:
            feedback_parts.append("Post is NOT published")
    else:
        feedback_parts.append("No 'Store Blog Post' node found")
    score += node_score

    # Criterion 6: View exists and accessible (15 pts)
    view_status = int(result.get('view_http_status', 0))
    view_config = result.get('view_config_exists')
    
    if view_status == 200:
        score += 15
        feedback_parts.append("View page accessible at /store-blog")
    elif view_config:
        score += 10
        feedback_parts.append("View config found but page not returning 200 OK")
    else:
        feedback_parts.append("View not found")

    # Final Pass Check
    # Threshold 65/100
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }