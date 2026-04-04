# Diagnose Event Listener Leak Task

**Difficulty**: 🟡 Medium  
**Skills**: Debugging, memory management, Node.js, event-driven programming  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Fix a memory leak in a Node.js WebSocket handler by identifying event listeners that are never removed and adding proper cleanup logic.

## Background

The WebSocket service is experiencing memory growth in production. Event listeners are registered on connection objects but never cleaned up when connections close, causing memory leaks. Additionally, a ping interval timer is never cleared.

## Expected Workflow

1. Open `/home/ga/workspace/memory-leak-project/src/websocket-handler.js`
2. Identify event listeners registered with `.on()` that lack cleanup
3. Locate the `setInterval` for ping that is never cleared
4. Add cleanup logic in the `close` event handler:
   - Use `.removeAllListeners('message')` or `.removeListener()`
   - Use `.removeAllListeners('error')`
   - Call `clearInterval(pingInterval)`
5. Save the file (Ctrl+S)

## Verification

Checks for:
1. Presence of listener removal calls (removeAllListeners/removeListener/off)
2. clearInterval call for pingInterval
3. Cleanup logic in close handler
4. Removal of message listener
5. Removal of error listener

**Pass Threshold**: 85% (at least 4/5 criteria)

## Common Patterns

- Register listener: `ws.on('event', handler)`
- Remove listener: `ws.removeListener('event', handler)` or `ws.removeAllListeners('event')`
- Remove all: `ws.removeAllListeners()`
- Clear timers: `clearInterval(intervalId)`