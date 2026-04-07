#!/bin/bash
echo "=== Setting up create_custom_viewtemplate task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the 3 seed tiddlers containing real academic paper data
cat > "$TIDDLER_DIR/Attention Is All You Need.tid" << 'EOF'
title: Attention Is All You Need
tags: Paper
author: Vaswani et al.
journal: NeurIPS
year: 2017
doi: 10.48550/arXiv.1706.03762
type: text/vnd.tiddlywiki

The dominant sequence transduction models are based on complex recurrent or convolutional neural networks that include an encoder and a decoder. The best performing models also connect the encoder and decoder through an attention mechanism. We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely.
EOF

cat > "$TIDDLER_DIR/MapReduce.tid" << 'EOF'
title: MapReduce
tags: Paper
author: Jeffrey Dean, Sanjay Ghemawat
journal: OSDI
year: 2004
doi: 10.1145/1327452.1327492
type: text/vnd.tiddlywiki

MapReduce is a programming model and an associated implementation for processing and generating large data sets. Users specify a map function that processes a key/value pair to generate a set of intermediate key/value pairs, and a reduce function that merges all intermediate values associated with the same intermediate key.
EOF

cat > "$TIDDLER_DIR/ResNet.tid" << 'EOF'
title: ResNet
tags: Paper
author: Kaiming He, Xiangyu Zhang, Shaoqing Ren, Jian Sun
journal: CVPR
year: 2016
doi: 10.1109/CVPR.2016.90
type: text/vnd.tiddlywiki

Deeper neural networks are more difficult to train. We present a residual learning framework to ease the training of networks that are substantially deeper than those used previously. We explicitly reformulate the layers as learning residual functions with reference to the layer inputs, instead of learning unreferenced functions.
EOF

chown -R ga:ga "$TIDDLER_DIR"

# Allow Node.js to sync the new files
sleep 3

# Record initial md5 hashes of the text bodies to prevent gaming (direct edits)
md5sum "$TIDDLER_DIR/Attention Is All You Need.tid" | awk '{print $1}' > /tmp/seed1_hash
md5sum "$TIDDLER_DIR/MapReduce.tid" | awk '{print $1}' > /tmp/seed2_hash
md5sum "$TIDDLER_DIR/ResNet.tid" | awk '{print $1}' > /tmp/seed3_hash

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/viewtemplate_initial.png

echo "=== Task setup complete ==="