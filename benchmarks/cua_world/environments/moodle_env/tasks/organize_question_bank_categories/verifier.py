#!/usr/bin/env python3
"""Verifier for Organize Question Bank task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_question_bank_categories(traj, env_info, task_info):
    """
    Verify proper organization of the question bank.
    
    Rubric:
    1. Category "Atomic Structure" exists in course context (15 pts)
    2. Category "Chemical Bonding" exists in course context (15 pts)
    3. Both new categories are children of the Default category (or top level) (10 pts)
    4. 5 "Atom_" questions are in "Atomic Structure" (25 pts)
    5. 5 "Bond_" questions are in "Chemical Bonding" (25 pts)
    6. Default category is empty of these specific questions (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    atom_cat_name = metadata.get('cat_atom_name', 'Atomic Structure')
    bond_cat_name = metadata.get('cat_bond_name', 'Chemical Bonding')
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    categories = result.get('categories', [])
    questions = result.get('questions', [])
    default_cat_id = result.get('default_cat_id', '0')
    
    # 1. Check Categories
    atom_cat = next((c for c in categories if c['name'].strip().lower() == atom_cat_name.lower()), None)
    bond_cat = next((c for c in categories if c['name'].strip().lower() == bond_cat_name.lower()), None)
    
    if atom_cat:
        score += 15
        feedback.append(f"Category '{atom_cat_name}' created.")
    else:
        feedback.append(f"Category '{atom_cat_name}' NOT found.")
        
    if bond_cat:
        score += 15
        feedback.append(f"Category '{bond_cat_name}' created.")
    else:
        feedback.append(f"Category '{bond_cat_name}' NOT found.")
        
    # 2. Check Parent Structure
    # We expect them to be children of the default category (or whatever default_cat_id is)
    parent_ok = True
    if atom_cat and str(atom_cat['parent']) != str(default_cat_id):
        # Allow if parent is top-level (0) but preferable to be under default if specified, 
        # but task desc said "subcategories inside Default".
        feedback.append(f"Atomic Structure parent is {atom_cat['parent']}, expected {default_cat_id}.")
        parent_ok = False
    if bond_cat and str(bond_cat['parent']) != str(default_cat_id):
        feedback.append(f"Chemical Bonding parent is {bond_cat['parent']}, expected {default_cat_id}.")
        parent_ok = False
        
    if atom_cat and bond_cat and parent_ok:
        score += 10
        feedback.append("Category hierarchy correct.")
    elif atom_cat and bond_cat:
        # Partial credit if categories exist but hierarchy is slightly off (e.g. top level)
        score += 5
        feedback.append("Categories exist but parent hierarchy mismatch.")

    # 3. Check Question Locations
    atom_qs = [q for q in questions if q['question_name'].startswith('Atom_')]
    bond_qs = [q for q in questions if q['question_name'].startswith('Bond_')]
    
    # Check Atoms
    atom_correct_count = 0
    if atom_cat:
        for q in atom_qs:
            if str(q['category_id']) == str(atom_cat['id']):
                atom_correct_count += 1
    
    # Check Bonds
    bond_correct_count = 0
    if bond_cat:
        for q in bond_qs:
            if str(q['category_id']) == str(bond_cat['id']):
                bond_correct_count += 1
                
    # Score Atoms (5 pts per question)
    score += (atom_correct_count * 5)
    if atom_correct_count == 5:
        feedback.append("All Atom questions moved correctly.")
    else:
        feedback.append(f"{atom_correct_count}/5 Atom questions moved.")
        
    # Score Bonds (5 pts per question)
    score += (bond_correct_count * 5)
    if bond_correct_count == 5:
        feedback.append("All Bond questions moved correctly.")
    else:
        feedback.append(f"{bond_correct_count}/5 Bond questions moved.")

    # 4. Check Default Category Empty (of these questions)
    # If all moved, this naturally passes, but let's verify explicitly
    leftover = [q for q in questions if str(q['category_id']) == str(default_cat_id)]
    if len(leftover) == 0 and len(questions) > 0:
        score += 10
        feedback.append("Default category is clean.")
    elif len(questions) == 0:
         feedback.append("No questions found (Setup error?).")
    else:
         feedback.append(f"{len(leftover)} questions still in default category.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }