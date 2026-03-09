#!/usr/bin/env python3
"""
Verifier for add_network_security_config task.

Criteria:
1. network_security_config.xml exists at correct path (10 pts)
2. Valid XML structure (5 pts)
3. Base config disables cleartext traffic (10 pts)
4. Production domain (api.weatherstack.com) configured (10 pts)
5. includeSubdomains set to true (5 pts)
6. Two specific certificate pins present (15 pts)
7. Pin expiration set to 2025-12-31 (5 pts)
8. Dev domain (10.0.2.2) allows cleartext (10 pts)
9. Debug overrides trust user CA (10 pts)
10. Manifest references the config file (15 pts)
11. Build/Resource validation passed (5 pts)

Anti-gaming:
- XML file must be created during task session.
- Manifest must be modified from initial state.
"""

import json
import logging
import os
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_network_security_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    expected_domain = metadata.get('expected_domain', 'api.weatherstack.com')
    expected_dev_domain = metadata.get('expected_dev_domain', '10.0.2.2')
    expected_pins = metadata.get('expected_pins', [])
    expected_expiration = metadata.get('expected_expiration', '2025-12-31')

    score = 0
    feedback = []
    
    # Check 1: File Exists & Created During Task (Anti-Gaming)
    if not result.get('nsc_exists'):
        return {"passed": False, "score": 0, "feedback": "FAIL: network_security_config.xml not found."}
    
    if not result.get('nsc_created_during_task'):
        feedback.append("WARNING: File timestamp suggests it wasn't created during this session.")
        # We penalize but don't fail immediately in case of clock oddities, but strictly it's suspicious
        score += 5 # Half points for existence
    else:
        score += 10
        feedback.append("PASS: XML file created.")

    # Parse XML
    nsc_content = result.get('nsc_content', '')
    root = None
    try:
        root = ET.fromstring(nsc_content)
        if root.tag == 'network-security-config':
            score += 5
            feedback.append("PASS: Valid XML root.")
        else:
            feedback.append("FAIL: Invalid XML root element.")
    except ET.ParseError:
        feedback.append("FAIL: XML parsing error.")
        # Stop here if XML is invalid
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Check 3: Base Config
    base_config = root.find('base-config')
    base_cleartext = False
    if base_config is not None:
        val = base_config.get('cleartextTrafficPermitted', '').lower()
        if val == 'false':
            base_cleartext = True
    
    if base_cleartext:
        score += 10
        feedback.append("PASS: Base config disables cleartext.")
    else:
        feedback.append("FAIL: Base config does not disable cleartext traffic.")

    # Check 4 & 5: Production Domain
    prod_domain_found = False
    subdomains_ok = False
    prod_config = None

    for dc in root.findall('domain-config'):
        for d in dc.findall('domain'):
            if d.text and expected_domain in d.text:
                prod_domain_found = True
                prod_config = dc
                if d.get('includeSubdomains', '').lower() == 'true':
                    subdomains_ok = True
                break
        if prod_domain_found:
            break
    
    if prod_domain_found:
        score += 10
        feedback.append(f"PASS: Domain config for {expected_domain} found.")
    else:
        feedback.append(f"FAIL: Domain config for {expected_domain} missing.")

    if subdomains_ok:
        score += 5
        feedback.append("PASS: includeSubdomains enabled.")
    else:
        feedback.append("FAIL: includeSubdomains missing or false.")

    # Check 6 & 7: Pins & Expiration
    pins_found = 0
    expiration_ok = False
    
    if prod_config is not None:
        pin_set = prod_config.find('pin-set')
        if pin_set is not None:
            # Check expiration
            if pin_set.get('expiration') == expected_expiration:
                expiration_ok = True
            
            # Check pins
            current_pins = []
            for p in pin_set.findall('pin'):
                digest = p.get('digest', '').lower()
                val = (p.text or '').strip()
                # Normalize format: digest can be attribute or part of text depending on agent style
                # Standard Android is <pin digest="SHA-256">base64</pin>
                # But we check flexible text match
                if val:
                    current_pins.append(val)
            
            # Check if expected pins exist in current pins
            # Expected format: "sha256/hash..."
            # XML content usually just hash.
            for exp_pin in expected_pins:
                exp_hash = exp_pin.split('/')[-1]
                if any(exp_hash in cp for cp in current_pins):
                    pins_found += 1
    
    if pins_found >= 2:
        score += 15
        feedback.append("PASS: Both certificate pins found.")
    elif pins_found == 1:
        score += 7
        feedback.append("PARTIAL: Only one pin found.")
    else:
        feedback.append("FAIL: Certificate pins missing.")

    if expiration_ok:
        score += 5
        feedback.append(f"PASS: Expiration set to {expected_expiration}.")
    else:
        feedback.append(f"FAIL: Pin expiration incorrect or missing.")

    # Check 8: Dev Domain
    dev_ok = False
    for dc in root.findall('domain-config'):
        if dc.get('cleartextTrafficPermitted', '').lower() == 'true':
            for d in dc.findall('domain'):
                if d.text and expected_dev_domain in d.text:
                    dev_ok = True
                    break
        if dev_ok: break
    
    if dev_ok:
        score += 10
        feedback.append(f"PASS: Dev domain {expected_dev_domain} allows cleartext.")
    else:
        feedback.append("FAIL: Dev domain cleartext configuration missing.")

    # Check 9: Debug Overrides
    debug_ok = False
    debug_overrides = root.find('debug-overrides')
    if debug_overrides is not None:
        trust_anchors = debug_overrides.find('trust-anchors')
        if trust_anchors is not None:
            # Check for certificates src="user"
            for cert in trust_anchors.findall('certificates'):
                if cert.get('src', '').lower() == 'user':
                    debug_ok = True
                    break
    
    if debug_ok:
        score += 10
        feedback.append("PASS: Debug overrides trust user CAs.")
    else:
        feedback.append("FAIL: Debug overrides for user CAs missing.")

    # Check 10: Manifest Reference
    manifest_content = result.get('manifest_content', '')
    manifest_modified = result.get('manifest_modified', False)
    
    if not manifest_modified:
        feedback.append("ANTI-GAMING: Manifest was not modified.")
        # If manifest wasn't modified, they can't get points for referencing the file
    elif 'android:networkSecurityConfig="@xml/network_security_config"' in manifest_content or \
         "android:networkSecurityConfig='@xml/network_security_config'" in manifest_content:
        score += 15
        feedback.append("PASS: Manifest references network security config.")
    else:
        feedback.append("FAIL: Manifest does not reference the config file correctly.")

    # Check 11: Build Validity
    if result.get('build_valid'):
        score += 5
        feedback.append("PASS: Project build/resource validation successful.")
    else:
        feedback.append("FAIL: Project failed resource validation (check XML syntax).")

    # Final Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }