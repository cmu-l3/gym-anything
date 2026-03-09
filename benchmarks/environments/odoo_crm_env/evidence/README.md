# Odoo CRM Environment — Evidence Documentation

## Environment Summary

- **App**: Odoo 17.0 Community (CRM module)
- **Stack**: `odoo:17.0` Docker + `postgres:15` Docker, port 8069
- **Admin credentials**: `admin` / `admin`
- **Resolution**: 1920x1080 (GNOME Desktop)
- **Browser**: Firefox snap (Ubuntu 22.04)

## Final Test Status

**Clean test performed**: `env.reset(seed=42, use_cache=False, use_savevm=True)` ✅
- Pre_start hook: ✅ Completed (installed Docker, xmlrpc.client, scrot, wmctrl, xdotool)
- Post_start hook: ✅ Completed (Docker containers up, data seeded, Firefox warm-up done)
- All 5 tasks demonstrated end-to-end: ✅

## Database Counts (after setup)

- CRM leads/opportunities: 45 (44 from Odoo demo data; seed_crm.py upserts 6 records by name — 5 update existing demo records, 1 creates a net-new record)
- Partners/contacts: 37 (36 demo + 1 seeded)
- CRM pipeline stages: 4 (New, Qualified, Proposition, Won)

## Pre_Start Log Snippet

```
xmlrpc.client available
=== Odoo CRM Installation complete ===
```
(Full log confirms: Docker, docker-compose-plugin, scrot, wmctrl, xdotool, xclip, jq, python3-pip, xmlrpc.client all installed)

## Post_Start Log Snippet

```
=== Seeding complete. Total CRM records: 45 ===
Warming up Firefox...
Warm-up login complete
=== Odoo CRM setup complete ===
```

## Docker Container Status

```
odoo-web   Up    0.0.0.0:8069->8069/tcp
odoo-db    Up (healthy)   5432/tcp
```

## Key Verified Coordinates (1920x1080 screen)

### Odoo Login Page (`http://localhost:8069/web/login`)
- Email field: actual(993, 422)
- Password field: actual(993, 503)
- "Log in" button: actual(993, 569)

### Firefox Navigation
- Address bar: actual(1030, 149) — VG(687, 99) × 1.5

### CRM Opportunity Form (Won button)
- "Won" button: VG(263, 200) = actual(395, 300)
- "Lost" button: VG(299, 200) = actual(449, 300)
- "Convert to Opportunity" (leads): VG(303, 200) = actual(455, 300)
- Activities button (bottom): VG(406, 619) = actual(609, 929)

## Working URLs

- Login: `http://localhost:8069/web/login`
- CRM Pipeline: `http://localhost:8069/web#action=209&cids=1&menu_id=139`
- Specific opportunity form: `http://localhost:8069/web#action=209&id={ID}&model=crm.lead&view_type=form&cids=1&menu_id=139`
- Contacts: `http://localhost:8069/web#action=154&cids=1&menu_id=117`

**Note**: `/odoo/crm` and `/odoo/contacts` return 404 in Odoo 17 Community — use hash URLs above.

## Task-Specific Records

| Task | Record | ID | Type | Stage |
|------|--------|----|------|-------|
| create_lead | Pacific Northwest Trading Co. - ERP Inquiry | (deleted by pre_task) | lead | N/A |
| convert_lead_to_opportunity | Enterprise Software Licensing | 45 | lead | New |
| schedule_activity | CloudServices Partnership | 46 | opportunity | Qualified |
| create_customer | Meridian Financial Group | (deleted by pre_task) | partner | N/A |
| mark_opportunity_won | Digital Marketing Campaign | 47 | opportunity | Proposition |

---

## Task 1: create_lead — Evidence

**Start State**: CRM Pipeline kanban view showing existing leads
- Screenshot: `create_lead_start_state.png`

