#!/bin/bash
set -e
echo "=== Setting up task: quarterly_pipeline_audit ==="

source /workspace/scripts/task_utils.sh

# Wait for Odoo to be ready
wait_for_odoo

# Seed all data via Python/XML-RPC
python3 - <<'PYEOF'
import xmlrpc.client
import json
import sys

URL = "http://localhost:8069"
DB = "odoodb"
USER = "admin"
PASS = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USER, PASS, {})
    if not uid:
        print("ERROR: Authentication failed")
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
    print(f"Authenticated as UID={uid}")
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

# ========== CLEANUP FROM PREVIOUS RUNS ==========

# Clean up opportunities
opp_names = [
    "DataVault Cloud Migration - Pinnacle Financial",
    "Network Infrastructure Refresh - Harbor Shipping Co",
    "ERP Modernization Suite - Atlas Manufacturing",
    "Full Office 365 Migration - Cascade Retail Group",
    "Email Migration - Cascade Retail Group",
    "Cybersecurity Audit Package - NovaTech Solutions",
    "Managed IT Services - Greenfield Organics",
    "Custom Analytics Platform - Redwood Data Systems",
]
for name in opp_names:
    existing = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search',
        [[['name', '=', name], '|', ['active', '=', True], ['active', '=', False]]])
    if existing:
        # Remove activities first
        for oid in existing:
            activities = models.execute_kw(DB, uid, PASS, 'mail.activity', 'search',
                [[['res_model', '=', 'crm.lead'], ['res_id', '=', oid]]])
            if activities:
                models.execute_kw(DB, uid, PASS, 'mail.activity', 'unlink', [activities])
        models.execute_kw(DB, uid, PASS, 'crm.lead', 'unlink', [existing])
        print(f"Cleaned up opportunity: {name}")

# Clean up partner companies created by this task
partner_names = [
    "Pinnacle Financial Group",
    "Harbor Shipping Co",
    "Atlas Manufacturing Inc",
    "Cascade Retail Group",
    "NovaTech Solutions",
    "Greenfield Organics",
    "Redwood Data Systems",
]
for name in partner_names:
    existing = models.execute_kw(DB, uid, PASS, 'res.partner', 'search',
        [[['name', '=', name], ['is_company', '=', True], '|', ['active', '=', True], ['active', '=', False]]])
    if existing:
        # Detach children first
        children = models.execute_kw(DB, uid, PASS, 'res.partner', 'search',
            [[['parent_id', 'in', existing], '|', ['active', '=', True], ['active', '=', False]]])
        if children:
            models.execute_kw(DB, uid, PASS, 'res.partner', 'write',
                [children, {'parent_id': False, 'active': True}])
        models.execute_kw(DB, uid, PASS, 'res.partner', 'write',
            [existing, {'active': False}])
        print(f"Archived partner: {name}")

# Clean up Elena Foster contact
elena_ids = models.execute_kw(DB, uid, PASS, 'res.partner', 'search',
    [[['name', '=', 'Elena Foster'], '|', ['active', '=', True], ['active', '=', False]]])
if elena_ids:
    models.execute_kw(DB, uid, PASS, 'res.partner', 'unlink', [elena_ids])
    print("Removed Elena Foster contact")

# Clean up "Negotiation" stage from previous runs
neg_stages = models.execute_kw(DB, uid, PASS, 'crm.stage', 'search',
    [[['name', '=', 'Negotiation']]])
if neg_stages:
    # Move any leads in this stage to a safe stage first
    leads_in_neg = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search',
        [[['stage_id', 'in', neg_stages]]])
    if leads_in_neg:
        new_stage = models.execute_kw(DB, uid, PASS, 'crm.stage', 'search',
            [[['name', '=', 'New']]], {'limit': 1})
        if new_stage: