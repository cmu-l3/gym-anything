# Enhance Dark Dashcam Task

**Difficulty**: 🟡 Medium  
**Skills**: Video effects, brightness/contrast adjustment, visual quality assessment  
**Duration**: 90 seconds  
**Steps**: ~25

## Objective

Enhance an extremely dark dashcam video by applying appropriate brightness and contrast adjustments through VLC's video effects system to make details visible.

## Task Description

The agent must:
1. Open an extremely dark dashcam video in VLC
2. Navigate to video effects/adjustments (Tools → Effects and Filters)
3. Apply brightness and contrast enhancements to make content visible
4. Verify that previously invisible details become distinguishable

## Scenario Context

**The Real-World Problem:**
A dashcam recording captured an important incident at dusk, but the camera's automatic settings failed, resulting in an extremely dark video. The user needs to quickly brighten this footage to identify key details (vehicle information, incident sequence) for an insurance claim, without learning complex video editing software.

## Expected Results

- Brightness increased significantly (≥1.4x or +40%)
- Contrast enhanced (≥1.2x or +20%)
- Video effects enabled and persistent in VLC configuration
- Previously dark/invisible details now visible

## Verification Criteria

1. ✅ **Brightness Enhanced**: VLC brightness setting ≥1.4x
2. ✅ **Contrast Increased**: VLC contrast setting ≥1.2x
3. ✅ **Effects Applied**: Video adjustment filter enabled
4. ✅ **Reasonable Values**: Settings within practical ranges

**Pass Threshold**: 70%

## Skills Tested

- Effects menu navigation (Tools → Effects and Filters)
- Image adjustment controls (brightness, contrast, gamma sliders)
- Real-time preview monitoring
- Visual quality assessment
- Understanding parameter relationships
- Settings persistence

## Controls

- **Menu**: Tools → Effects and Filters (or `Ctrl+E`)
- **Video Effects tab**: Enable "Image adjust" or "Essential" adjustments
- **Sliders**: 
  - Brightness: Increase to ~1.5-1.8
  - Contrast: Increase to ~1.3-1.6
  - Gamma: Adjust to ~1.2-1.5 (optional)

## Notes

- Enhancement introduces some noise/grain (inevitable with dark footage)
- Balance is key: bright enough to see details, but avoid over-processing
- Effects apply in real-time without re-encoding
- Settings persist in VLC configuration file