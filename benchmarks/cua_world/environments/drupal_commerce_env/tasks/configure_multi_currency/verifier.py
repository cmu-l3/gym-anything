#!/usr/bin/env python3
"""
Verifier for configure_multi_currency task.

Score Breakdown (100 pts):
1. Import EUR currency (10 pts)
2. Import GBP currency (10 pts)
3. Add EUR to Store (15 pts)
4. Add GBP to Store (15 pts)
5. Create EU Product (25 pts)
   - Exists & Published (10)
   - Correct Price (5)
   - Correct Currency (10)
6. Create UK Product (25 pts)
   - Exists & Published (10)
   - Correct Price (5)
   - Correct Currency (10)

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_configure_multi_currency(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_multi_currency_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # 1. Check Currencies (20 pts)
    if result.get('has_eur_currency'):
        score += 10
        feedback.append("EUR currency imported.")
    else:
        feedback.append("EUR currency NOT imported.")

    if result.get('has_gbp_currency'):
        score += 10
        feedback.append("GBP currency imported.")
    else:
        feedback.append("GBP currency NOT imported.")

    # 2. Check Store Config (30 pts)
    if result.get('store_supports_eur'):
        score += 15
        feedback.append("Store supports EUR.")
    else:
        feedback.append("Store does NOT support EUR.")

    if result.get('store_supports_gbp'):
        score += 15
        feedback.append("Store supports GBP.")
    else:
        feedback.append("Store does NOT support GBP.")

    # 3. Check EU Product (25 pts)
    eu = result.get('eu_product', {})
    if eu.get('exists') and eu.get('published'):
        score += 10
        
        # Check Price (allow string/float comparison)
        try:
            p = float(eu.get('price', 0))
            if abs(p - 24.99) < 0.01:
                score += 5
            else:
                feedback.append(f"EU Product price mismatch: {p} != 24.99")
        except:
            feedback.append("EU Product price invalid.")

        # Check Currency
        if eu.get('currency') == 'EUR':
            score += 10
        else:
            feedback.append(f"EU Product currency wrong: {eu.get('currency')} != EUR")
            
        feedback.append("EU Product created.")
    else:
        feedback.append("EU Product missing or unpublished.")

    # 4. Check UK Product (25 pts)
    uk = result.get('uk_product', {})
    if uk.get('exists') and uk.get('published'):
        score += 10
        
        try:
            p = float(uk.get('price', 0))
            if abs(p - 12.99) < 0.01:
                score += 5
            else:
                feedback.append(f"UK Product price mismatch: {p} != 12.99")
        except:
            feedback.append("UK Product price invalid.")

        if uk.get('currency') == 'GBP':
            score += 10
        else:
            feedback.append(f"UK Product currency wrong: {uk.get('currency')} != GBP")

        feedback.append("UK Product created.")
    else:
        feedback.append("UK Product missing or unpublished.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }