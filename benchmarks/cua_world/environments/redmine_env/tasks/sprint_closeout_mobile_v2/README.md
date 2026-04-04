# sprint_closeout_mobile_v2

**Difficulty**: very_hard
**Environment**: redmine_env
**Occupation context**: Scrum Master / Project Manager (Computer and Mathematical)

## Scenario

A Scrum Master at DevLabs performs end-of-sprint closeout for the Mobile Application v2 team's v2.0 Release sprint. Multiple issues need different actions depending on their sprint outcome: closing resolved work, deferring risky items, verifying fixes, and creating a sprint summary.

## Actions Required

1. **Close Dark Mode bug** (v1.9 Legacy, Resolved → Closed)
2. **Defer Offline Sync** (v2.0 Release → v2.1 Hotfix; add "Deferred" comment)
3. **Verify Push Notifications** (log 1.5h Testing from grace.lee; change status to Resolved)
4. **Create sprint closeout issue** (Feature, Closed, v2.0 Release, alice.chen)

## Why This Is Very Hard

- Agent must navigate to multiple different issues across versions in the mobile-app-v2 project
- Dark mode issue is in a **closed version** (v1.9 Legacy) — agent must browse or search for it
- Offline sync milestone change requires editing the issue and updating the Fixed Version field
- Push notifications time logging requires navigating to Log Time and specifying activity type
- Creating a new issue with Status=Closed requires the issue to first be created then immediately closed
- No step-by-step UI guidance — only the end goal is described

## Verification

`export_result.sh` fetches all 3 existing issues + searches for closeout summary.

`verifier.py` checks:
1. Dark mode status = Closed (20 pts)
2. Offline sync version = v2.1 Hotfix (20 pts)
3. Offline sync has "Deferred" comment (10 pts)
4. Push notif has ≥1.5h Testing time logged (25 pts)
5. Push notif status = Resolved (15 pts)
6. Closeout summary issue exists (10 pts)

Pass threshold: 60/100

## Seeded Data Used

- Project: `mobile-app-v2`
- Issues:
  - "Dark mode: tab bar icons inverted on Android 12" (Resolved, v1.9 Legacy)
  - "Offline mode: local changes lost on sync conflict" (New, Urgent, v2.0 Release)
  - "Push notifications not delivered when app is force-closed on iOS" (In Progress, v2.0 Release)
- Versions: v1.9 Legacy (closed), v2.0 Release, v2.1 Hotfix
- Users: alice.chen, grace.lee
