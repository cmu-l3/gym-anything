# Hiking Trail Time Budget Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, conditional logic, time calculations, data analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Create a hiking time calculator using Naismith's Rule to estimate trail completion time with elevation adjustments. The agent must apply formulas to calculate base hiking time, elevation gain penalties, descent bonuses, add safety margins, and determine if a day hike is feasible before sunset.

## Task Description

The agent must:
1. Review trail segment data (distance, elevation gain, elevation loss)
2. Create formulas to calculate base hiking time from distance
3. Add elevation gain time penalties (climbing is slower)
4. Add elevation descent time bonuses (descending is faster)
5. Calculate total segment times
6. Sum total moving time
7. Add 25% safety margin for rests
8. Determine if hike is feasible within available daylight
9. Save the completed calculator

## Naismith's Rule

Standard hiking time estimation formula:
- **Base time**: 1 hour per 5 km (or 3 miles)
- **Ascent penalty**: +1 hour per 600m (or 2000 ft) elevation gain
- **Descent bonus**: -1 hour per 1200m (or 4000 ft) elevation loss
- **Safety margin**: Add 20-30% buffer time for rests and contingencies

## Sample Trail Data

| Segment | Distance (km) | Elev Gain (m) | Elev Loss (m) |
|---------|---------------|---------------|---------------|
| Trailhead to Creek | 3.2 | 150 | 20 |
| Creek to Ridge | 4.5 | 480 | 30 |
| Ridge to Summit | 2.8 | 590 | 10 |
| Summit to Saddle | 2.1 | 50 | 420 |
| Saddle to Viewpoint | 1.9 | 180 | 90 |
| Viewpoint to Junction | 2.4 | 30 | 380 |
| Junction to Trailhead | 3.1 | 20 | 250 |

**Total**: 18 km distance, 1200m gain, 1200m loss

## Expected Formulas

**Column E - Base Time (hours)**: