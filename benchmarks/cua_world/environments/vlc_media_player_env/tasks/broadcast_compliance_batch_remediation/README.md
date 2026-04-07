# Broadcast Compliance Batch Remediation

## Difficulty
Very Hard

## Skills Tested
- Media file analysis and diagnostics
- Video/audio transcoding to precise specifications
- Batch processing workflow management
- Technical compliance reporting
- CLI tool discovery and usage

## Objective
Diagnose and remediate 4 non-compliant media files to meet EBU broadcast standards, then produce a compliance audit report.

## Real-World Scenario
A broadcast engineer at a regional TV station receives files flagged by the automated QC system before they can air. Each file violates a different broadcast spec. The engineer must efficiently diagnose all violations, transcode each file to exact specifications, and document the remediation in a structured report for the station's compliance records.

## Task Description
Four media files in `/home/ga/Videos/qc_flagged/` have been flagged as non-compliant:

1. **news_segment_01.mp4** - Framerate violation
2. **sports_highlight_02.mp4** - Resolution violation
3. **interview_03.mp4** - Audio channel violation
4. **documentary_04.mpg** - Codec/container violation

The QC report at `/home/ga/Documents/qc_flags.txt` identifies which test each file failed.

### Target Specifications (PAL Broadcast):
- Resolution: 1920x1080
- Framerate: 25fps
- Video codec: H.264 (AVC)
- Container: MP4
- Audio: Stereo (2 channels), AAC, 48kHz
- Minimum video bitrate: 4 Mbps

### Required Deliverables:
1. Remediated files in `/home/ga/Videos/broadcast_ready/` (preserving filenames, .mp4 extension)
2. Compliance report at `/home/ga/Documents/compliance_report.json`

## Expected Results
- 4 broadcast-compliant video files
- JSON report documenting each violation and remediation

## Verification Criteria (Pass Threshold: 70%)
- Each file: correct resolution, framerate, audio configuration, codec (4 pts each × 4 files = 16 pts)
- Compliance report (GATE): valid JSON, lists all files, identifies correct violations (8 pts)
- Total: 24 points

## Strategy Enumeration
| Strategy | Files Score | Report Score | Total | Pass? |
|----------|-----------|-------------|-------|-------|
| Do-nothing | 0 | 0 | 0% | No |
| Copy originals without transcoding | ~54% (each file 3/4) | 0 | ~54% | No |
| All correct + no report | 67% | 0 | 67% | No |
| All correct + report | 67% | 33% | 100% | Yes |

## Occupation Context
**Broadcast Engineer (SOC 27-4012)** — Television Broadcasting industry
