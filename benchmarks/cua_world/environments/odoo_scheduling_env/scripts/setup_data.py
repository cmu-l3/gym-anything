#!/usr/bin/env python3
"""
Setup realistic contacts and calendar events for Odoo Scheduling environment.
Called from setup_odoo.sh post_start hook.

Data design:
- 8 contacts with realistic names and @company.org domain
- 15 calendar events spread over 3 weeks
- Alice Johnson appears on 5 events (meaningful for filter_calendar_by_attendee task)
"""
import xmlrpc.client
import time
import sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'

# Authenticate as admin
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = None
for attempt in range(12):
    try:
        uid = common.authenticate(db, 'admin', 'admin', {})
        if uid:
            print(f"Authenticated as admin (uid={uid})")
            break
    except Exception as e:
        print(f"Auth attempt {attempt+1} failed: {e}", file=sys.stderr)
        time.sleep(10)

if not uid:
    print("ERROR: Could not authenticate to Odoo", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

# Create realistic contacts — Alice appears on 5 events for the filter task
contacts_data = [
    {'name': 'Alice Johnson',    'email': 'alice.johnson@northbridge.org',    'phone': '+1-555-0101', 'function': 'Senior Financial Analyst'},
    {'name': 'Bob Williams',     'email': 'bob.williams@northbridge.org',     'phone': '+1-555-0102', 'function': 'Sales Director'},
    {'name': 'Carol Martinez',   'email': 'carol.martinez@northbridge.org',   'phone': '+1-555-0103', 'function': 'Marketing Manager'},
    {'name': 'David Chen',       'email': 'david.chen@northbridge.org',       'phone': '+1-555-0104', 'function': 'Lead Engineer'},
    {'name': 'Emma Thompson',    'email': 'emma.thompson@northbridge.org',    'phone': '+1-555-0105', 'function': 'Product Manager'},
    {'name': 'Frank Rivera',     'email': 'frank.rivera@northbridge.org',     'phone': '+1-555-0106', 'function': 'HR Business Partner'},
    {'name': 'Grace Patel',      'email': 'grace.patel@northbridge.org',      'phone': '+1-555-0107', 'function': 'CFO'},
    {'name': 'Henry Kim',        'email': 'henry.kim@northbridge.org',        'phone': '+1-555-0108', 'function': 'VP Operations'},
    {'name': 'Isabel Santos',    'email': 'isabel.santos@northbridge.org',    'phone': '+1-555-0109', 'function': 'Customer Success Manager'},
    {'name': 'James O\'Brien',   'email': 'james.obrien@northbridge.org',     'phone': '+1-555-0110', 'function': 'Business Analyst'},
    {'name': 'Karen Lee',        'email': 'karen.lee@northbridge.org',        'phone': '+1-555-0111', 'function': 'Legal Counsel'},
    {'name': 'Luis Fernandez',   'email': 'luis.fernandez@northbridge.org',   'phone': '+1-555-0112', 'function': 'DevOps Engineer'},
]

partner_ids = {}
for contact in contacts_data:
    try:
        existing = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                     [[['email', '=', contact['email']]]])
        if not existing:
            pid = models.execute_kw(db, uid, 'admin', 'res.partner', 'create', [contact])
            print(f"Created contact: {contact['name']} (id={pid})")
            partner_ids[contact['name']] = pid
        else:
            partner_ids[contact['name']] = existing[0]
            print(f"Contact exists: {contact['name']} (id={existing[0]})")
    except Exception as e:
        print(f"Warning: Could not create {contact['name']}: {e}", file=sys.stderr)


def p(name):
    """Return (4, partner_id) tuple for a contact name, or empty list if not found."""
    pid = partner_ids.get(name)
    return (4, pid) if pid else None


def ev(days, hour, minute=0):
    """Return datetime string offset from next Monday."""
    return (next_monday + timedelta(days=days)).replace(
        hour=hour, minute=minute, second=0, microsecond=0
    ).strftime('%Y-%m-%d %H:%M:%S')


def ev_soon(days, hour, minute=0):
    """Return datetime string offset from today (for near-term events visible in current week)."""
    return (now.replace(hour=hour, minute=minute, second=0, microsecond=0)
            + timedelta(days=days)).strftime('%Y-%m-%d %H:%M:%S')


# Anchor to next Monday so future dates are always forward
now = datetime.now().replace(second=0, microsecond=0)
days_to_monday = (7 - now.weekday()) % 7 or 7
next_monday = now + timedelta(days=days_to_monday)