**Task Flow Demonstrated**:
1. Click "New" in CRM Pipeline → quick-add form appears in kanban
2. Fill Opportunity title: "Pacific Northwest Trading Co. - ERP Inquiry"
3. Click "Edit" to open full form
4. Fill Customer: "Pacific Northwest Trading Co." (create new)
5. Fill Expected Revenue: $45,000.00
6. Fill Email: contact@pnwtradingco.com
7. Fill Phone: +1 (503) 555-0192
8. Fill Internal Notes: "Interested in enterprise resource planning..."
9. Odoo auto-saves the record

**Completion Screenshots**:
- `create_lead_start_state.png` — CRM Pipeline kanban with all seed data
- `create_lead_completed.png` — Full form with all fields filled (Revenue: $45,000.00, Customer: Pacific Northwest Trading Co.)

**Key observations**:
- CRM Pipeline shows 4 stages (New/Qualified/Proposition/Won) with real Odoo demo data
- "New" button creates a kanban quick-add form
- "Edit" opens the full form for additional fields
- Odoo 17 auto-saves records when navigating away

---

## Task 2: convert_lead_to_opportunity — Evidence

**Start State**: Lead form for "Enterprise Software Licensing" with "Convert to Opportunity" button
- Screenshot: `convert_lead_start_state.png`

**Task Flow Demonstrated**:
1. Setup reset lead ID=45 to type=lead, partner_name=BlueStar Technologies (XML-RPC)
2. Navigate to lead form: `#action=209&id=45&model=crm.lead&view_type=form`
3. "Convert to Opportunity" button visible at VG(303, 200)
4. Click → "Convert to opportunity" dialog opens
5. Dialog options: "Convert to opportunity" (selected) / "Merge with existing opportunities"
6. Customer options: Create new / Link existing / Do not link
7. Click "Create Opportunity" to confirm
8. Lead converts → opportunity form with stage buttons (New/Qualified/Proposition/Won)

**Completion Screenshots**:
- `convert_lead_start_state.png` — Lead form with "Convert to Opportunity" button
- `convert_lead_dialog.png` — Conversion wizard dialog
- `convert_lead_completed.png` — Converted opportunity with stage buttons, no more "Convert" button

---

## Task 3: schedule_activity — Evidence

**Start State**: "CloudServices Partnership" opportunity in Qualified stage
- Screenshot: `schedule_activity_start_state.png`

**Task Flow Demonstrated**:
1. Setup cleared activities, set stage to Qualified (XML-RPC)
2. Navigate to opportunity form: `#action=209&id=46&model=crm.lead&view_type=form`
3. Click "Activities" button at VG(406, 619) → actual(609, 929)
4. "Schedule Activity" dialog opens with fields: Activity Type, Due Date, Summary, Assigned to, Note
5. Activity Type set to "Phone Call"
6. Summary typed: "Follow-up call regarding Q2 proposal"
7. Click "Schedule" button
8. Activity appears in "Planned Activities" section: "Due in 5 days: 'Follow-up call regarding Q2 proposal' for Mitchell Admin"

**Completion Screenshots**:
- `schedule_activity_start_state.png` — CloudServices Partnership in Qualified stage
- `schedule_activity_dialog.png` — Schedule Activity dialog with Activity Type "Phone Call" and Summary "Follow-up call regarding Q2 proposal" both filled
- `schedule_activity_completed.png` — Activity scheduled, showing in Planned Activities section

---

## Task 4: create_customer — Evidence

**Start State**: Contacts kanban view with 37 contacts, "New" button visible
- Screenshot: `create_customer_start_state.png`

**Task Flow Demonstrated**:
1. Setup deleted any existing "Meridian Financial Group" contact (XML-RPC)
2. Navigate to Contacts: `#action=154&cids=1&menu_id=117`
3. Click "New" → New contact form opens (Company type pre-selected)
4. Fill Company Name: "Meridian Financial Group"
5. Fill Phone: "+1 (212) 555-0847"
6. Fill Email: "info@meridianfinancial.com"
7. Fill City: "New York"
8. Navigate back → contact saved (count: 37 → 38)
9. Search "Meridian" confirms: "Meridian Financial Group" (New York, info@meridianfinancial.com) visible

**Completion Screenshots**:
- `create_customer_start_state.png` — Contacts kanban with "New" button
- `create_customer_completed.png` — Form filled with all required fields
- `create_customer_saved_confirmation.png` — Search result showing saved "Meridian Financial Group" contact

---

## Task 5: mark_opportunity_won — Evidence

**Start State**: "Digital Marketing Campaign" opportunity in Proposition stage with "Won" button
- Screenshot: `mark_opportunity_won_start_state.png`

**Task Flow Demonstrated**:
1. Setup reset opportunity ID=47 to Proposition stage, probability=60% (XML-RPC)
2. Navigate to form: `#action=209&id=47&model=crm.lead&view_type=form`
3. Opportunity shows: "Proposition 2h" stage, Revenue $55,000, "Won" button at top
4. Click "Won" button at VG(263, 200) → actual(395, 300)
5. Opportunity immediately transitions: green "WON" ribbon appears
6. Celebratory message: "Boom! Team record for the past 30 days."
7. Stage indicator shows "Won" as active stage
8. Probability: 100.00%

**Completion Screenshots**:
- `mark_opportunity_won_start_state.png` — Digital Marketing Campaign in Proposition stage with Won button
- `mark_opportunity_won_completed.png` — Green "WON" ribbon with celebratory message

---

## Firefox Setup Notes

**Critical**: Firefox snap on Ubuntu 22.04 requires a headless warm-up before content renders correctly:

1. `su - ga -c "DISPLAY=:1 firefox --headless &"` (creates default `.default*` profile)
2. `pkill -f firefox` after 10 seconds
3. `find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d`
4. Inject `user.js` into that auto-generated profile
5. Launch: `su - ga -c "DISPLAY=:1 firefox URL &"` (NO `-profile` flag)

**DO NOT**: Use `-profile` flag, create custom `profiles.ini`, disable e10s (`browser.tabs.remote.autostart=false`), or disable WebRender.

## Runner Note: File Copy Behavior

The gym_anything QEMU runner **copies** mount source files into the VM at startup time (not live-mounted). This means:
- Files must be correct at the time `env.reset()` is called
- Changes to host files after VM starts are NOT reflected in the VM
- For testing, always use `env.close()` + `env.reset()` if you update scripts

Host files are verified correct with hash-based URLs (`web#action=209&cids=1&menu_id=139`).

---

## New Hard Tasks — Phase 4-6 Test Results (2026-02-24)

### Test Summary (All 5 tasks)

| Task | Reset | Export | JSON | Do-Nothing Score | Do-Nothing Passed | Errors |
|------|-------|--------|------|------------------|-------------------|--------|
| reorganize_pipeline | OK | OK | OK | 0 | False | 0 |
| bulk_lead_qualification | OK | OK | OK | 0 | False | 0 |
| customer_account_setup | OK | OK | OK | 0 | False | 0 |
| lost_deal_reactivation | OK | OK | OK | 0 | False | 0 |
| pipeline_forecast_preparation | OK | OK | OK | 0 | False | 0 |

**ALL TESTS PASSED** — 0 total errors across all tasks.

---

## Task 6: reorganize_pipeline — Evidence (Hard)

**Difficulty**: Hard | **Scoring**: 100 points (5 criteria × 20 pts) | **Pass threshold**: 60

**Setup State**: CRM Pipeline with 4 default stages (New, Qualified, Proposition, Won). Two opportunities seeded: "Cloud Infrastructure Migration" (New, prob=10%) and "Annual License Renewal" (Qualified, prob=40%).

