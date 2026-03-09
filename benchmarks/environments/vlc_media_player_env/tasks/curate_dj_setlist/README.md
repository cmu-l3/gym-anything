# DJ Setlist Quality Curation Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio quality assessment, playlist management, metadata analysis  
**Duration**: 3-5 minutes  
**Steps**: ~50

## Objective

You're a mobile DJ preparing for tomorrow's wedding reception. The bride sent you a USB drive with 15 requested songs from various sources (YouTube rips, old CD backups, legal downloads). You need to quickly check the audio quality of all tracks and create a performance-ready playlist containing ONLY the high-quality tracks suitable for professional playback through your PA system.

## Scenario

**The Problem**: Mixed-quality audio sounds terrible through professional sound equipment. Tracks below 192 kbps bitrate will have noticeable artifacts, lack of clarity, and reduced dynamic range - unacceptable for a paid gig.

**Your Task**: Use VLC to efficiently assess the quality of all 15 tracks in `/home/ga/Music/wedding_requests/` and create a playlist named `approved_setlist.xspf` containing ONLY tracks that meet professional standards (bitrate ≥ 192 kbps).

## Task Description

The agent must:
1. Open VLC and navigate to the wedding_requests folder
2. Check the bitrate/codec information for each audio file
3. Identify which tracks meet professional quality standards (≥ 192 kbps)
4. Add only the high-quality tracks to a new playlist
5. Save the playlist as XSPF format to `/home/ga/Music/playlists/approved_setlist.xspf`

## Expected Results

- Playlist file `approved_setlist.xspf` exists at correct location
- Playlist contains ALL 8 high-quality tracks (tracks 01-08: ≥192 kbps)
- Playlist contains ZERO low-quality tracks (tracks 09-15: <192 kbps)
- Playlist is valid XSPF format and loadable by VLC

## Verification Criteria

1. ✅ **Playlist Exists**: Playlist file found and is valid XSPF
2. ✅ **No False Positives**: No low-quality tracks included
3. ✅ **No False Negatives**: All high-quality tracks included
4. ✅ **100% Accuracy**: Perfect quality curation

**Pass Threshold**: 100% accuracy (no mistakes in quality assessment)

## Skills Tested

- **Media information feature**: Accessing codec/bitrate metadata
- **Efficient workflow**: Checking multiple files without full playback
- **Playlist management**: Creating and saving playlists
- **Professional judgment**: Understanding quality thresholds for professional use
- **File operations**: Navigating directories and saving outputs

## Controls & Workflow

**Method 1 - Media Information (Recommended)**:
- Open file in VLC
- Press `Ctrl+I` (or Tools → Media Information)
- Check "Codec Details" tab for bitrate
- Add to playlist if ≥ 192 kbps

**Method 2 - Playlist View**:
- Open playlist view (`Ctrl+L`)
- Add files from wedding_requests folder
- Right-click file → Information to check bitrate
- Remove low-quality tracks

**Saving Playlist**:
- Media → Save Playlist to File
- Choose XSPF format
- Save to `/home/ga/Music/playlists/approved_setlist.xspf`

## Track Quality Reference

**High Quality (INCLUDE)**: tracks 01-08
- 320 kbps, 256 kbps, 224 kbps, 192 kbps MP3
- FLAC and WAV (lossless formats)
- M4A at high bitrate

**Low Quality (EXCLUDE)**: tracks 09-15
- 128 kbps, 96 kbps, 80 kbps, 64 kbps MP3
- Below professional threshold

## Real-World Context

This task simulates a genuine professional workflow where DJs must:
- Quickly assess large music libraries
- Identify quality issues before performance
- Make binary accept/reject decisions based on technical criteria
- Maintain quality standards despite time pressure

Poor-quality tracks can ruin a professional event when played through high-end PA systems, making this skill critical for mobile DJs, wedding DJs, and event professionals.

## Notes

- You do NOT need to play tracks fully - checking metadata is sufficient
- Lossless formats (FLAC, WAV) are always considered high quality
- VLC displays bitrate in kbps (kilobits per second) in Media Information
- The task tests both software knowledge AND understanding of audio quality standards