#!/usr/bin/env python3
"""
Verifier for TLS Certificate Audit task.

Scoring (100 points):
- Report exists and was modified after task start: 10 points
- Visits to 5 target domains (verified via history): 10 points each (50 total)
- Report content analysis (CA, Dates, Key Info, TLS Version): 40 points total
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/tls_audit_result.json"

def verify_tls_certificate_audit(traj, env_info, task_info):
    """Verify the TLS Certificate Audit task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        # Copy result from container
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

        score = 0
        feedback_parts = []
        
        visited_domains = result.get("visited_domains", [])
        report = result.get("report", {})
        content = report.get("content_snippet", "")
        
        # Criterion 1: Report existence and timestamp (10 pts)
        if report.get("exists") and report.get("created_during_task"):
            score += 10
            feedback_parts.append("Report created (10/10)")
        elif report.get("exists"):
            score += 5
            feedback_parts.append("Report exists but pre-dates task (5/10)")
        else:
            feedback_parts.append("Report not found (0/10)")

        # Criterion 2: Visits to target domains (50 pts, 10 each)
        targets = ["treasury.gov", "ssa.gov", "sec.gov", "usa.gov", "cisa.gov"]
        visited_count = 0
        for domain in targets:
            if domain in visited_domains:
                score += 10
                visited_count += 1
            else:
                # Also check if domain is mentioned in report as a fallback evidence
                # (Anti-gaming: only full points if visited, but maybe partial if just reported?)
                # Sticking to strict history check for "Proof of Work"
                pass
        
        feedback_parts.append(f"Visited {visited_count}/5 domains ({visited_count*10}/50)")

        # Criterion 3: Report Content Analysis (40 pts)
        if len(content) > 100:
            content_lower = content.lower()
            
            # Check for CA names (DigiCert, Entrust, Let's Encrypt, etc.)
            known_cas = ["digicert", "entrust", "sectigo", "godaddy", "amazon", "geotrust", "global sign", "letsencrypt", "let's encrypt", "gts", "google trust services"]
            ca_found = any(ca in content_lower for ca in known_cas)
            
            # Check for Key Info (RSA, ECDSA, 2048, 256)
            key_found = bool(re.search(r'(rsa|ecdsa|ecc).{0,20}\d+', content_lower) or re.search(r'\d+.{0,10}bit', content_lower))
            
            # Check for Date patterns (YYYY-MM-DD or Month DD, YYYY)
            date_found = bool(re.search(r'\d{4}-\d{2}-\d{2}', content) or re.search(r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)', content_lower))
            
            # Check for TLS version
            tls_found = bool(re.search(r'tls\s?1\.[23]', content_lower))

            # Scoring content
            content_score = 0
            if ca_found: content_score += 10
            if key_found: content_score += 10
            if date_found: content_score += 10
            if tls_found: content_score += 10
            
            score += content_score
            feedback_parts.append(f"Content Analysis: CA={ca_found}, Key={key_found}, Dates={date_found}, TLS={tls_found} ({content_score}/40)")
            
            # Verify mentioned domains match visited domains (Anti-gaming)
            # If report mentions a domain that wasn't visited, penalize
            mentioned_domains = [d for d in targets if d in content_lower]
            unvisited_mentions = [d for d in mentioned_domains if d not in visited_domains]
            if unvisited_mentions:
                score -= (len(unvisited_mentions) * 5)
                feedback_parts.append(f"Penalty: Reported unvisited domains {unvisited_mentions}")

        else:
            feedback_parts.append("Report content too short or empty (0/40)")

        return {
            "passed": score >= 60,
            "score": max(0, min(100, score)),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.remove(tmp.name)