#!/bin/bash
echo "=== Setting up build_dynamic_recipe_scaler task ==="
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the data tiddlers for Baguette recipe
cat > "$TIDDLER_DIR/Bread Flour.tid" << 'EOF'
title: Bread Flour
recipe: Baguette
ingredient: Bread Flour
base_amount: 1000
unit: g
tags: Ingredient

EOF

cat > "$TIDDLER_DIR/Water.tid" << 'EOF'
title: Water
recipe: Baguette
ingredient: Water
base_amount: 700
unit: ml
tags: Ingredient

EOF

cat > "$TIDDLER_DIR/Salt.tid" << 'EOF'
title: Salt
recipe: Baguette
ingredient: Salt
base_amount: 20
unit: g
tags: Ingredient

EOF

cat > "$TIDDLER_DIR/Instant Yeast.tid" << 'EOF'
title: Instant Yeast
recipe: Baguette
ingredient: Instant Yeast
base_amount: 7
unit: g
tags: Ingredient

EOF

chown ga:ga "$TIDDLER_DIR"/*.tid

# Ensure TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Focus browser window
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/scaler_initial.png

echo "=== Task setup complete ==="