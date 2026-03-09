# release_blocking_triage

**Difficulty**: very_hard
**Environment**: redmine_env
**Occupation context**: Engineering Manager / Software Developer (Computer and Mathematical)

## Scenario

An engineering manager at DevLabs needs to perform release-blocking issue triage for the Phoenix E-Commerce Platform v1.0 Launch milestone. Two critical actions are required:

1. **Escalation**: For all open issues in the v1.0 Launch milestone with Urgent or Immediate priority, add a "RELEASE BLOCKER" comment and move status to In Progress.
2. **Reassignment**: The login button bug is behind schedule. Reassign it from bob.walker to carol.santos, align its due date with the v1.0 Launch milestone date, and leave a comment.

## Why This Is Very Hard

- No step-by-step instructions given; agent must navigate Redmine's issue filter/version views independently
- Agent must discover the v1.0 Launch milestone due date from the project's versions page
- Multiple issues must be found and updated across a realistic Redmine project
- Requires cross-referencing issue priorities, statuses, and milestone metadata
- Agent must apply conditional logic (only Urgent/Immediate issues get the RELEASE BLOCKER comment)

## Verification

`export_result.sh` fetches:
- Payment gateway issue (Urgent, v1.0 Launch): status, priority, comments
- Login button issue (High, v1.0 Launch): status, assignee, due_date, comments
- v1.0 Launch version due date

`verifier.py` checks (25 pts each):
1. Payment gateway has comment containing "RELEASE BLOCKER"
2. Payment gateway status = In Progress
3. Login button assignee = Carol Santos
4. Login button due_date matches v1.0 Launch milestone due date

Pass threshold: 60/100

## Seeded Data Used

- Project: `phoenix-ecommerce`
- Issues: "Payment gateway timeout..." (Urgent, In Progress, v1.0 Launch), "Login button unresponsive..." (High, New, v1.0 Launch)
- Version: "v1.0 Launch" (due ~45 days from seed date)
- Users: alice.chen, bob.walker, carol.santos
