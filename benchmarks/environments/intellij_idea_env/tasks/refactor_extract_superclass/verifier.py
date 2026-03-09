#!/usr/bin/env python3
"""
Verifier for refactor_extract_superclass task.

Criteria:
1. BankAccount.java exists and is abstract (20 pts)
2. Checking/Savings extend BankAccount (20 pts)
3. Duplication removed: balance/accountNumber NOT in subclasses (30 pts)
4. Functional integrity: Tests pass (20 pts)
5. Unique methods preserved (10 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_extract_superclass(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result
    try:
        tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_file.close()
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    bank_content = result.get('bank_account_content', '')
    checking_content = result.get('checking_content', '')
    savings_content = result.get('savings_content', '')
    tests_passed = result.get('tests_passed', False)

    # --- Criterion 1: Superclass Creation (20 pts) ---
    if bank_content:
        # Must be abstract
        if 'abstract class BankAccount' in bank_content or 'abstract public class BankAccount' in bank_content:
            score += 20
            feedback_parts.append("Abstract superclass BankAccount created")
        elif 'class BankAccount' in bank_content:
            score += 10
            feedback_parts.append("Superclass BankAccount created (but not abstract)")
        else:
            feedback_parts.append("BankAccount.java content invalid")
    else:
        feedback_parts.append("BankAccount.java not found")

    # --- Criterion 2: Inheritance (20 pts) ---
    extends_checking = 'extends BankAccount' in checking_content
    extends_savings = 'extends BankAccount' in savings_content
    
    if extends_checking and extends_savings:
        score += 20
        feedback_parts.append("Both subclasses extend BankAccount")
    elif extends_checking or extends_savings:
        score += 10
        feedback_parts.append("Only one subclass extends BankAccount")
    else:
        feedback_parts.append("Subclasses do not extend BankAccount")

    # --- Criterion 3: Duplication Removal (30 pts) ---
    # We check if 'private double balance' still exists in subclasses
    # It SHOULD be removed (or visibility changed, but ideally removed from definition)
    
    # Simple regex to check for field declarations
    field_regex = r'private\s+\w+\s+(balance|accountNumber|owner);'
    
    duplication_found = False
    if re.search(field_regex, checking_content) or re.search(field_regex, savings_content):
        duplication_found = True
        
    # Check methods too
    method_regex = r'public\s+void\s+deposit\('
    
    # Note: If they kept the methods but called super.deposit(), that's okay but usually Extract Superclass removes them.
    # However, for this task, we want them MOVED. A strict check is if they are present in subclasses.
    # If they are present with @Override calling super, that's acceptable but less ideal for "Pull Up".
    # Let's stick to fields as the primary indicator of duplicated state.
    
    if not duplication_found and bank_content:
        # Verify fields ARE in superclass
        if 'balance' in bank_content and 'accountNumber' in bank_content:
            score += 30
            feedback_parts.append("Common fields successfully moved to superclass")
        else:
            score += 10
            feedback_parts.append("Fields removed from subclasses but missing in superclass?")
    else:
        feedback_parts.append("Duplicate fields still present in subclasses")

    # --- Criterion 4: Tests Pass (20 pts) ---
    if tests_passed:
        score += 20
        feedback_parts.append("Tests passed")
    else:
        feedback_parts.append("Tests failed (refactoring broke functionality)")

    # --- Criterion 5: Unique Members Preserved (10 pts) ---
    if 'overdraftLimit' in checking_content and 'interestRate' in savings_content:
        score += 10
        feedback_parts.append("Unique fields preserved in subclasses")
    else:
        feedback_parts.append("Unique fields missing or moved incorrectly")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }