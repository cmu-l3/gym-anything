#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime, date, timedelta

def verify_structured_quotation_builder(traj, env_info, task_info):
    """
    Verifies the structured quotation task.
    
    Criteria:
    1. Quotation exists for correct customer (10 pts)
    2. Quotation is in Draft state (NOT confirmed) (10 pts)
    3. Expiration date is ~30 days from today (10 pts)
    4. Total amount is correct (~$58,710) (10 pts)
    5. Structural integrity (Order and type of lines) (60 pts total)
       - Section 1 present & correct (10)
       - Section 2 present & correct (10)
       - Products correct & in correct sections (20)
       - Notes present & correct (20)
    """
    
    # 1. Retrieve Result JSON using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    temp_path = tempfile.mktemp()
    try:
        copy_from_env('/tmp/task_result.json', temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task result file not found. Did the task complete?"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    # 2. Basic Validation
    if not result.get('quotation_found'):
        return {"passed": False, "score": 0, "feedback": "No quotation found for customer 'Aurora Dynamics Inc.'"}

    score = 0
    feedback = []
    
    meta = result.get('meta', {})
    lines = result.get('lines', [])

    # Criterion 1: Quotation Found (Already checked existence, giving points)
    score += 10
    feedback.append("Quotation found.")

    # Criterion 2: Draft State
    state = meta.get('state', '')
    if state in ['draft', 'sent']:
        score += 10
        feedback.append("Quotation is in Draft/Sent state (Correct).")
    else:
        feedback.append(f"Quotation state is '{state}' (Expected Draft/Sent).")
        # Penalty for confirming if strictly forbidden? Task says "do NOT confirm".
        # We just don't give points.

    # Criterion 3: Expiration Date (30 days +/- 1 day)
    validity_date_str = meta.get('validity_date')
    if validity_date_str:
        try:
            val_date = datetime.strptime(validity_date_str, '%Y-%m-%d').date()
            target_date = date.today() + timedelta(days=30)
            delta = abs((val_date - target_date).days)
            if delta <= 1:
                score += 10
                feedback.append(f"Expiration date {validity_date_str} is correct.")
            else:
                feedback.append(f"Expiration date {validity_date_str} is incorrect (Expected ~{target_date}).")
        except:
            feedback.append("Could not parse expiration date.")
    else:
        feedback.append("Expiration date not set.")

    # Criterion 4: Total Amount
    # Expected: 58710.0
    amount = float(meta.get('amount_total', 0))
    expected_amount = 58710.0
    if abs(amount - expected_amount) < 100: # Allow small tolerance
        score += 10
        feedback.append(f"Total amount ${amount} is correct.")
    else:
        feedback.append(f"Total amount ${amount} is incorrect (Expected ${expected_amount}).")

    # Criterion 5: Structure Verification
    # Expected structure:
    # 0: Section "Workstation..."
    # 1: Product "Desk"
    # 2: Product "Chair"
    # 3: Note "warranty"
    # 4: Section "Technology..."
    # 5: Product "Laptop"
    # 6: Product "Mouse"
    # 7: Note "support"

    structural_score = 0
    
    if len(lines) >= 8:
        # Check Section 1
        l0 = lines[0]
        if l0['display_type'] == 'line_section' and 'workstation' in l0['name'].lower():
            structural_score += 7.5
        else:
            feedback.append("Line 1 should be 'Workstation' section.")

        # Check Product 1
        l1 = lines[1]
        if not l1['display_type'] and 'desk' in (l1['product_name'] or '').lower() and l1['qty'] == 20:
            structural_score += 7.5
        else:
            feedback.append("Line 2 should be 20 Desks.")

        # Check Product 2
        l2 = lines[2]
        if not l2['display_type'] and 'chair' in (l2['product_name'] or '').lower() and l2['qty'] == 20:
            structural_score += 7.5
        else:
            feedback.append("Line 3 should be 20 Chairs.")

        # Check Note 1
        l3 = lines[3]
        if l3['display_type'] == 'line_note' and 'warranty' in l3['name'].lower():
            structural_score += 7.5
        else:
            feedback.append("Line 4 should be Warranty note.")

        # Check Section 2
        l4 = lines[4]
        if l4['display_type'] == 'line_section' and 'technology' in l4['name'].lower():
            structural_score += 7.5
        else:
            feedback.append("Line 5 should be 'Technology' section.")

        # Check Product 3
        l5 = lines[5]
        if not l5['display_type'] and 'laptop' in (l5['product_name'] or '').lower() and l5['qty'] == 25:
            structural_score += 7.5
        else:
            feedback.append("Line 6 should be 25 Laptops.")

        # Check Product 4
        l6 = lines[6]
        if not l6['display_type'] and 'mouse' in (l6['product_name'] or '').lower() and l6['qty'] == 25:
            structural_score += 7.5
        else:
            feedback.append("Line 7 should be 25 Mice.")

        # Check Note 2
        l7 = lines[7]
        if l7['display_type'] == 'line_note' and 'support' in l7['name'].lower():
            structural_score += 7.5
        else:
            feedback.append("Line 8 should be Support note.")

    else:
        feedback.append(f"Incorrect number of lines: found {len(lines)}, expected 8.")
        # Partial credit logic for out-of-order lines could go here, 
        # but strict structure is the goal.
        # Let's check simply for existence of components to be generous if order is slightly off
        # but key items are present.
        
        section_count = sum(1 for l in lines if l['display_type'] == 'line_section')
        note_count = sum(1 for l in lines if l['display_type'] == 'line_note')
        prod_count = sum(1 for l in lines if not l['display_type'])
        
        if section_count >= 2: structural_score += 10
        if note_count >= 2: structural_score += 10
        if prod_count >= 4: structural_score += 10

    score += structural_score
    feedback.append(f"Structural verification score: {structural_score}/60")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }