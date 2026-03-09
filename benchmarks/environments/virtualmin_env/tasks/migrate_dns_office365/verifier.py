#!/usr/bin/env python3
"""
Verifier for migrate_dns_office365 task.
Checks DNS records for specific Office 365 migration configurations.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_dns_office365(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    records = result.get('dns_records', [])
    
    score = 0
    feedback_parts = []
    
    # Metadata targets
    domain = "acmecorp.test"
    target_mx = "acmecorp-test.mail.protection.outlook.com"
    target_spf_include = "include:spf.protection.outlook.com"
    target_cname = "autodiscover.outlook.com"
    target_srv_host = "sipdir.online.lync.com"

    # --- 1. Check MX Records (35 pts total) ---
    # Goal: Legacy gone (15), New correct (20)
    
    mx_records = [r for r in records if r['type'] == 'MX']
    
    # Check for legacy (local) MX
    # Legacy usually points to 'acmecorp.test.' or 'mail.acmecorp.test.'
    has_legacy_mx = False
    for r in mx_records:
        target = r.get('target', '').rstrip('.')
        if target in [domain, f"mail.{domain}", "localhost"]:
            has_legacy_mx = True
    
    if not has_legacy_mx and len(mx_records) > 0:
        score += 15
        feedback_parts.append("Legacy MX removed")
    elif has_legacy_mx:
        feedback_parts.append("Legacy MX record still present")
    
    # Check for new Office 365 MX
    has_correct_mx = False
    for r in mx_records:
        target = r.get('target', '').rstrip('.').lower()
        priority = r.get('priority', '100')
        
        # Priority should be 0, target should match
        if target == target_mx.lower() and int(priority) == 0:
            has_correct_mx = True
            break
            
    if has_correct_mx:
        score += 20
        feedback_parts.append("Office 365 MX configured")
    else:
        feedback_parts.append(f"Missing or incorrect Office 365 MX record (expected prio 0, target {target_mx})")

    # --- 2. Check SPF Record (20 pts) ---
    # Goal: Updated existing record, contains include
    
    txt_records = [r for r in records if r['type'] == 'TXT']
    spf_records = [r for r in txt_records if "v=spf1" in r['value']]
    
    spf_correct = False
    if len(spf_records) == 1:
        val = spf_records[0]['value'].lower()
        if target_spf_include in val and "-all" in val:
            score += 20
            spf_correct = True
            feedback_parts.append("SPF record updated successfully")
        else:
            feedback_parts.append("SPF record exists but missing required Office 365 include or hard fail")
    elif len(spf_records) > 1:
        feedback_parts.append("Multiple SPF records detected (invalid DNS configuration)")
    else:
        feedback_parts.append("No SPF record found")

    # --- 3. Check CNAME (15 pts) ---
    # Goal: autodiscover -> autodiscover.outlook.com
    
    cname_records = [r for r in records if r['type'] == 'CNAME']
    autodisc_correct = False
    
    for r in cname_records:
        name = r.get('name', '').rstrip('.')
        target = r.get('value', '').rstrip('.').lower()
        
        # Name might be 'autodiscover' or 'autodiscover.acmecorp.test.'
        if name == "autodiscover" or name.startswith("autodiscover."):
            if target == target_cname.lower():
                autodisc_correct = True
                break
    
    if autodisc_correct:
        score += 15
        feedback_parts.append("Autodiscover CNAME correct")
    else:
        feedback_parts.append("Autodiscover CNAME missing or incorrect")

    # --- 4. Check SRV (30 pts total) ---
    # Goal: Exists (10), Details correct (20)
    
    srv_records = [r for r in records if r['type'] == 'SRV']
    srv_found = False
    srv_details_correct = False
    
    for r in srv_records:
        # Name check: _sip._tls...
        name = r.get('name', '')
        if "_sip" in name and "_tls" in name:
            srv_found = True
            
            # Detail check
            # Priority 100, Weight 1, Port 443, Target sipdir...
            prio = r.get('priority', '-1')
            weight = r.get('weight', '-1')
            port = r.get('port', '-1')
            target = r.get('target', '').rstrip('.').lower()
            
            if (int(prio) == 100 and 
                int(weight) == 1 and 
                int(port) == 443 and 
                target == target_srv_host.lower()):
                srv_details_correct = True
            break
            
    if srv_found:
        score += 10
        if srv_details_correct:
            score += 20
            feedback_parts.append("SRV record correct")
        else:
            feedback_parts.append("SRV record found but values (port/weight/prio/target) incorrect")
    else:
        feedback_parts.append("SRV record not found")

    # --- Final Result ---
    # Pass threshold: 65 (Must get MX (35) + SPF (20) + CNAME/SRV partial)
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }