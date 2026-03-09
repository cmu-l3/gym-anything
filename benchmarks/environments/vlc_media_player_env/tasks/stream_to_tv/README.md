# Stream to TV Task

**Difficulty**: 🟡 Medium  
**Skills**: Network streaming, HTTP server configuration, local network sharing  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Configure VLC Media Player to stream a video file over HTTP on the local network, making it accessible to other devices (TV, tablet, phone) without copying files.

## Scenario

You're in your bedroom with your laptop. Your roommates in the living room want to watch a documentary video (`nature_doc.mp4`) you just downloaded. Instead of copying files to a USB drive or uploading to the cloud, you'll set up VLC to stream it over the local network so they can watch instantly.

## Task Description

The agent must:
1. Open VLC's streaming interface
2. Configure HTTP streaming for `/home/ga/Videos/nature_doc.mp4`
3. Stream on port **8080**
4. Document the stream URL in `/home/ga/stream_url.txt`
5. Keep VLC running in streaming mode

## Expected Results

- VLC configured as HTTP streaming server on port 8080
- Stream accessible at `http://<local_ip>:8080/`
- Stream URL documented in text file
- Video content served over HTTP

## Verification Criteria

1. ✅ **Stream URL Documented**: File exists with valid URL format
2. ✅ **VLC Streaming**: VLC process running in stream output mode
3. ✅ **Port Listening**: Port 8080 in LISTEN state
4. ✅ **Stream Accessible**: HTTP server responding with media content

**Pass Threshold**: 75%

## Skills Tested

- Understanding VLC's streaming capabilities vs playback
- Network streaming protocol configuration (HTTP)
- Port and IP address concepts
- Stream vs file transfer decision-making
- Server mode operation

## Controls

- **Menu**: Media → Stream (Ctrl+S)
- **CLI**: `cvlc --sout '#standard{access=http,mux=ts,dst=:8080/}'`
- **Network**: Check local IP with `ip addr` or `hostname -I`

## Notes

- Use HTTP (not RTSP/RTP) for maximum compatibility with basic media players
- Stream must remain active (don't close VLC)
- Port 8080 is commonly used for HTTP alternatives and usually not blocked
- This enables instant multi-device access without file duplication