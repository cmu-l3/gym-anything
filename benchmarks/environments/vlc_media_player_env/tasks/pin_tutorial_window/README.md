# Pin Tutorial Window Task

**Difficulty**: 🟢 Easy-Medium  
**Skills**: Window management, menu navigation, UI positioning  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Configure VLC as an always-visible tutorial window by enabling "always on top" mode, resizing to a compact size, and positioning in the top-right corner of the screen.

## Task Description

The agent must:
1. VLC launches with a tutorial video playing
2. Enable "Always on Top" mode (Video menu or right-click)
3. Resize the window to compact tutorial size (~640x360 pixels)
4. Position the window in the top-right corner of the screen

## Real-World Context

Developers and learners often follow tutorial videos while working in other applications. Keeping the tutorial visible in a corner without constantly switching windows improves workflow and learning efficiency.

## Expected Results

- VLC window has "Always on Top" property enabled
- Window dimensions are compact (500-700 x 300-450 pixels)
- Window positioned in top-right area (right half of screen, near top edge)
- Configuration persists and is verifiable

## Verification Criteria

1. ✅ **Window Config Accessible**: Window properties retrieved successfully
2. ✅ **Compact Size**: Window dimensions 500-700 x 300-450 pixels
3. ✅ **Top-Right Position**: Window in right half and near top of screen
4. ✅ **Always on Top**: Window has _NET_WM_STATE_ABOVE property

**Pass Threshold**: 75%

## Skills Tested

- Menu navigation (Video → Always on Top)
- Window management (resize, reposition)
- Understanding of window behavior
- Spatial awareness of screen layout

## Controls

- **Menu**: Video → Always on Top
- **Right-click**: Title bar → Always on Top (depending on window manager)
- **Resize**: Drag window corners/edges
- **Move**: Drag title bar to top-right corner

## Notes

Window decorations (title bar) may vary by desktop environment. The verification accounts for typical title bar heights (~30-40px) when checking position.