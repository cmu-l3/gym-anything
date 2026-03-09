#!/usr/bin/env python3
"""Verifier for multi_source_decoder_pipeline task.

A Security Engineer must build a complete multi-source log ingestion pipeline for
nginx and PostgreSQL logs: parent-child decoder pairs for each source, detection rules,
ossec.conf localfile entries, and web-servers group agent.conf configuration.

Scoring (100 points total):
- Nginx parent + child decoder pair with field extraction: 20 pts
- PostgreSQL parent + child decoder pair with field extraction: 20 pts
- >=3 detection rules covering nginx attacks and postgres access: 25 pts
- ossec.conf localfile entries for nginx AND postgres log locations: 15 pts
- web-servers group agent.conf updated with monitoring config: 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_multi_source_decoder_pipeline(traj, env_info, task_info):
    """Verify multi-source decoder pipeline task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/multi_source_decoder_pipeline_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Nginx decoder chain (parent + child) (20 pts)
        nginx_parent = bool(result.get('nginx_parent_decoder'))
        nginx_child = bool(result.get('nginx_child_decoder'))
        nginx_fields = bool(result.get('nginx_fields_extracted'))

        if nginx_parent and nginx_child and nginx_fields:
            score += 20
            subscores['nginx_decoder'] = True
            feedback_parts.append(
                f"Nginx parent+child decoder with field extraction (20/20)"
            )
        elif nginx_parent and nginx_child:
            score += 14
            subscores['nginx_decoder'] = False
            feedback_parts.append("Nginx parent+child decoder found but field extraction unclear (14/20)")
        elif nginx_parent:
            score += 8
            subscores['nginx_decoder'] = False
            feedback_parts.append("Nginx parent decoder found but no child decoder (8/20)")
        else:
            subscores['nginx_decoder'] = False
            feedback_parts.append("No nginx decoder found in local_decoder.xml (0/20)")

        # Criterion 2: PostgreSQL decoder chain (parent + child) (20 pts)
        pg_parent = bool(result.get('postgres_parent_decoder'))
        pg_child = bool(result.get('postgres_child_decoder'))
        pg_fields = bool(result.get('postgres_fields_extracted'))

        if pg_parent and pg_child and pg_fields:
            score += 20
            subscores['postgres_decoder'] = True
            feedback_parts.append("PostgreSQL parent+child decoder with field extraction (20/20)")
        elif pg_parent and pg_child:
            score += 14
            subscores['postgres_decoder'] = False
            feedback_parts.append("PostgreSQL parent+child decoder found but field extraction unclear (14/20)")
        elif pg_parent:
            score += 8
            subscores['postgres_decoder'] = False
            feedback_parts.append("PostgreSQL parent decoder found but no child decoder (8/20)")
        else:
            subscores['postgres_decoder'] = False
            feedback_parts.append("No PostgreSQL decoder found in local_decoder.xml (0/20)")

        # Criterion 3: >=3 detection rules covering both sources (25 pts)
        new_rules = int(result.get('new_rule_count', 0))
        nginx_attack = bool(result.get('nginx_attack_rule'))
        pg_access = bool(result.get('postgres_access_rule'))
        web_error = bool(result.get('web_error_rule'))
        total_cats = int(result.get('total_new_categories', 0))

        # Require: at least nginx AND postgres coverage, plus enough total rules
        has_both_sources = nginx_attack and pg_access
        if has_both_sources and new_rules >= 3:
            score += 25
            subscores['detection_rules'] = True
            feedback_parts.append(
                f"{new_rules} rules covering nginx attacks + PostgreSQL access (25/25)"
            )
        elif has_both_sources and new_rules >= 1:
            score += 15
            subscores['detection_rules'] = False
            feedback_parts.append(
                f"Both sources covered but only {new_rules} rules (need >=3) (15/25)"
            )
        elif nginx_attack or pg_access:
            score += 8
            subscores['detection_rules'] = False
            covered = "nginx" if nginx_attack else "postgres"
            feedback_parts.append(f"Only {covered} covered; need rules for both sources (8/25)")
        else:
            subscores['detection_rules'] = False
            feedback_parts.append("No new detection rules for nginx or PostgreSQL found (0/25)")

        # Criterion 4: ossec.conf localfile for nginx AND postgres (15 pts)
        ossec_nginx = bool(result.get('ossec_has_nginx_localfile'))
        ossec_pg = bool(result.get('ossec_has_postgres_localfile'))
        new_lf = int(result.get('new_localfile_count', 0))

        if ossec_nginx and ossec_pg:
            score += 15
            subscores['ossec_localfiles'] = True
            feedback_parts.append("ossec.conf has localfile entries for nginx AND PostgreSQL (15/15)")
        elif ossec_nginx or ossec_pg:
            score += 8
            subscores['ossec_localfiles'] = False
            which = "nginx" if ossec_nginx else "PostgreSQL"
            feedback_parts.append(f"ossec.conf has localfile for {which} only (need both) (8/15)")
        elif new_lf >= 1:
            score += 5
            subscores['ossec_localfiles'] = False
            feedback_parts.append(f"{new_lf} new localfile entries but not nginx/postgres paths (5/15)")
        else:
            subscores['ossec_localfiles'] = False
            feedback_parts.append("ossec.conf not updated with nginx/PostgreSQL localfile entries (0/15)")

        # Criterion 5: web-servers group agent.conf updated (20 pts)
        ac_updated = bool(result.get('agent_conf_updated'))
        ac_nginx = bool(result.get('agent_conf_has_nginx'))
        ac_pg = bool(result.get('agent_conf_has_postgres'))

        if ac_updated and (ac_nginx or ac_pg):
            score += 20
            subscores['group_agent_conf'] = True
            sources = [s for s, v in [("nginx", ac_nginx), ("postgres", ac_pg)] if v]
            feedback_parts.append(
                f"web-servers agent.conf updated with {', '.join(sources)} monitoring (20/20)"
            )
        elif ac_updated:
            score += 12
            subscores['group_agent_conf'] = False
            feedback_parts.append(
                "web-servers agent.conf updated but nginx/postgres monitoring not clearly specified (12/20)"
            )
        else:
            subscores['group_agent_conf'] = False
            feedback_parts.append(
                "web-servers group agent.conf not updated (0/20)"
            )

        passed = score >= PASS_THRESHOLD
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {e}"}
    except Exception as e:
        logger.exception("Verification error in multi_source_decoder_pipeline")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
