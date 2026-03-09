#!/bin/bash
set -e
echo "=== Setting up resolve_compiler_warnings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
SOURCE_DIR="/home/ga/project-sources/DataUtils"
WORKSPACE_DIR="/home/ga/eclipse-workspace"

# Clean up any previous runs
rm -rf "$SOURCE_DIR"
rm -rf "$WORKSPACE_DIR/DataUtils"

# Create source directory structure
mkdir -p "$SOURCE_DIR/src/com/datautils/core"
mkdir -p "$SOURCE_DIR/src/com/datautils/collections"

# --- Generate Java Files with Warnings ---

# 1. DataProcessor.java (Raw types, unused variable)
cat > "$SOURCE_DIR/src/com/datautils/core/DataProcessor.java" << 'EOF'
package com.datautils.core;

import java.util.ArrayList;
import java.util.List;

public class DataProcessor {
    
    // Warning: Raw type
    public List processData(List input) {
        // Warning: Raw type
        List result = new ArrayList();
        
        // Warning: Unused variable
        int unusedCounter = 0;
        
        for (Object obj : input) {
            if (obj instanceof String) {
                result.add(((String) obj).trim());
            }
        }
        return result;
    }
}
EOF

# 2. CacheManager.java (Missing serialVersionUID, resource leak, unused import)
cat > "$SOURCE_DIR/src/com/datautils/core/CacheManager.java" << 'EOF'
package com.datautils.core;

import java.io.Serializable;
import java.io.FileOutputStream;
import java.io.IOException;
// Warning: Unused import
import java.util.Date;

// Warning: Missing serialVersionUID
public class CacheManager implements Serializable {
    
    public void saveCache(String data) throws IOException {
        // Warning: Resource leak (unclosed stream)
        FileOutputStream fos = new FileOutputStream("cache.dat");
        fos.write(data.getBytes());
        // Missing fos.close();
    }
}
EOF

# 3. StringHelper.java (Deprecated API, unused imports)
cat > "$SOURCE_DIR/src/com/datautils/core/StringHelper.java" << 'EOF'
package com.datautils.core;

import java.net.URLEncoder;
// Warning: Unused import
import java.util.Vector;
// Warning: Unused import
import java.util.Hashtable;

public class StringHelper {
    
    public String encode(String s) {
        // Warning: Deprecated method
        return URLEncoder.encode(s);
    }
}
EOF

# 4. SortedBuffer.java (Raw types, missing @Override)
cat > "$SOURCE_DIR/src/com/datautils/collections/SortedBuffer.java" << 'EOF'
package com.datautils.collections;

import java.util.Collections;
import java.util.LinkedList;
import java.util.List;

// Warning: Raw type
public class SortedBuffer implements Comparable {
    
    private List<String> buffer = new LinkedList<>();
    
    // Warning: Missing @Override annotation
    public int compareTo(Object o) {
        return 0;
    }
    
    public void sort() {
        Collections.sort(buffer);
    }
}
EOF

# 5. Pair.java (Unused imports, dead code)
cat > "$SOURCE_DIR/src/com/datautils/collections/Pair.java" << 'EOF'
package com.datautils.collections;

// Warning: Unused import
import java.io.File;

public class Pair<K, V> {
    private K key;
    private V value;
    
    public Pair(K key, V value) {
        this.key = key;
        this.value = value;
    }
    
    public void check() {
        if (true) {
            return;
        }
        // Warning: Dead code
        System.out.println("This is unreachable");
    }
}
EOF

# 6. Registry.java (Unchecked cast, unnecessary cast)
cat > "$SOURCE_DIR/src/com/datautils/collections/Registry.java" << 'EOF'
package com.datautils.collections;

import java.util.HashMap;
import java.util.Map;

public class Registry {
    private Map<String, Object> items = new HashMap<>();
    
    public void register(String key, Object value) {
        items.put(key, value);
    }
    
    public <T> T get(String key) {
        // Warning: Unchecked cast
        return (T) items.get(key);
    }
    
    public String getString(String key) {
        // Warning: Unnecessary cast
        return (String) ((String) items.get(key));
    }
}
EOF

# Create .project and .classpath to make it a valid Eclipse project
cat > "$SOURCE_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>DataUtils</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

cat > "$SOURCE_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# Set permissions
chown -R ga:ga "$SOURCE_DIR"

# Record initial checksums of source files (to verify modification)
find "$SOURCE_DIR/src" -name "*.java" -type f -exec sha256sum {} \; | sort > /tmp/initial_checksums.txt

# Wait for Eclipse and ensure it's ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Project DataUtils created at $SOURCE_DIR"
echo "Agent must import this project and fix warnings."