# 15 events over 3 weeks. Alice appears in 5 of them.
# Events for task setup (pre-existing named events):
#   - 'Q2 Financial Review'                  → set_meeting_reminder task (clear alarms)
#   - 'Product Roadmap Planning'             → set_meeting_location task (clear location)
#   - 'Annual Performance Review - Frank Rivera' → add_meeting_description task (clear desc)
# Tasks create their own events:
#   - 'Career Coaching Session - Emma Thompson' → create_meeting / book_meeting
#   - 'Tax Advisory - Alice Johnson'         → reschedule_meeting
#   - 'Financial Planning - Bob Williams'    → cancel_meeting

events_data = [
    # ── Near-term events (visible in current week view) ──────────────────────
    # Alice appears here → filter_calendar_by_attendee task always has visible events
    {
        'name': 'Weekly Team Kickoff',
        'start': ev_soon(1, 9), 'stop': ev_soon(1, 9, 45),
        'partner_ids': [p('Alice Johnson'), p('Carol Martinez'), p('David Chen')],
        'location': 'Main Conference Room',
        'description': 'Weekly team sync: priorities, blockers, and updates.',
    },
    {
        'name': 'Operations Daily Sync',
        'start': ev_soon(1, 14), 'stop': ev_soon(1, 14, 30),
        'partner_ids': [p('Grace Patel'), p('Henry Kim'), p('Bob Williams')],
        'location': 'Operations Hub',
    },
    {
        'name': 'Product Strategy Review',
        'start': ev_soon(2, 10), 'stop': ev_soon(2, 11, 30),
        'partner_ids': [p('Alice Johnson'), p('Emma Thompson'), p('David Chen')],
        'location': 'Product Lab',
        'description': 'Review product roadmap and prioritize features for next release.',
    },
    {
        'name': 'Finance Planning Session',
        'start': ev_soon(3, 15), 'stop': ev_soon(3, 16),
        'partner_ids': [p('Bob Williams'), p('Grace Patel'), p('Henry Kim')],
        'location': 'Finance Office',
        'description': 'Monthly finance planning: expense review and budget adjustments.',
    },
    # ── Week 1 (next Monday onwards) — editing task anchors ──────────────────
    {
        'name': 'Q2 Financial Review',
        'start': ev(0, 10), 'stop': ev(0, 11, 30),
        'partner_ids': [p('Alice Johnson'), p('Bob Williams'), p('Henry Kim')],
        'location': 'Conference Room A',
        'description': 'Review Q2 financial performance against targets.',
    },
    {
        'name': 'Team Standup',
        'start': ev(0, 9), 'stop': ev(0, 9, 30),
        'partner_ids': [p('Alice Johnson'), p('Carol Martinez'), p('David Chen'), p('Emma Thompson')],
        'location': 'Main Conference Room',
    },
    {
        'name': 'Marketing Campaign Review',
        'start': ev(1, 14), 'stop': ev(1, 15),
        'partner_ids': [p('Alice Johnson'), p('Carol Martinez')],
        'location': 'Zoom Meeting',
        'description': 'Review Q3 marketing campaign results and plan Q4 strategy.',
    },
    {
        'name': 'Engineering Architecture Discussion',
        'start': ev(1, 10), 'stop': ev(1, 12),
        'partner_ids': [p('David Chen'), p('Emma Thompson'), p('Luis Fernandez')],
        'location': 'Engineering Lab',
        'description': 'Architecture review for the new microservices migration.',
    },
    {
        'name': 'Product Roadmap Planning',
        'start': ev(2, 9), 'stop': ev(2, 11),
        'partner_ids': [p('Alice Johnson'), p('David Chen'), p('Emma Thompson')],
    },
    {
        'name': 'Legal Contract Review',
        'start': ev(3, 11), 'stop': ev(3, 12),
        'partner_ids': [p('Karen Lee'), p('Bob Williams')],
        'location': 'Legal Conference Room',
        'description': 'Review of vendor contracts and renewal terms.',
    },
    # Week 1 Fri
    {
        'name': 'Annual Performance Review - Frank Rivera',
        'start': ev(4, 13), 'stop': ev(4, 14),
        'partner_ids': [p('Frank Rivera')],
    },
    {
        'name': 'Sales Pipeline Sync',
        'start': ev(4, 15), 'stop': ev(4, 16),
        'partner_ids': [p('Carol Martinez'), p('Bob Williams'), p('Isabel Santos')],
        'location': 'Sales Room',
        'description': 'Weekly pipeline sync and forecasting.',
    },
    # ── Week 2 (Mon–Fri) ──────────────────────────────────────────────────────
    {
        'name': 'Investor Update Preparation',
        'start': ev(7, 11), 'stop': ev(7, 12, 30),
        'partner_ids': [p('Alice Johnson'), p('Henry Kim'), p('Grace Patel')],
        'location': 'Board Room',
        'description': 'Prepare Q2 investor update materials and talking points.',
    },
    {
        'name': 'HR Policy Review',
        'start': ev(8, 10), 'stop': ev(8, 11),
        'partner_ids': [p('Grace Patel'), p('Frank Rivera'), p('Karen Lee')],
        'location': 'HR Office',
        'description': 'Review updated HR policies and compliance requirements.',
    },
    {
        'name': 'Client Onboarding - Isabel Santos',
        'start': ev(9, 14), 'stop': ev(9, 15, 30),
        'partner_ids': [p('Isabel Santos'), p('Emma Thompson')],
        'location': 'Zoom Meeting',
        'description': 'New client onboarding session: account setup and walkthrough.',
    },
    {
        'name': 'Budget Committee Meeting',
        'start': ev(10, 15), 'stop': ev(10, 16, 30),
        'partner_ids': [p('Grace Patel'), p('Henry Kim'), p('Bob Williams'), p('James O\'Brien')],
        'location': 'Board Room',
        'description': 'Monthly budget review and department budget approvals.',
    },
    {
        'name': 'Security Awareness Training',
        'start': ev(11, 9), 'stop': ev(11, 10),
        'partner_ids': [p('David Chen'), p('Emma Thompson'), p('Frank Rivera'), p('Luis Fernandez')],
        'location': 'Training Room',
        'description': 'Annual security awareness and compliance training session.',
    },
    # ── Week 3 ────────────────────────────────────────────────────────────────
    {
        'name': 'Quarterly Business Review',
        'start': ev(14, 9), 'stop': ev(14, 12),
        'partner_ids': [p('Alice Johnson'), p('Bob Williams'), p('Carol Martinez'),
                        p('Grace Patel'), p('Henry Kim'), p('James O\'Brien')],
        'location': 'Board Room',
        'description': 'Full Q2 business review: financials, product, sales, and HR.',
    },
    {
        'name': 'Sprint Planning - Engineering',
        'start': ev(15, 10), 'stop': ev(15, 12),
        'partner_ids': [p('David Chen'), p('Emma Thompson'), p('Luis Fernandez')],
        'location': 'Engineering Lab',
        'description': 'Plan next 2-week engineering sprint: story points and assignments.',
    },
    {
        'name': 'Customer Success Review',
        'start': ev(15, 14), 'stop': ev(15, 15),
        'partner_ids': [p('Isabel Santos'), p('Carol Martinez'), p('Bob Williams')],
        'location': 'Zoom Meeting',
        'description': 'Monthly customer success metrics review and churn analysis.',
    },
    {
        'name': 'All-Hands Meeting',
        'start': ev(16, 14), 'stop': ev(16, 15, 30),
        'partner_ids': [p('Alice Johnson'), p('Bob Williams'), p('Carol Martinez'),
                        p('David Chen'), p('Emma Thompson'), p('Frank Rivera'),
                        p('Grace Patel'), p('Henry Kim'), p('Isabel Santos')],
        'location': 'Main Conference Room',
        'description': 'Monthly all-hands: company updates, Q&A, and recognition.',
    },
]

created = updated = 0
for event in events_data:
    try:
        # Filter out None attendee refs (contacts not found)
        partners = [ref for ref in event.get('partner_ids', []) if ref is not None]
        event_data = {k: v for k, v in event.items() if k != 'partner_ids'}
        if partners:
            event_data['partner_ids'] = partners

        existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                     [[['name', '=', event['name']]]])
        if not existing:
            event_id = models.execute_kw(db, uid, 'admin', 'calendar.event', 'create', [event_data])
            print(f"Created event: {event['name']} (id={event_id})")
            created += 1
        else:
            # Always refresh dates so events stay in the future when running from a savevm checkpoint
            models.execute_kw(db, uid, 'admin', 'calendar.event', 'write',
                              [existing, {'start': event_data['start'], 'stop': event_data['stop']}])
            print(f"Refreshed dates for: {event['name']} (id={existing[0]})")
            updated += 1
    except Exception as e:
        print(f"Warning: Could not create/update '{event['name']}': {e}", file=sys.stderr)

print(f"Setup complete! Created {created} new events, refreshed dates for {updated} existing events.")
