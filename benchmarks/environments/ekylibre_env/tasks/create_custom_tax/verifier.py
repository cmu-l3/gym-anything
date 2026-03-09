#!/usr/bin/env python3
"""
Verifier for create_custom_tax task in Ekylibre.

Criteria:
1. New tax record exists (count increased) - 20 pts
2. Rate is exactly 5.5 (or 0.055) - 30 pts
3. Name contains relevant keywords ("TVA" + "5.5") - 20 pts
4. Country is France ("fr") - 10 pts
5. Record was created AFTER task start (Anti-gaming) - 20 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_tax(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # Extract data
    initial_count = int(result.get('initial_tax_count', 0))
    current_count = int(result.get('current_tax_count', 0))
    new_tax = result.get('new_tax_record')
    task_start = float(result.get('task_start', 0))

    # Criterion 1: Tax count increased
    if current_count > initial_count:
        score += 20
        feedback_parts.append(f"Tax count increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append("Tax count did not increase")

    # If no tax found, stop here
    if not new_tax:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No tax record found matching criteria."
        }

    # Inspect the found record
    tax_name = str(new_tax.get('name', '')).strip()
    tax_amount = float(new_tax.get('amount', 0))
    tax_country = str(new_tax.get('country', '')).lower()
    created_epoch = float(new_tax.get('created_epoch', 0))

    # Criterion 2: Rate is correct (5.5)
    # Ekylibre might store as 5.5 or 0.055 depending on version/config
    if abs(tax_amount - 5.5) < 0.01 or abs(tax_amount - 0.055) < 0.001:
        score += 30
        feedback_parts.append(f"Rate correct ({tax_amount})")
    else:
        feedback_parts.append(f"Incorrect rate: {tax_amount} (expected 5.5)")

    # Criterion 3: Name match
    name_lower = tax_name.lower()
    if "tva" in name_lower and ("5.5" in name_lower or "5,5" in name_lower):
        score += 20
        feedback_parts.append("Name format correct")
    elif "tva" in name_lower:
        score += 10
        feedback_parts.append("Name contains TVA but missing '5.5'")
    else:
        feedback_parts.append(f"Name '{tax_name}' mismatch")

    # Criterion 4: Country
    if tax_country in ['fr', 'france']:
        score += 10
        feedback_parts.append("Country correct")
    else:
        feedback_parts.append(f"Country mismatch ({tax_country})")

    # Criterion 5: Anti-gaming (Time check)
    # Allow a small buffer for clock skew, but generally created_epoch should be >= task_start
    if created_epoch >= task_start - 5:
        score += 20
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("Record predates task start (pre-existing)")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }