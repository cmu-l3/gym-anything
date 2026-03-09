#!/usr/bin/env python3
"""
Verifier for configure_dns_zone_params task.

Verifies:
1. Zone file $TTL directive matches 300
2. SOA record parameters match requirements (Refresh, Retry, Expiry, Minimum)
3. Zone file was actually modified during the task
4. Live DNS query matches the file (consistency check)
"""

import json
import base64
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_time_to_seconds(value_str):
    """Convert time strings (1h, 5m, 300) to seconds integer."""
    if not value_str:
        return None
    
    value_str = value_str.lower().strip()
    
    # Plain number
    if value_str.isdigit():
        return int(value_str)
        
    # Units
    match = re.match(r'^(\d+)([smhdw])$', value_str)
    if match:
        val = int(match.group(1))
        unit = match.group(2)
        if unit == 's': return val
        if unit == 'm': return val * 60
        if unit == 'h': return val * 3600
        if unit == 'd': return val * 86400
        if unit == 'w': return val * 604800
        
    return None

def verify_configure_dns_zone_params(traj, env_info, task_info):
    """
    Verify DNS parameters were updated correctly.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Decode zone content
    zone_content = ""
    if result.get("zone_content_base64"):
        try:
            zone_content = base64.b64decode(result["zone_content_base64"]).decode('utf-8')
        except:
            zone_content = ""
            
    if not zone_content:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Zone file empty or not found. Did you save the changes?"
        }

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Expected values
    EXP_TTL = 300
    EXP_REFRESH = 3600
    EXP_RETRY = 600
    EXP_EXPIRY = 604800
    EXP_MINIMUM = 300
    
    # ----------------------------------------------------------------
    # 1. Parse Zone File $TTL
    # ----------------------------------------------------------------
    ttl_match = re.search(r'^\$TTL\s+(\S+)', zone_content, re.MULTILINE | re.IGNORECASE)
    found_ttl = None
    if ttl_match:
        found_ttl = parse_time_to_seconds(ttl_match.group(1))
        
    if found_ttl == EXP_TTL:
        score += 20
        feedback_parts.append("Global TTL correct (300s)")
    else:
        feedback_parts.append(f"Global TTL incorrect (found {found_ttl}s, expected {EXP_TTL}s)")

    # ----------------------------------------------------------------
    # 2. Parse SOA Record
    # ----------------------------------------------------------------
    # Regex to extract SOA block (handles multiline with parentheses)
    # Looks for: IN SOA mname rname ( ... )
    soa_pattern = re.compile(r'\bSOA\b[^(]*\(([^)]*)\)', re.DOTALL | re.IGNORECASE)
    soa_match = soa_pattern.search(zone_content)
    
    soa_params_ok = False
    
    if soa_match:
        # Extract numbers inside parentheses
        # Format: Serial Refresh Retry Expire Minimum
        # Remove comments (;...) and excessive whitespace
        inner_content = soa_match.group(1)
        # Remove comments
        inner_content = re.sub(r';.*', '', inner_content)
        # Extract fields
        fields = inner_content.split()
        
        # We expect at least 5 fields
        if len(fields) >= 5:
            # Parse fields
            # Field 0: Serial (variable)
            # Field 1: Refresh
            # Field 2: Retry
            # Field 3: Expire
            # Field 4: Minimum
            
            # Refresh
            found_refresh = parse_time_to_seconds(fields[1])
            if found_refresh == EXP_REFRESH:
                score += 20
                feedback_parts.append("SOA Refresh correct")
            else:
                feedback_parts.append(f"SOA Refresh incorrect ({found_refresh}s)")

            # Retry
            found_retry = parse_time_to_seconds(fields[2])
            if found_retry == EXP_RETRY:
                score += 20
                feedback_parts.append("SOA Retry correct")
            else:
                feedback_parts.append(f"SOA Retry incorrect ({found_retry}s)")

            # Expiry
            found_expire = parse_time_to_seconds(fields[3])
            if found_expire == EXP_EXPIRY:
                score += 10
                feedback_parts.append("SOA Expiry correct")
            else:
                feedback_parts.append(f"SOA Expiry incorrect ({found_expire}s)")

            # Minimum
            found_minimum = parse_time_to_seconds(fields[4])
            if found_minimum == EXP_MINIMUM:
                score += 20
                feedback_parts.append("SOA Minimum correct")
            else:
                feedback_parts.append(f"SOA Minimum incorrect ({found_minimum}s)")
                
            soa_params_ok = True
        else:
            feedback_parts.append("Could not parse SOA fields from zone file")
    else:
        feedback_parts.append("Could not find SOA record in zone file")

    # ----------------------------------------------------------------
    # 3. Consistency Check (Live DNS)
    # ----------------------------------------------------------------
    # Dig Output: "mname rname serial refresh retry expire minimum"
    live_dns_soa = result.get("live_dns_soa", "").strip()
    
    consistency_passed = False
    if live_dns_soa:
        dig_parts = live_dns_soa.split()
        if len(dig_parts) >= 7:
            # Dig parts: ... serial(2) refresh(3) retry(4) expire(5) minimum(6)
            dig_refresh = int(dig_parts[3])
            dig_retry = int(dig_parts[4])
            
            # Check if live matches file expectations (at least refresh and retry)
            if dig_refresh == EXP_REFRESH and dig_retry == EXP_RETRY:
                score += 10
                feedback_parts.append("Live DNS queries match configuration")
                consistency_passed = True
            else:
                feedback_parts.append("Live DNS values do not match (Did you apply/reload changes?)")
        else:
            feedback_parts.append("Live DNS query failed or format unexpected")
    else:
        feedback_parts.append("Live DNS query returned empty")

    # ----------------------------------------------------------------
    # 4. Anti-Gaming: File Modification
    # ----------------------------------------------------------------
    if not result.get("file_modified_during_task", False):
        feedback_parts.append("WARNING: Zone file timestamp did not update during task")
        # Penalty? Or just strict requirement?
        # If score is high but file not modified, maybe they did it too fast or clock skew?
        # But for this task, Virtualmin writes to file, so it MUST modify.
        if score > 0:
            score = max(0, score - 20) # Significant penalty
            feedback_parts.append("(Penalty applied for no file modification)")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }