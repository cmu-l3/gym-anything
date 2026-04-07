#!/bin/bash
echo "=== Setting up build_quote_explorer_app task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure tiddlers directory exists
mkdir -p "$TIDDLER_DIR"

# Clean up any previous state
rm -f "$TIDDLER_DIR/Quote Explorer.tid" 2>/dev/null || true
rm -f "$TIDDLER_DIR/Quote_ Explorer.tid" 2>/dev/null || true
find "$TIDDLER_DIR" -type f -name "Quote_*.tid" -delete 2>/dev/null || true

echo "Injecting real quote data..."

# Generate 10 real historical/scientific quotes
cat > "$TIDDLER_DIR/Quote_ Pale Blue Dot.tid" << 'EOF'
title: Quote: Pale Blue Dot
tags: Quote
author: Carl Sagan
source: Pale Blue Dot: A Vision of the Human Future in Space

Look again at that dot. That's here. That's home. That's us. On it everyone you love, everyone you know, everyone you ever heard of, every human being who ever was, lived out their lives.
EOF

cat > "$TIDDLER_DIR/Quote_ Fear in Life.tid" << 'EOF'
title: Quote: Fear in Life
tags: Quote
author: Marie Curie
source: Autobiographical Notes

Nothing in life is to be feared, it is only to be understood. Now is the time to understand more, so that we may fear less.
EOF

cat > "$TIDDLER_DIR/Quote_ Safely Say.tid" << 'EOF'
title: Quote: Safely Say
tags: Quote
author: Richard Feynman
source: The Character of Physical Law

I think I can safely say that nobody understands quantum mechanics.
EOF

cat > "$TIDDLER_DIR/Quote_ Analytical Engine.tid" << 'EOF'
title: Quote: Analytical Engine
tags: Quote
author: Ada Lovelace
source: Notes on the Analytical Engine

The Analytical Engine weaves algebraic patterns just as the Jacquard loom weaves flowers and leaves.
EOF

cat > "$TIDDLER_DIR/Quote_ Forgiveness.tid" << 'EOF'
title: Quote: Forgiveness
tags: Quote
author: Grace Hopper
source: Navy Management Review

It's easier to ask forgiveness than it is to get permission.
EOF

cat > "$TIDDLER_DIR/Quote_ Imagination.tid" << 'EOF'
title: Quote: Imagination
tags: Quote
author: Albert Einstein
source: Interview in The Saturday Evening Post

Imagination is more important than knowledge. For knowledge is limited, whereas imagination embraces the entire world, stimulating progress, giving birth to evolution.
EOF

cat > "$TIDDLER_DIR/Quote_ Science and Life.tid" << 'EOF'
title: Quote: Science and Life
tags: Quote
author: Rosalind Franklin
source: Letter to Ellis Franklin

Science and everyday life cannot and should not be separated.
EOF

cat > "$TIDDLER_DIR/Quote_ Small Step.tid" << 'EOF'
title: Quote: Small Step
tags: Quote
author: Neil Armstrong
source: Apollo 11 Lunar Landing

That's one small step for man, one giant leap for mankind.
EOF

cat > "$TIDDLER_DIR/Quote_ Make a Difference.tid" << 'EOF'
title: Quote: Make a Difference
tags: Quote
author: Jane Goodall
source: Reason for Hope

What you do makes a difference, and you have to decide what kind of difference you want to make.
EOF

cat > "$TIDDLER_DIR/Quote_ Look Up.tid" << 'EOF'
title: Quote: Look Up
tags: Quote
author: Stephen Hawking
source: London Paralympic Games Opening Ceremony

Remember to look up at the stars and not down at your feet. Try to make sense of what you see and wonder about what makes the universe exist. Be curious.
EOF

# Fix permissions
chown -R ga:ga "$TIDDLER_DIR"

# Allow TiddlyWiki a moment to pick up the new files
sleep 3

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 2

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="