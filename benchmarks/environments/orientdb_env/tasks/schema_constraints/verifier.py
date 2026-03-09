#!/usr/bin/env python3
"""
Verifier for schema_constraints task.

Verifies that the agent correctly applied schema constraints to the OrientDB database.
Checks:
1. Hotels.Name: MANDATORY=true, NOTNULL=true
2. Hotels.Stars: MIN=1, MAX=5
3. Profiles.Email: MANDATORY=true, NOTNULL=true
4. Orders.Price: MIN=0
5. Restaurants.Name: MANDATORY=true, NOTNULL=true
6. Reviews: STRICTMODE=true
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schema_constraints(traj, env_info, task_info):
    """
    Verify the schema constraints using the exported DB schema JSON.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get('schema_retrieved', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not retrieve database schema. Ensure OrientDB is running."
        }

    schema = result.get('schema_snapshot', {})
    classes = schema.get('classes', [])
    
    # Helper to find class by name
    def get_class(name):
        for cls in classes:
            if cls.get('name') == name:
                return cls
        return None

    # Helper to find property in a class
    def get_property(cls_obj, prop_name):
        if not cls_obj:
            return None
        properties = cls_obj.get('properties', [])
        for prop in properties:
            if prop.get('name') == prop_name:
                return prop
        return None

    score = 0
    max_score = 100
    details = []

    # --- 1. Hotels.Name (18 pts) ---
    hotels = get_class('Hotels')
    hotels_name = get_property(hotels, 'Name')
    
    # Check MANDATORY
    if hotels_name and hotels_name.get('mandatory') is True:
        score += 10
        details.append("PASS: Hotels.Name MANDATORY")
    else:
        details.append("FAIL: Hotels.Name MANDATORY")

    # Check NOTNULL
    if hotels_name and hotels_name.get('notNull') is True:
        score += 8
        details.append("PASS: Hotels.Name NOTNULL")
    else:
        details.append("FAIL: Hotels.Name NOTNULL")

    # --- 2. Hotels.Stars (20 pts) ---
    hotels_stars = get_property(hotels, 'Stars')
    
    # Check MIN
    min_val = str(hotels_stars.get('min', '')) if hotels_stars else ''
    if min_val == '1':
        score += 10
        details.append("PASS: Hotels.Stars MIN=1")
    else:
        details.append(f"FAIL: Hotels.Stars MIN (found '{min_val}')")
        
    # Check MAX
    max_val = str(hotels_stars.get('max', '')) if hotels_stars else ''
    if max_val == '5':
        score += 10
        details.append("PASS: Hotels.Stars MAX=5")
    else:
        details.append(f"FAIL: Hotels.Stars MAX (found '{max_val}')")

    # --- 3. Profiles.Email (18 pts) ---
    profiles = get_class('Profiles')
    prof_email = get_property(profiles, 'Email')
    
    if prof_email and prof_email.get('mandatory') is True:
        score += 10
        details.append("PASS: Profiles.Email MANDATORY")
    else:
        details.append("FAIL: Profiles.Email MANDATORY")

    if prof_email and prof_email.get('notNull') is True:
        score += 8
        details.append("PASS: Profiles.Email NOTNULL")
    else:
        details.append("FAIL: Profiles.Email NOTNULL")

    # --- 4. Orders.Price (12 pts) ---
    orders = get_class('Orders')
    orders_price = get_property(orders, 'Price')
    
    min_price = str(orders_price.get('min', '')) if orders_price else ''
    # Convert to float for comparison if it looks numeric, handle string '0'
    try:
        if min_price and float(min_price) == 0:
            score += 12
            details.append("PASS: Orders.Price MIN=0")
        else:
            details.append(f"FAIL: Orders.Price MIN (found '{min_price}')")
    except ValueError:
        details.append(f"FAIL: Orders.Price MIN (found '{min_price}', expected 0)")

    # --- 5. Restaurants.Name (18 pts) ---
    restaurants = get_class('Restaurants')
    rest_name = get_property(restaurants, 'Name')
    
    if rest_name and rest_name.get('mandatory') is True:
        score += 10
        details.append("PASS: Restaurants.Name MANDATORY")
    else:
        details.append("FAIL: Restaurants.Name MANDATORY")
        
    if rest_name and rest_name.get('notNull') is True:
        score += 8
        details.append("PASS: Restaurants.Name NOTNULL")
    else:
        details.append("FAIL: Restaurants.Name NOTNULL")

    # --- 6. Reviews STRICTMODE (14 pts) ---
    reviews = get_class('Reviews')
    if reviews and reviews.get('strictMode') is True:
        score += 14
        details.append("PASS: Reviews STRICTMODE")
    else:
        strict = reviews.get('strictMode', False) if reviews else 'N/A'
        details.append(f"FAIL: Reviews STRICTMODE (found {strict})")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }