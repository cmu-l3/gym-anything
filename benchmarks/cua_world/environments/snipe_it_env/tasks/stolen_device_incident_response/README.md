# Task: stolen_device_incident_response

## Occupation Context
**Role:** IT Security Analyst
**Industry:** Healthcare

## Task Description
Process a stolen device security incident. Agent must check in the stolen laptop, mark it as Lost/Stolen, add incident notes, check out a replacement to the affected employee, and create an insurance tracking asset.

## Difficulty: very_hard
- 5 sequential operations that must be done in correct order
- Agent must discover which asset belongs to David Kim
- Must navigate checkout/checkin workflows
- Must create a new asset with specific details
- Wrong-target gate: modifying unrelated assets caps score
- No UI path provided

## Verification Criteria (100 points)
1. C1 (15 pts): Stolen laptop checked in
2. C2 (15 pts): Stolen laptop status set to Lost/Stolen
3. C3 (10 pts): Incident note added to stolen laptop
4. C4 (20 pts): Replacement checked out to David Kim
5. C5 (10 pts): Checkout note references incident ID
6. C6 (15 pts): Insurance claim asset ASSET-L012 created
7. C7 (10 pts): Insurance asset has correct serial and Pending status
8. C8 (5 pts): Control asset unchanged (wrong-target gate)
