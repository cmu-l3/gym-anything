#!/usr/bin/env python3
"""
Verifier for first_party_circuit_isolation_audit task.
Validates Tor Browser's circuit isolation via IP extraction and browser history.
"""

import json
import os
import tempfile
import logging
import ipaddress

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_circuit_isolation_audit(traj, env_info, task_info):
    """
    Scoring system (100 points total):
    1. JSON Structure (20 pts): Output file exists, parses, has all 3 target domains as keys.
    2. Valid IP Formats (15 pts): Values are correctly formatted IPv4/IPv6 strings.
    3. Browser History (25 pts): All 3 domains are present in Tor Browser's SQLite history.
    4. Tor Routing (20 pts): Documented IPs do not match the system's clear-net public IP.
    5. Circuit Isolation (20 pts): At least 2 of the 3 IP addresses are unique.

    Pass threshold: 65 points AND ("Browser History" must pass AND "Circuit Isolation" must pass).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported state results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check if the agent created the output file
    if not export_data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Agent failed to create /home/ga/Documents/isolation_audit.json"
        }

    if not export_data.get("file_created_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "The file isolation_audit.json predates the task start. It must be newly created."
        }

    # 3. Load agent's JSON output file
    output_json_path = task_info.get("metadata", {}).get("expected_output_path", "/home/ga/Documents/isolation_audit.json")
    temp_audit = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(output_json_path, temp_audit.name)
        with open(temp_audit.name, 'r') as f:
            try:
                agent_audit = json.load(f)
            except json.JSONDecodeError:
                agent_audit = None
    except Exception as e:
        agent_audit = None
    finally:
        if os.path.exists(temp_audit.name):
            os.unlink(temp_audit.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: JSON Structure & Keys (20 points)
    # ---------------------------------------------------------
    required_domains = task_info.get("metadata", {}).get("required_domains", ["api.ipify.org", "icanhazip.com", "checkip.amazonaws.com"])
    
    if agent_audit and isinstance(agent_audit, dict):
        keys_present = [d for d in required_domains if d in agent_audit]
        if len(keys_present) == 3:
            score += 20
            feedback_parts.append("JSON structure correct and has all required keys (20/20)")
        else:
            score += (len(keys_present) * 5)
            feedback_parts.append(f"JSON missing some domains. Found: {keys_present} (Partial: {len(keys_present)*5}/20)")
    else:
        feedback_parts.append("Failed to parse JSON or invalid structure (0/20)")
        agent_audit = {}  # Set to empty dict to safely continue checks

    # ---------------------------------------------------------
    # Criterion 2: Valid IP Formats (15 points)
    # ---------------------------------------------------------
    extracted_ips = []
    valid_ips_count = 0
    
    for domain in required_domains:
        val = str(agent_audit.get(domain, "")).strip()
        if val:
            try:
                # This will throw ValueError if not a valid IPv4/IPv6
                ip_obj = ipaddress.ip_address(val)
                extracted_ips.append(val)
                
                # Also ensure it's not a local/private network
                if not ip_obj.is_private and not ip_obj.is_loopback:
                    valid_ips_count += 1
            except ValueError:
                pass
                
    if valid_ips_count == 3:
        score += 15
        feedback_parts.append("All 3 values are valid public IP addresses (15/15)")
    elif valid_ips_count > 0:
        score += (valid_ips_count * 5)
        feedback_parts.append(f"Found {valid_ips_count}/3 valid public IPs (Partial: {valid_ips_count*5}/15)")
    else:
        feedback_parts.append("No valid public IP addresses found in the JSON values (0/15)")

    # ---------------------------------------------------------
    # Criterion 3: Browser History (25 points) - MUST PASS
    # ---------------------------------------------------------
    visited_domains = export_data.get("visited_domains", [])
    history_matches = [d for d in required_domains if d in visited_domains]
    
    history_passed = False
    if len(history_matches) == 3:
        score += 25
        history_passed = True
        feedback_parts.append("All 3 domains verified in Tor Browser history (25/25)")
    elif len(history_matches) > 0:
        pts = len(history_matches) * 8
        score += pts
        feedback_parts.append(f"Only {len(history_matches)}/3 domains found in history (Partial: {pts}/25)")
    else:
        feedback_parts.append("No required domains found in Tor Browser history (0/25)")

    # ---------------------------------------------------------
    # Criterion 4: Tor Routing (20 points)
    # ---------------------------------------------------------
    clearnet_ip = export_data.get("clearnet_ip", "unknown").strip()
    
    if not extracted_ips:
        feedback_parts.append("No IPs to verify against Tor Routing (0/20)")
    else:
        if clearnet_ip == "unknown" or not clearnet_ip:
            # If the host environment blocked the setup script from getting IP, we assume pass if IPs are valid.
            if valid_ips_count > 0:
                score += 20
                feedback_parts.append("Host clearnet IP unknown, but valid public IPs imply Tor routing (20/20)")
            else:
                feedback_parts.append("Cannot verify Tor routing due to invalid IPs (0/20)")
        else:
            matched_clearnet = any(ip == clearnet_ip for ip in extracted_ips)
            if matched_clearnet:
                feedback_parts.append("FAILURE: One or more recorded IPs matched the system clear-net IP. Traffic leaked outside Tor! (0/20)")
            else:
                score += 20
                feedback_parts.append("Success: Recorded IPs differ from system clear-net IP (20/20)")

    # ---------------------------------------------------------
    # Criterion 5: Circuit Isolation (20 points) - MUST PASS
    # ---------------------------------------------------------
    isolation_passed = False
    if len(extracted_ips) >= 2:
        unique_ips = set(extracted_ips)
        if len(unique_ips) >= 2:
            score += 20
            isolation_passed = True
            feedback_parts.append(f"Circuit isolation verified: Found {len(unique_ips)} unique IPs (20/20)")
        else:
            feedback_parts.append("Circuit isolation failed: All domains mapped to the same exit IP (0/20)")
    else:
        feedback_parts.append("Not enough IPs extracted to verify circuit isolation (0/20)")

    # Final Evaluation
    is_success = score >= 65 and history_passed and isolation_passed

    if not is_success and score >= 65:
        feedback_parts.append("Gating check failed: Task requires BOTH history verification and confirmed circuit isolation.")

    return {
        "passed": is_success,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }