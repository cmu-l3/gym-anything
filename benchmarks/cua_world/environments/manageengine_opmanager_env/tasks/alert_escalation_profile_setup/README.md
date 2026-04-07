# Task: alert_escalation_profile_setup

**Difficulty:** hard
**Environment:** ManageEngine OpManager 12.4.154 (Ubuntu GNOME desktop)
**Max Steps:** 100 | **Timeout:** 1200s | **Reward:** dense

---

## Professional Context

An IT operations team is rolling out a structured three-tier alert escalation policy to ensure that every severity of incident reaches the right responders at the right time. First-line operations staff must be notified for both Critical and Trouble events; the NOC escalation team is called only for Critical severity; and senior IT management receives notification whenever a device is reported as down. An IT analyst must implement all three notification profiles in ManageEngine OpManager before the policy goes live.

---

## Starting State

- OpManager is running at `http://localhost:8060` (credentials: `admin` / `Admin@123`).
- No pre-existing notification profiles with the required names exist.
- The task description fully specifies the three profiles to be created; no external specification file is needed.

---

## Agent Workflow

1. Log in to OpManager at `http://localhost:8060`.
2. Navigate to **Settings > Notifications > Notification Profiles**.
3. Create **Profile 1 — L1-Operations-Alert**:
   - Email recipient: `ops-l1@company.internal`
   - Trigger conditions: Critical severity device alerts, Trouble severity device alerts
4. Create **Profile 2 — L2-NOC-Escalation**:
   - Email recipient: `noc-escalation@company.internal`
   - Trigger conditions: Critical severity only
5. Create **Profile 3 — L3-Management-Notify**:
   - Email recipient: `it-management@company.internal`
   - Trigger conditions: Device Down events
6. Verify all three profiles appear in the Notification Profiles list with correct names and email addresses.

---

## Success Criteria

| # | Criterion | Points |
|---|-----------|--------|
| 1 | Profile `L1-Operations-Alert` exists with email `ops-l1@company.internal` | 34 |
| 2 | Profile `L2-NOC-Escalation` exists with email `noc-escalation@company.internal` | 33 |
| 3 | Profile `L3-Management-Notify` exists with email `it-management@company.internal` | 33 |

**Total: 100 points. Pass threshold: 60 points (2 of 3 criteria).**

---

## Key Files

| Path | Purpose |
|------|---------|
| `/tmp/alert_escalation_result.json` | Exported state collected by `export_result.sh` |
| `setup_task.sh` | Pre-task hook: waits for OpManager, opens Firefox dashboard |
| `export_result.sh` | Post-task hook: queries DB and API for notification profiles |
| `verifier.py` | Scoring logic |

---

## Notes

- Profile names must match **exactly** as specified (case-sensitive, hyphens preserved).
- Email addresses must match exactly; any typo will cause that criterion to fail.
- Verification checks both the PostgreSQL database (raw table dump) and the OpManager REST API; a profile visible in either source is sufficient.
- The trigger configuration (severity levels, event types) is not directly verified by the scorer — focus on getting the name and email correct first.
