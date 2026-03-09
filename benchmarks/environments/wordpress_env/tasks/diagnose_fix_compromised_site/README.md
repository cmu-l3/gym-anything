# Task: Diagnose and Fix Compromised WordPress Site

## Domain Context
**Occupation:** Web Administrator (SOC 15-1299.01)
**Rationale:** Web administrators regularly respond to security incidents where WordPress sites have been tampered with — defaced titles, rogue admin accounts, disabled security settings. This task simulates a realistic post-compromise remediation workflow.

## Goal
The WordPress site has been compromised. The agent must investigate the admin panel, discover all tampered settings and unauthorized accounts, and restore the site to a secure, professional state. The agent is NOT told which specific settings were changed — it must discover them through investigation.

## Expected End State
- Site title: "My WordPress Blog" (original value)
- Tagline: "A WordPress blog for testing and demonstrations" (original value)
- No unauthorized admin users (only 'admin' should have administrator role)
- Permalink structure uses clean URLs (not plain `?p=123`)
- Comment moderation is enabled
- Public user registration is disabled, or default role is not "administrator"
- Timezone is restored to "America/Los_Angeles"

## Injected Issues (setup_task.sh)
1. **blogname** → "H4CK3D SITE - Buy Ch3ap M3ds Online"
2. **blogdescription** → "Best pr1ces on pharmaceut1cals - V1sit our store now"
3. **Rogue admin user** "service_worker" with administrator role
4. **permalink_structure** → "" (Plain/default)
5. **comment_moderation** → 0 (disabled)
6. **users_can_register** → 1, **default_role** → "administrator"
7. **timezone_string** → "UTC"

## Verification Strategy
7 independent programmatic criteria (10 pts each = 70 pts):
1. Site title no longer contains spam strings
2. Tagline no longer contains spam strings
3. Rogue user "service_worker" deleted
4. Permalink structure is not empty/plain
5. Comment moderation enabled (value = 1)
6. Registration disabled OR default role != administrator
7. Timezone restored from UTC

VLM trajectory + final state checks (30 pts).

Pass threshold: score >= 70 AND at least 5 of 7 issues fixed.

## Schema Reference
All settings stored in `wp_options` table:
- `blogname`, `blogdescription`, `permalink_structure`, `comment_moderation`, `users_can_register`, `default_role`, `timezone_string`
- User data in `wp_users` table (check for user_login = 'service_worker')

## Edge Cases
- Agent might change title to something other than the original — accepted as long as no spam
- Agent might set a different timezone — accepted as long as not UTC
- Agent might disable registration but leave default_role as admin — still passes (registration is off)
- Agent might change the rogue user's role instead of deleting — does NOT pass (user must be removed)
