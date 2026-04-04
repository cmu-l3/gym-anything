# Tiered Recording Policy

## Domain Context

Security operations centers (SOCs) and loss prevention departments often implement tiered recording policies based on the sensitivity and traffic patterns of each monitored location. High-traffic external areas (parking lots, entrances) require continuous high-quality recording for incident review and legal defensibility. Internal server rooms with lower foot traffic may use motion-triggered recording to reduce storage. Configuring these distinct policies in a VMS requires understanding recording types, frame rates, quality settings, and camera-specific scheduling.

## Task Overview

**Difficulty**: hard
**Occupation context**: Security Guard / Loss Prevention Manager / SOC Operator

The facility needs to implement a differentiated recording policy across its three cameras. The current state has all recording disabled (reset by setup). Configure each camera with its required policy and create the SOC monitoring layout.

The agent must configure exactly:

1. **Parking Lot Camera** — continuous 24/7 recording:
   - Type: `always` (continuous)
   - Frame rate: **25 fps** (or above 20 fps)
   - Quality: **High**
   - Days: all 7 days

2. **Entrance Camera** — continuous recording at moderate frame rate:
   - Type: `always` (continuous)
   - Frame rate: **15 fps** (or above 10 fps)
   - Quality: **High**
   - Days: all 7 days

3. **Server Room Camera** — motion/metadata-triggered recording only:
   - Type: `metadataAndLowQuality` or `metadataOnly` (NOT `always`)
   - Frame rate: **10 fps**
   - Quality: **Low**
   - Days: all 7 days

4. Create a layout named **"Security Operations Center"** containing all three cameras.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Parking Lot Camera: `always` type + fps ≥ 20 | 20 |
| Entrance Camera: `always` type + fps ≥ 10 | 20 |
| Server Room Camera: motion/metadata type (NOT `always`) | 20 |
| Layout "Security Operations Center" exists | 10 |
| Layout contains all 3 cameras | 30 |
| **Total** | **100** |
| **Pass threshold** | **70** |

## Starting State

`setup_task.sh`:
- Disables ALL camera recording schedules (agent must configure from scratch)
- Removes "Security Operations Center" layout if it pre-exists

## Verification Strategy

`export_result.sh` queries the Nx Witness REST API for each camera's schedule:
- Checks `is_enabled`, `recording_types[]`, `fps_values[]`, `has_always`, `has_motion`, `days_covered`
- Checks "Security Operations Center" layout and its camera contents

Results written to `/tmp/tiered_recording_policy_result.json`.

`verifier.py` scores:
- Parking Lot: `has_always=True AND max_fps>=20`
- Entrance: `has_always=True AND max_fps>=10`
- Server Room: `has_motion=True AND has_always=False`
- Layout existence and 3-camera membership

## Access Information

- **URL**: https://localhost:7001
- **Login**: admin / Admin1234!
- **API base**: https://localhost:7001/rest/v1/

## Edge Cases

- Nx Witness recording types: `always`, `metadataAndLowQuality`, `metadataOnly` — the server room must NOT use `always`
- The `fps` in the API is typically 0-30; the schedule task object has `fps` and `streamQuality` fields
- Partial credit awarded separately per camera and for layout
- The agent must recognize that each camera needs a distinct configuration — they cannot all be set identically

## Schema Reference

```
PATCH /rest/v1/devices/{cameraId}
Body:
{
  "schedule": {
    "isEnabled": true,
    "tasks": [
      {
        "dayOfWeek": 0,  // 0=Mon, 1=Tue, ..., 6=Sun
        "startTime": 0,
        "endTime": 86400,
        "recordingType": "always",   // or "metadataAndLowQuality"
        "fps": 25,
        "streamQuality": "high"      // or "low"
      }
      // repeat for all 7 days
    ]
  }
}
```
