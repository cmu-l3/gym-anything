# Stream Network Media Task

**Difficulty**: 🟡 Medium  
**Skills**: Network streaming, URL handling, playlist management  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Stream media from a network URL using VLC's network stream feature, verify playback, and save the stream location to a playlist for future access.

## Task Description

The agent must:
1. Launch VLC Media Player
2. Open the Network Stream dialog (Media → Open Network Stream)
3. Enter a streaming URL from a text file on the desktop
4. Play the network stream successfully
5. Save the stream to a playlist file

## Expected Results

- VLC plays the network stream (not a local file)
- Playback continues for at least 10 seconds
- Playlist file created at `/home/ga/Videos/company_streams.m3u`
- Playlist contains the stream URL

## Verification Criteria

1. ✅ **Network Stream Playing**: VLC playing network URL
2. ✅ **Sustained Playback**: Video plays for 10+ seconds
3. ✅ **Playlist Created**: Playlist file exists and is valid
4. ✅ **URL in Playlist**: Playlist contains the stream URL

**Pass Threshold**: 60%

## Skills Tested

- Network stream interface navigation
- URL input and handling
- Stream connection management
- Playlist creation with network sources
- Understanding streaming vs local playback

## Controls

- **Menu**: Media → Open Network Stream (Ctrl+N)
- **Playlist**: Ctrl+L to open playlist, Media → Save Playlist to File

## Real-World Context

This simulates accessing media from network sources like:
- IP cameras and webcam feeds
- Company media servers and training portals
- IPTV channels
- Streaming URLs shared by colleagues