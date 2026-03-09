#!/bin/bash
set -e
echo "=== Setting up task: implement_lru_cache_mri ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

PROJECT_NAME="MedicalImagingSystem"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# 1. Clean up previous runs
rm -rf "$PROJECT_DIR"

# 2. Create Maven Project Structure
mkdir -p "$PROJECT_DIR/src/main/java/com/medsys/imaging"
mkdir -p "$PROJECT_DIR/src/test/java/com/medsys/imaging"
mkdir -p "$PROJECT_DIR/.settings"

# 3. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.medsys</groupId>
    <artifactId>medical-imaging-system</artifactId>
    <version>1.0.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.0</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.1.2</version>
            </plugin>
        </plugins>
    </build>
</project>
EOF

# 4. Create MRISlice.java (Simulated Data Object)
cat > "$PROJECT_DIR/src/main/java/com/medsys/imaging/MRISlice.java" << 'EOF'
package com.medsys.imaging;

import java.util.UUID;

/**
 * Represents a single MRI slice image (DICOM data).
 * Simulates heavy memory usage.
 */
public class MRISlice {
    private final String id;
    private final byte[] imageData;
    private final int sliceIndex;

    public MRISlice(int sliceIndex) {
        this.id = UUID.randomUUID().toString();
        this.sliceIndex = sliceIndex;
        // Allocate 5MB per slice to simulate high-res medical imagery
        this.imageData = new byte[5 * 1024 * 1024]; 
    }

    public String getId() { return id; }
    public int getSliceIndex() { return sliceIndex; }
}
EOF

# 5. Create MRISliceCache.java (The Problematic Class)
cat > "$PROJECT_DIR/src/main/java/com/medsys/imaging/MRISliceCache.java" << 'EOF'
package com.medsys.imaging;

import java.util.HashMap;
import java.util.Map;

/**
 * Caches loaded MRI slices to improve scrolling performance in the viewer.
 * 
 * TODO: This cache currently grows indefinitely.
 * We need to limit it to hold only the most recent 20 slices
 * to prevent OutOfMemory errors on client workstations.
 */
public class MRISliceCache {

    // PROBLEM: Standard HashMap grows without bound
    private static final Map<Integer, MRISlice> cache = new HashMap<>();

    /**
     * Retrieves a slice from cache or returns null if not present.
     */
    public static MRISlice getSlice(int index) {
        return cache.get(index);
    }

    /**
     * Adds a slice to the cache.
     */
    public static void putSlice(int index, MRISlice slice) {
        cache.put(index, slice);
        // Debug output to monitor growth
        if (cache.size() % 5 == 0) {
            System.out.println("Cache size: " + cache.size());
        }
    }
    
    /**
     * Returns current cache size.
     */
    public static int getSize() {
        return cache.size();
    }
    
    /**
     * Clears the cache.
     */
    public static void clear() {
        cache.clear();
    }
}
EOF

# 6. Create CacheStabilityTest.java (The Verification Test)
cat > "$PROJECT_DIR/src/test/java/com/medsys/imaging/CacheStabilityTest.java" << 'EOF'
package com.medsys.imaging;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class CacheStabilityTest {

    private static final int MAX_CACHE_SIZE = 20;

    @BeforeEach
    void setUp() {
        MRISliceCache.clear();
    }

    @Test
    void testCacheEvictionPolicy() {
        System.out.println("Starting functional eviction test...");
        
        // 1. Fill cache up to the limit
        for (int i = 0; i < MAX_CACHE_SIZE; i++) {
            MRISliceCache.putSlice(i, new MRISlice(i));
        }
        
        assertEquals(MAX_CACHE_SIZE, MRISliceCache.getSize(), "Cache should hold " + MAX_CACHE_SIZE + " items");
        
        // 2. Add one more item (should trigger eviction of index 0)
        MRISliceCache.putSlice(MAX_CACHE_SIZE, new MRISlice(MAX_CACHE_SIZE));
        
        // Verify size did not grow
        assertEquals(MAX_CACHE_SIZE, MRISliceCache.getSize(), "Cache size should not exceed " + MAX_CACHE_SIZE);
        
        // Verify the oldest item (0) is gone
        assertNull(MRISliceCache.getSlice(0), "Oldest item (0) should have been evicted");
        
        // Verify the newest item exists
        assertNotNull(MRISliceCache.getSlice(MAX_CACHE_SIZE), "Newest item should be in cache");
    }

    @Test
    void testMemoryStability() {
        System.out.println("Starting memory stability stress test...");
        // This test attempts to load 100 slices.
        // Without eviction: 100 * 5MB = 500MB.
        // This will likely cause OOM or fail the assertion if the heap is constrained.
        
        int limit = 100;
        for (int i = 0; i < limit; i++) {
            MRISliceCache.putSlice(i, new MRISlice(i));
            
            // Check constraint after filling
            if (i >= MAX_CACHE_SIZE) {
                if (MRISliceCache.getSize() > MAX_CACHE_SIZE) {
                     fail("Cache grew beyond limit! Current size: " + MRISliceCache.getSize());
                }
            }
        }
    }
}
EOF

# 7. Configure Eclipse Project Metadata (so import is smooth)
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>MedicalImagingSystem</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
		<buildCommand>
			<name>org.eclipse.m2e.core.maven2Builder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
		<nature>org.eclipse.m2e.core.maven2Nature</nature>
	</natures>
</projectDescription>
EOF

cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" output="target/classes" path="src/main/java">
		<attributes>
			<attribute name="optional" value="true"/>
			<attribute name="maven.pomderived" value="true"/>
		</attributes>
	</classpathentry>
	<classpathentry kind="src" output="target/test-classes" path="src/test/java">
		<attributes>
			<attribute name="optional" value="true"/>
			<attribute name="maven.pomderived" value="true"/>
			<attribute name="test" value="true"/>
		</attributes>
	</classpathentry>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
		<attributes>
			<attribute name="maven.pomderived" value="true"/>
		</attributes>
	</classpathentry>
	<classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
		<attributes>
			<attribute name="maven.pomderived" value="true"/>
		</attributes>
	</classpathentry>
	<classpathentry kind="output" path="target/classes"/>
</classpath>
EOF

# 8. Set Ownership
chown -R ga:ga "$PROJECT_DIR"

# 9. Pre-compile to download dependencies
echo "Pre-warming Maven dependencies..."
cd "$PROJECT_DIR"
su - ga -c "cd $PROJECT_DIR && mvn clean compile test-compile"

# 10. Start Eclipse
# Ensure Eclipse is running
if ! pgrep -f "eclipse" > /dev/null; then
    echo "Starting Eclipse..."
    su - ga -c "DISPLAY=:1 /opt/eclipse/eclipse -data /home/ga/eclipse-workspace > /tmp/eclipse.log 2>&1 &"
    # Wait for window
    wait_for_eclipse 120 || echo "WARNING: Eclipse failed to start"
fi

# 11. Focus and maximize
focus_eclipse_window
sleep 2

# 12. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="