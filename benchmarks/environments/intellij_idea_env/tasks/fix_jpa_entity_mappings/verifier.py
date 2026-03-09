#!/usr/bin/env python3
"""
Verifier for fix_jpa_entity_mappings task.
"""

import json
import logging
import re
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_jpa_entity_mappings(traj, env_info, task_info):
    """
    Verifies that the JPA Entity mappings were fixed correctly.
    
    Criteria:
    1. Build/Tests Success (20 pts): 'mvn test' passed with exit code 0.
    2. Category Entity (20 pts): Category.java has @Entity annotation.
    3. Product Columns (30 pts): Product.java maps id->product_id, sku->sku_code, price->unit_price.
    4. Relationship (30 pts): Product.java has @ManyToOne relationship to Category.
    
    Anti-gaming:
    - Fails if schema.sql was modified (agent should fix Java, not DB).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 0. Anti-Gaming Check
    if result.get('schema_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: You modified schema.sql! The task requires fixing the Java mappings to match the existing schema."
        }

    # 1. Build Success (20 pts)
    if result.get('mvn_exit_code') == 0:
        score += 20
        feedback.append("Tests passed successfully.")
    else:
        feedback.append("Tests failed.")

    # 2. Category Entity (20 pts)
    cat_code = result.get('category_content', '')
    if '@Entity' in cat_code:
        score += 20
        feedback.append("Category.java marked with @Entity.")
    else:
        feedback.append("Category.java missing @Entity annotation.")

    # 3. Product Columns (30 pts)
    prod_code = result.get('product_content', '')
    
    # Check for correct @Column annotations
    # We look for combinations like @Column(name="product_id") or name = "product_id"
    col_mappings_score = 0
    
    # Check ID mapping
    if re.search(r'name\s*=\s*"product_id"', prod_code):
        col_mappings_score += 10
    
    # Check SKU mapping
    if re.search(r'name\s*=\s*"sku_code"', prod_code):
        col_mappings_score += 10
        
    # Check Price mapping
    if re.search(r'name\s*=\s*"unit_price"', prod_code):
        col_mappings_score += 10
    
    score += col_mappings_score
    if col_mappings_score == 30:
        feedback.append("All column mappings correct.")
    else:
        feedback.append(f"Column mappings partial score: {col_mappings_score}/30.")

    # 4. Relationship Refactor (30 pts)
    # Check that categoryId was replaced/supplemented by Category object with @ManyToOne
    rel_score = 0
    
    has_many_to_one = '@ManyToOne' in prod_code
    has_category_type = re.search(r'private\s+Category\s+\w+', prod_code)
    has_join_col = re.search(r'name\s*=\s*"category_id"', prod_code)
    
    if has_many_to_one and has_category_type:
        rel_score += 20
        if has_join_col:
            rel_score += 10
            feedback.append("Relationship refactored correctly with @ManyToOne and @JoinColumn.")
        else:
            feedback.append("Relationship refactored but missing explicit @JoinColumn (might rely on default, verified by test).")
    else:
        feedback.append("Relationship NOT refactored to use @ManyToOne Category object.")
        
    score += rel_score

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " ".join(feedback)
    }