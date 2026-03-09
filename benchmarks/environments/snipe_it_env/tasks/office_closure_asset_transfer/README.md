# Task: office_closure_asset_transfer

## Occupation Context
**Role:** Operations Manager
**Industry:** Manufacturing

## Task Description
The London Office is being permanently closed. The agent must transfer all London assets to the New York Office, check in any checked-out assets first, add relocation notes, and create 2 new replacement assets at NYC.

## Difficulty: very_hard
- Multi-step: check in, update location, add notes, create new assets
- Must find all London assets (across categories — laptops, desktops, monitors)
- Must handle checked-out vs non-checked-out assets differently
- Must not disturb non-London assets
- No UI path provided

## Verification Criteria (100 points)
1. C1 (25 pts): All London assets relocated to NYC
2. C2 (15 pts): Checked-out London assets were checked in first
3. C3 (15 pts): Relocation notes added to transferred assets
4. C4 (20 pts): Two new assets created at NYC location
5. C5 (15 pts): Non-London assets left unchanged
6. C6 (10 pts): No assets remain at London Office