**Do-Nothing Verifier Feedback**: "Discovery stage not found | Negotiation stage not found | Proposition not renamed to Proposal Sent | Cloud Infrastructure Migration in 'New' (expected 'Discovery') | Annual License Renewal in 'Qualified' (expected 'Negotiation')"

**Screenshot**: `reorganize_pipeline_screenshot.png` — Shows CRM pipeline kanban with default stages
**Evidence JSON**: `reorganize_pipeline_evidence.json`

---

## Task 7: bulk_lead_qualification — Evidence (Hard)

**Difficulty**: Hard | **Scoring**: 100 points (6 criteria) | **Pass threshold**: 60

**Setup State**: 5 leads created in "New" stage as type=lead: DataSync Solutions, Brightwave Energy, Pinnacle Healthcare (qualified), Quick Print Supplies, FreshStart App (unqualified).

**Do-Nothing Verifier Feedback**: "DataSync not converted (type=lead, active=True) | Brightwave not converted (type=lead, active=True) | Pinnacle not converted (type=lead, active=True) | Quick Print not lost (active=True) | FreshStart not lost (active=True) | No opportunities tagged with Q1-2026 Qualified"

**Screenshot**: `bulk_lead_qualification_screenshot.png`
**Evidence JSON**: `bulk_lead_qualification_evidence.json`

---

## Task 8: customer_account_setup — Evidence (Hard)

**Difficulty**: Hard | **Scoring**: 100 points (5 criteria × 20 pts) | **Pass threshold**: 60

**Setup State**: Westfield Dynamics Corp (company partner, ID=41) and Westfield ERP Migration (opportunity, ID=51, partner_id=None). No child contacts, no activities, no notes.

**Do-Nothing Verifier Feedback**: "Sarah Chen contact not found | Marcus Rivera contact not found | Opportunity not linked to any customer | No activities scheduled on opportunity | No internal notes found on opportunity"

**Bug Fixed**: Removed `customer_rank` field from res.partner create (not available in CRM-only install without `sale` module). Also removed `partner_id: False` from crm.lead create data (potential XML-RPC error).

**Screenshot**: `customer_account_setup_screenshot.png`
**Evidence JSON**: `customer_account_setup_evidence.json`

---

## Task 9: lost_deal_reactivation — Evidence (Hard)

**Difficulty**: Hard | **Scoring**: 100 points (5 criteria) | **Pass threshold**: 60

**Setup State**: Two archived opportunities (active=False): "GlobalTech AI Platform" (ID=51, rev=$50K) and "Metro Finance Dashboard" (ID=52, rev=$35K). No tags, no activities.

**Do-Nothing Verifier Feedback**: "GlobalTech still lost/archived | Metro Finance still lost/archived | No activity on GlobalTech | No activity on Metro Finance | Neither opportunity tagged with Reactivated-2026"

**Screenshot**: `lost_deal_reactivation_screenshot.png`
**Evidence JSON**: `lost_deal_reactivation_evidence.json`

---

## Task 10: pipeline_forecast_preparation — Evidence (Hard)

**Difficulty**: Hard | **Scoring**: 100 points (5 criteria × 20 pts) | **Pass threshold**: 60

**Setup State**: Four opportunities with specific initial conditions: EcoSmart Solutions (Qualified, prob=25%), Horizon Media Group (New, rev=$0, prob=10%), Apex Manufacturing (New, prob=10%), Deadwood Analytics (New, active=True, prob=5%).

**Do-Nothing Verifier Feedback**: "EcoSmart: prob=25.0%, stage='Qualified' (0/20) | Horizon: revenue=$0.0, prob=10.0% (0/20) | Apex: stage='New', prob=10.0% (0/20) | Deadwood Analytics still active (not marked as lost) | No opportunities tagged with Q2-Forecast"

**Screenshot**: `pipeline_forecast_preparation_screenshot.png` — Confirms all 4 target opportunities visible in CRM pipeline
**Evidence JSON**: `pipeline_forecast_preparation_evidence.json`
