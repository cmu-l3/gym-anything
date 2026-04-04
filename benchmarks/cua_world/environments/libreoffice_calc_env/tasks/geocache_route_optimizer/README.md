# Geocache Route Optimizer Task

**Difficulty**: 🟡 Medium
**Estimated Steps**: 50
**Timeout**: 300 seconds (5 minutes)

## Objective

Plan an efficient geocaching route through Rocky Mountain National Park to find as many high-priority caches as possible within a 4-hour (240 minute) time constraint. This task combines geographic coordinate calculations, time budgeting, priority-based decision making, and multi-constraint optimization.

## Scenario

You're on a geocaching trip to Rocky Mountain National Park. You arrived late and only have **4 hours (240 minutes)** before the park closes at 5:00 PM. You've identified 10 caches you'd like to find, but you need to determine which ones to attempt and ensure you can complete them all within your time budget.

## Starting State

- LibreOffice Calc opens with a spreadsheet containing 10 geocache locations
- Data includes: Cache Name, Latitude, Longitude, Difficulty (1-5 stars), Terrain (1-5 stars), Priority (1-3)
- Starting location: Visitor Center (40.3200, -105.6700)
- Priority levels:
  - **Priority 1** (must-find): Favorite scenic spots, rare caches
  - **Priority 2** (want-to-find): Good caches but not critical
  - **Priority 3** (nice-to-have): Bonus caches if time permits

## Required Actions

### 1. Calculate Estimated Time per Cache
Create a formula to estimate how long each cache will take to find:
- Base time: 15 minutes (approach, search, sign log, return)
- Difficulty modifier: Add 5 minutes per difficulty star above 1
- Terrain modifier: Add 8 minutes per terrain star above 1

**Formula**: `=15 + (Difficulty-1)*5 + (Terrain-1)*8`

### 2. Calculate Distance from Starting Point
Calculate approximate distance from Visitor Center to each cache using coordinate math.

**Simplified formula** (good enough for small distances):