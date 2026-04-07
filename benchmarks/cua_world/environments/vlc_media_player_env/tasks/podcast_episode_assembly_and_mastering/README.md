# Podcast Episode Assembly and Mastering

## Difficulty
Very Hard

## Skills Tested
- Audio file concatenation
- Multi-format audio conversion (WAV, MP3)
- ID3 metadata embedding
- Audio segment extraction at precise timestamps
- Production specification interpretation
- Multi-deliverable workflow management

## Objective
Assemble a podcast episode from raw components (intro, episode, outro), produce master and distribution copies with proper metadata, and extract a promotional highlight clip.

## Real-World Scenario
A podcast producer at a media company assembles Episode 47 of "The Finance Hour" for multi-platform distribution. The raw recording and music components are ready, but need to be concatenated, mastered, tagged with metadata, and a highlight clip extracted for social media promotion — all per the show's production spec.

## Task Description
- **Raw components** in `/home/ga/Music/raw_podcast/`:
  - `intro.wav` (5-second opening jingle)
  - `episode_raw.wav` (60-second main recording)
  - `outro.wav` (5-second closing music)
- **Production spec**: `/home/ga/Documents/production_spec.txt`

### Required Deliverables (in `/home/ga/Music/podcast_output/`):
1. **Master file**: `episode_47_master.wav` — Concatenated (intro + episode + outro), WAV, stereo, 44.1kHz
2. **Distribution file**: `episode_47_dist.mp3` — Same content as master, MP3 at 192kbps, with ID3 tags:
   - Title: "Episode 47: Market Analysis"
   - Artist: "The Finance Hour"
   - Album: "Season 3"
   - Track: 47
3. **Highlight clip**: `episode_47_highlight.mp3` — 15-second excerpt from raw episode (20s-35s mark), MP3

## Expected Results
- Master WAV (~70 seconds)
- Distribution MP3 with ID3 metadata (~70 seconds)
- Highlight MP3 (~15 seconds)

## Verification Criteria (Pass Threshold: 55%)
- Master WAV: exists, correct duration (~70s), stereo 44.1kHz, properly concatenated (6 pts)
- Distribution MP3: exists, 192kbps, correct duration, 4 ID3 tags (8 pts)
- Highlight clip: exists, ~15s duration, MP3, not full episode (6 pts)
- Files in correct directory (2 pts)
- Total: 22 points

## Occupation Context
**Audio/Video Technician (SOC 27-4011)** — Digital Media / Podcasting industry
