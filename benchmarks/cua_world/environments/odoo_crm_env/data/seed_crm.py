#!/usr/bin/env python3
"""
Seed CRM data for Odoo CRM environment.
Creates task-specific leads, opportunities, and customers via Odoo XML-RPC API.
"""
import xmlrpc.client
import time
import sys

ODOO_URL = 'http://localhost:8069'
DB = 'odoodb'
ADMIN_USER = 'admin'
ADMIN_PASS = 'admin'


def connect(retries=10, delay=10):
    """Connect to Odoo XML-RPC with retries."""
    for attempt in range(retries):
        try:
            common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
            uid = common.authenticate(DB, ADMIN_USER, ADMIN_PASS, {})
            if uid:
                print(f"Connected to Odoo as uid={uid}")
                models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')
                return uid, models
            else:
                print(f"Authentication failed (attempt {attempt+1}/{retries})")
        except Exception as e:
            print(f"Connection error (attempt {attempt+1}/{retries}): {e}")
        time.sleep(delay)
    raise RuntimeError("Failed to connect to Odoo after retries")


def execute(models, uid, model, method, args, kwargs=None):
    return models.execute_kw(DB, uid, ADMIN_PASS, model, method, args, kwargs or {})


def get_stages(models, uid):
    """Get CRM pipeline stages ordered by sequence."""
    stages = execute(models, uid, 'crm.stage', 'search_read',
                     [[]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence'})
    print(f"Found {len(stages)} CRM stages: {[(s['name'], s['sequence']) for s in stages]}")
    return stages


def get_or_create_partner(models, uid, name, email='', phone='', company=True):
    """Get or create a res.partner record."""
    existing = execute(models, uid, 'res.partner', 'search', [[['name', '=', name]]])
    if existing:
        print(f"Partner '{name}' already exists (ID={existing[0]})")
        return existing[0]
    data = {
        'name': name,
        'is_company': company,
        'email': email,
        'phone': phone,
        'customer_rank': 1,
    }
    partner_id = execute(models, uid, 'res.partner', 'create', [data])
    print(f"Created partner '{name}' (ID={partner_id})")
    return partner_id


def get_or_create_lead(models, uid, name, partner_name, lead_type, expected_revenue,
                        stage_id=None, email='', phone='', description='', probability=20):
    """Get or create a crm.lead record."""
    existing = execute(models, uid, 'crm.lead', 'search', [[['name', '=', name]]])
    data = {
        'name': name,
        'partner_name': partner_name,
        'type': lead_type,
        'expected_revenue': expected_revenue,
        'email_from': email,
        'phone': phone,
        'description': description,
        'probability': probability if lead_type == 'opportunity' else 0,
    }
    if stage_id:
        data['stage_id'] = stage_id

    if existing:
        execute(models, uid, 'crm.lead', 'write', [existing, data])
        print(f"Updated {lead_type} '{name}' (ID={existing[0]})")
        return existing[0]
    else:
        lead_id = execute(models, uid, 'crm.lead', 'create', [data])
        print(f"Created {lead_type} '{name}' (ID={lead_id})")
        return lead_id


def main():
    print("=== Seeding Odoo CRM Data ===")

    uid, models = connect()

    # Get stages
    stages = get_stages(models, uid)
    if not stages:
        print("ERROR: No CRM stages found. CRM module may not be installed.")
        sys.exit(1)

    # Map stages by name or by index
    stage_by_name = {s['name'].lower(): s['id'] for s in stages}
    new_stage_id = stages[0]['id']  # First stage (New / New)
    qualified_stage_id = stages[1]['id'] if len(stages) > 1 else stages[0]['id']
    proposition_stage_id = stages[2]['id'] if len(stages) > 2 else stages[0]['id']

    # Find "Won" stage if it exists
    won_stage_id = next(
        (s['id'] for s in stages if 'won' in s['name'].lower()),
        stages[-1]['id']
    )
    print(f"Stage IDs - New={new_stage_id}, Qualified={qualified_stage_id}, "
          f"Proposition={proposition_stage_id}, Won={won_stage_id}")

    # ===== Task 2: convert_lead_to_opportunity =====
    # Pre-create a lead that the agent will convert
    get_or_create_lead(
        models, uid,
        name='Enterprise Software Licensing',
        partner_name='BlueStar Technologies',
        lead_type='lead',
        expected_revenue=75000,
        email='sales@bluestar-tech.com',
        phone='+1 (408) 555-0123',
        description='Interested in enterprise-wide software licensing for 500+ users. '
                     'Current contract expires Q3. Decision maker is the CTO.',
        probability=0,
    )

    # ===== Task 3: schedule_activity =====
    # Pre-create an opportunity for scheduling a follow-up call
    get_or_create_lead(
        models, uid,
        name='CloudServices Partnership',
        partner_name='Vertex Solutions Corp',
        lead_type='opportunity',
        expected_revenue=120000,
        stage_id=qualified_stage_id,
        email='partnerships@vertex-solutions.com',
        phone='+1 (312) 555-0456',
        description='Strategic partnership for cloud infrastructure services. '
                     'Q2 implementation timeline. Awaiting final proposal review.',
        probability=30,
    )

    # ===== Task 5: mark_opportunity_won =====
    # Pre-create an opportunity that the agent will mark as won
    get_or_create_lead(
        models, uid,
        name='Digital Marketing Campaign',
        partner_name='TechPulse Media',
        lead_type='opportunity',
        expected_revenue=55000,
        stage_id=proposition_stage_id,
        email='contact@techpulse-media.com',
        phone='+1 (212) 555-0789',
        description='Annual digital marketing campaign management and analytics platform. '
                     'Contract includes 12-month subscription with quarterly reviews.',
        probability=60,
    )

    # ===== Additional background opportunities (realistic pipeline) =====
    get_or_create_lead(
        models, uid,
        name='Annual License Renewal',
        partner_name='Northern Lights Consulting',
        lead_type='opportunity',
        expected_revenue=38000,
        stage_id=qualified_stage_id,
        email='renewals@northernlights.com',
        phone='+1 (206) 555-0321',
        description='Annual software license renewal for their analytics team.',
        probability=80,
    )

    get_or_create_lead(
        models, uid,
        name='Cloud Infrastructure Migration',
        partner_name='Omega Digital Systems',
        lead_type='opportunity',
        expected_revenue=95000,
        stage_id=new_stage_id,
        email='it@omega-digital.com',
        phone='+1 (415) 555-0654',
        description='Full cloud infrastructure migration project. On-premise to cloud.',
        probability=15,
    )

    get_or_create_lead(
        models, uid,
        name='SaaS Platform Implementation',
        partner_name='Cascade River Technologies',
        lead_type='lead',
        expected_revenue=42000,
        email='info@cascade-river-tech.com',
        phone='+1 (503) 555-0987',
        description='Interested in implementing our SaaS platform for their 200-person team.',
        probability=0,
    )

    # ===== Verify seeded data =====
    total_leads = execute(models, uid, 'crm.lead', 'search_count', [[]])
    print(f"\n=== Seeding complete. Total CRM records: {total_leads} ===")


if __name__ == '__main__':
    main()
