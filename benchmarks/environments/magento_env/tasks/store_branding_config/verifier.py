#!/usr/bin/env python3
"""Verifier for Store Branding Config task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_store_branding(traj, env_info, task_info):
    """
    Verify store branding configuration.
    
    Checks 3 main areas:
    1. Store Information (Name, Address, Phone, Hours)
    2. Store Email Addresses (General, Sales, Support)
    3. Design Settings (Head Title, Meta Desc, Welcome Text, Copyright)
    
    Pass threshold: 60 points
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/branding_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    # Check if config changed at all
    if not result.get('meta', {}).get('config_changed', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No configuration changes detected in database."
        }

    # 1. Store Information (40 pts total)
    info = result.get('store_info', {})
    
    # Store Name (10 pts)
    if info.get('name', '').strip() == "Terra & Clay Studio":
        score += 10
        feedback_parts.append("Store name correct")
    
    # Phone (5 pts)
    if "(505) 555-0142" in info.get('phone', ''):
        score += 5
    
    # Hours (5 pts)
    hours = info.get('hours', '').lower()
    if "mon-fri" in hours and "sat" in hours:
        score += 5
        
    # Address (15 pts - 3 pts each component)
    addr_score = 0
    if info.get('country', '') == 'US': addr_score += 3
    if info.get('city', '').lower() == 'santa fe': addr_score += 3
    if '214 canyon' in info.get('street', '').lower(): addr_score += 3
    if '87501' in info.get('zip', ''): addr_score += 3
    # Region can be ID (32 for NM) or text
    rid = str(info.get('region_id', ''))
    rtext = info.get('region', '').lower()
    if rid == '36' or rid == '32' or 'new mexico' in rtext: # 32 is standard Magento ID for NM, allowing 36 just in case
        addr_score += 3
    
    if addr_score > 0:
        score += addr_score
        feedback_parts.append(f"Address partially correct ({addr_score}/15 pts)")

    # 2. Emails (30 pts total)
    emails = result.get('emails', {})
    
    # General (10 pts)
    if "Terra & Clay Studio" in emails.get('general_name', '') and \
       "hello@terraandclay.com" in emails.get('general_email', ''):
        score += 10
        feedback_parts.append("General contact correct")
        
    # Sales (10 pts)
    if "Terra & Clay Orders" in emails.get('sales_name', '') and \
       "orders@terraandclay.com" in emails.get('sales_email', ''):
        score += 10
        feedback_parts.append("Sales contact correct")
        
    # Support (10 pts)
    if "Terra & Clay Support" in emails.get('support_name', '') and \
       "support@terraandclay.com" in emails.get('support_email', ''):
        score += 10
        feedback_parts.append("Support contact correct")

    # 3. Design (30 pts total)
    design = result.get('design', {})
    
    # Head Title (10 pts)
    if "Terra & Clay Studio" in design.get('head_title', ''):
        score += 10
        feedback_parts.append("Page title correct")
        
    # Meta Description (10 pts)
    if "handcrafted pottery" in design.get('head_desc', '').lower():
        score += 10
        feedback_parts.append("Meta description correct")
        
    # Welcome Text (5 pts)
    if "Terra & Clay Studio" in design.get('welcome', ''):
        score += 5
        
    # Copyright (5 pts)
    if "2025 Terra & Clay Studio" in design.get('copyright', ''):
        score += 5

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }