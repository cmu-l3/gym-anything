#!/usr/bin/env python3
"""Verifier for DNS Record Type Analysis task.

Scoring (100 points):
- Criterion 1: Report file exists and is substantial (10 points)
- Criterion 2: Domain names extracted (20 points)
- Criterion 3: DNS record types identified with counts (25 points)
- Criterion 4: DNS server IP identified (15 points)
- Criterion 5: Query count correct (15 points)
- Criterion 6: Response count correct (15 points)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_dns_record_type_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        if not result.get('file_exists'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file not created. Agent must save findings to dns_audit_report.txt"
            }

        # Criterion 1: Report exists
        content_length = result.get('content_length', 0)
        if content_length >= 150:
            score += 10
            feedback_parts.append(f"Report exists ({content_length} chars)")
        elif content_length > 0:
            score += 5
            feedback_parts.append(f"Report exists but short ({content_length} chars)")
        else:
            feedback_parts.append("Report is empty")

        # Criterion 2: Domains extracted
        domains_found = result.get('domains_found', 0)
        domains_total = result.get('domains_total', 1)
        if domains_total > 0:
            domain_ratio = domains_found / domains_total
            if domain_ratio >= 0.6:
                score += 20
                feedback_parts.append(f"Domains: {domains_found}/{domains_total} found")
            elif domains_found >= 2:
                score += 12
                feedback_parts.append(f"Domains: {domains_found}/{domains_total} found (partial)")
            elif domains_found > 0:
                score += 6
                feedback_parts.append(f"Domains: only {domains_found}/{domains_total} found")
            else:
                feedback_parts.append("No domain names found in report")

        # Criterion 3: Record types identified
        types_found = result.get('types_found', 0)
        types_total = result.get('types_total', 1)
        if types_total > 0:
            type_ratio = types_found / types_total
            if type_ratio >= 0.6:
                score += 25
                feedback_parts.append(f"Record types: {types_found}/{types_total} found")
            elif types_found >= 2:
                score += 15
                feedback_parts.append(f"Record types: {types_found}/{types_total} found (partial)")
            elif types_found > 0:
                score += 8
                feedback_parts.append(f"Record types: only {types_found}/{types_total} found")
            else:
                feedback_parts.append("No DNS record types found in report")

        # Criterion 4: DNS server IP
        if result.get('has_dns_server'):
            score += 15
            feedback_parts.append("DNS server IP identified")
        else:
            feedback_parts.append("DNS server IP not found in report")

        # Criterion 5: Query count
        if result.get('has_query_count'):
            score += 15
            feedback_parts.append("Query count correct")
        else:
            feedback_parts.append("Query count not found or incorrect")

        # Criterion 6: Response count
        if result.get('has_response_count'):
            score += 15
            feedback_parts.append("Response count correct")
        else:
            feedback_parts.append("Response count not found or incorrect")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
