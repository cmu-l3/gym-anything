# Verify Delivery Specs Task

**Difficulty**: 🟡 Medium  
**Skills**: Media inspection, specification verification, technical analysis  
**Duration**: 2-3 minutes  
**Steps**: ~40

## Objective

Verify that a video file delivered by a freelancer meets the technical specifications outlined in a contract. Use VLC's media information tools to inspect codec details and create a verification report.

## Real-World Scenario

You hired a freelance video editor to create a promotional video. The contract specified exact delivery requirements: 1920x1080 resolution, H.264 codec, ~5 Mbps bitrate, MP4 format, and minimum 30 seconds duration. Before paying the invoice and publishing the video, you need to verify the file meets these specifications.

## Task Description

The agent must:
1. Read the specification document at `/home/ga/Documents/delivery_specs.txt`
2. Open the delivered video file `/home/ga/Videos/client_delivery.mp4` in VLC
3. Access VLC's Media Information (Tools → Media Information → Codec Details)
4. Inspect: resolution, codec, bitrate, format, and duration
5. Create a verification report at `/home/ga/Documents/verification_report.txt`

## Expected Results

- Verification report created with all 5 parameters checked
- Each parameter marked as PASS or FAIL
- Overall verdict (PASS/FAIL) based on whether ALL specs are met
- Recommendation: "ACCEPT DELIVERY" or "REQUEST REVISION"

## Verification Criteria

1. ✅ **Report Exists**: Verification report file is created and parseable
2. ✅ **Correct Analysis**: Each parameter (resolution, codec, bitrate, format, duration) is correctly evaluated
3. ✅ **Accurate Verdict**: Overall determination matches whether all specs are met
4. ✅ **Proper Recommendation**: Recommendation aligns with verdict

**Pass Threshold**: 70%

## Skills Tested

- Reading specification documents
- VLC Media Information navigation
- Codec details interpretation
- Technical specification comparison
- Report writing with specific format
- Logical reasoning (AND condition for pass)

## Controls

- **Menu**: Tools → Media Information (Ctrl+I)
- **Codec Details Tab**: Shows technical video properties
- **File operations**: Creating text reports

## Notes

- VLC may show codec names in various formats (H.264, h264, AVC, MPEG-4 AVC)
- Bitrate might be shown in kb/s (needs conversion to Mbps)
- The video might or might not meet specs - agent must determine this accurately
- ALL specifications must be met for an overall PASS