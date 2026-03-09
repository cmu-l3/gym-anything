# Snapshot Interrupted Context Task

**Difficulty**: 🟡 Medium  
**Skills**: Context preservation, workflow management, annotations, workspace management  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~80

## Objective

You're debugging a payment processing bug when suddenly interrupted by an urgent production issue on a different project. Create a comprehensive "context snapshot" so you can seamlessly resume debugging later without losing your mental state.

## Scenario

You've been investigating a bug in `project_alpha` where payment amounts are stored incorrectly (e.g., $10.10 appears as $10.09). You've identified the suspicious code at line 26 in `services/payment_processor.py` and were about to test a fix when you received an urgent Slack:

> 🚨 CLIENT B EMERGENCY: Production dashboard completely broken. Users cannot log in. Need fix ASAP!

You must immediately switch to `project_beta`, but first need to preserve your debugging context.

## Expected Workflow

1. **Add inline context comment** at the bug location (line ~26 in payment_processor.py)
   - Document what you were investigating
   - Note your hypothesis about the bug
   - Specify your planned next action

2. **Add TODO marker** near the top of payment_processor.py summarizing debugging state

3. **Create _DEBUG_NOTES.md** file documenting:
   - Current timestamp
   - What you were working on
   - Your hypothesis
   - Next steps when you return

4. **Save workspace state** as `project_alpha_debug_session.code-workspace`

5. **(Optional)** Add explanatory comment in test file

## Verification

Checks for:
1. Inline context comment exists at bug location with meaningful content
2. TODO marker exists summarizing debugging state
3. _DEBUG_NOTES.md file created with required elements
4. Workspace file saved with correct configuration

**Pass Threshold**: 70% (3.5/5.0 points)

## Example Context Comment
