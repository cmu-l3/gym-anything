# Task: new_site_provisioning

## Occupation Context
**Role:** IT Director
**Industry:** Retail and Logistics

## Task Description
Provision a completely new site: create a location, department, and user, then transfer existing assets and check out equipment to the new employee. This simulates a real office expansion workflow.

## Difficulty: very_hard
- 5 different entity types must be created/modified (location, department, user, assets, checkout)
- Entities have dependencies (department needs location, user needs department)
- Must navigate across Settings, Users, and Hardware sections
- Must handle asset location changes and checkouts
- No UI path provided

## Verification Criteria (100 points)
1. C1 (15 pts): Chicago Distribution Center location created with correct address
2. C2 (10 pts): Logistics department created at Chicago location
3. C3 (15 pts): User trivera created with correct email and at Chicago
4. C4 (20 pts): ASSET-D001 and ASSET-D002 transferred to Chicago
5. C5 (10 pts): Transfer notes added to relocated assets
6. C6 (15 pts): ASSET-M002 checked out to Thomas Rivera
7. C7 (5 pts): Monitor checkout note present
8. C8 (10 pts): Control assets left unchanged
