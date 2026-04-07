# Multi-Platform Distribution Transcode

## Difficulty
Very Hard

## Skills Tested
- Multi-format video transcoding
- Specification document interpretation
- Container and codec management
- Audio-only extraction
- Manifest/documentation generation
- Batch workflow orchestration

## Objective
Transcode a master video to meet 4 different platform specifications, each requiring different codecs, resolutions, framerates, and audio configurations, then produce a deliverables manifest.

## Real-World Scenario
A digital content coordinator at a media distribution company prepares a master video for simultaneous delivery to broadcast TV, mobile app, web streaming, and podcast platforms. Each platform has strict technical requirements that must be met exactly, and a manifest must accompany the deliverables for the distribution system.

## Task Description
- **Master video**: `/home/ga/Videos/master_content.mp4` (60s, 1920x1080, H.264, 30fps)
- **Platform specs**: `/home/ga/Documents/platform_specs.json`

### Platform Requirements:
| Platform | Filename | Container | Video Codec | Resolution | FPS | Audio |
|----------|----------|-----------|-------------|-----------|-----|-------|
| Broadcast | broadcast_delivery.mp4 | MP4 | H.264 | 1920x1080 | 25 | Stereo AAC 48kHz |
| Mobile | mobile_delivery.mp4 | MP4 | H.264 | 640x360 | 30 | Mono AAC 44.1kHz |
| Web | web_delivery.mkv | MKV | H.264 | 1280x720 | 30 | Stereo AAC 44.1kHz |
| Audio Only | audio_extract.mp3 | MP3 | None | None | N/A | Stereo MP3 44.1kHz |

### Required Deliverables:
1. 4 transcoded files in `/home/ga/Videos/deliverables/`
2. Manifest at `/home/ga/Documents/deliverables_manifest.json`

## Expected Results
- 4 output files matching their platform specifications
- JSON manifest with technical properties for each deliverable

## Verification Criteria (Pass Threshold: 70%)
- Per platform (4 × 5 pts = 20 pts): file exists, correct codec, resolution, framerate, audio
- Manifest (8 pts, GATE): valid JSON, lists all 4 outputs, contains properties
- Total: 28 points

## Strategy Enumeration
| Strategy | Files Score | Manifest Score | Total | Pass? |
|----------|-----------|---------------|-------|-------|
| Do-nothing | 0 | 0 | 0% | No |
| Copy master to all (no transcoding) | ~53% | 0 | ~53% | No |
| All platforms correct + no manifest | ~71% | 0 | ~71% | Yes (borderline) |
| All platforms correct + manifest | ~71% | ~29% | 100% | Yes |

## Occupation Context
**Media/Communication Worker (SOC 27-3099)** — Entertainment / Streaming Media industry
