#!/bin/bash
set -e
echo "=== Setting up implement_annotation_validator task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/chinook-validator"
mkdir -p "$PROJECT_DIR"

# ==============================================================================
# 1. Create Maven Project Structure
# ==============================================================================

# pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.chinook</groupId>
    <artifactId>chinook-validator</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter-api</artifactId>
            <version>5.9.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter-engine</artifactId>
            <version>5.9.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# Create package directories
mkdir -p "$PROJECT_DIR/src/main/java/com/chinook/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/chinook/validation"
mkdir -p "$PROJECT_DIR/src/test/java/com/chinook/validation"

# ==============================================================================
# 2. Create Domain Classes (Pre-annotated)
# ==============================================================================

# Artist.java
cat > "$PROJECT_DIR/src/main/java/com/chinook/model/Artist.java" << 'JAVAEOF'
package com.chinook.model;

import com.chinook.validation.*;

public class Artist {
    private int artistId;

    @NotNull
    @StringLength(min = 1, max = 120)
    private String name;

    public Artist(int artistId, String name) {
        this.artistId = artistId;
        this.name = name;
    }
}
JAVAEOF

# Album.java
cat > "$PROJECT_DIR/src/main/java/com/chinook/model/Album.java" << 'JAVAEOF'
package com.chinook.model;

import com.chinook.validation.*;

public class Album {
    private int albumId;

    @NotNull
    @StringLength(max = 160)
    private String title;

    @Range(min = 1)
    private int artistId;

    public Album(int albumId, String title, int artistId) {
        this.albumId = albumId;
        this.title = title;
        this.artistId = artistId;
    }
}
JAVAEOF

# Track.java
cat > "$PROJECT_DIR/src/main/java/com/chinook/model/Track.java" << 'JAVAEOF'
package com.chinook.model;

import com.chinook.validation.*;

public class Track {
    private int trackId;

    @NotNull
    @StringLength(max = 200)
    private String name;

    @Pattern(regex = "^[A-Za-z\\s\\.]+$")
    private String composer;

    @Range(min = 1)
    private int milliseconds;

    @Range(min = 0, max = 100)
    private double unitPrice;

    public Track(String name, String composer, int milliseconds, double unitPrice) {
        this.name = name;
        this.composer = composer;
        this.milliseconds = milliseconds;
        this.unitPrice = unitPrice;
    }
}
JAVAEOF

# ==============================================================================
# 3. Create Validation Framework Stubs
# ==============================================================================

# ValidationError.java (Complete)
cat > "$PROJECT_DIR/src/main/java/com/chinook/validation/ValidationError.java" << 'JAVAEOF'
package com.chinook.validation;

public class ValidationError {
    private final String field;
    private final String message;

    public ValidationError(String field, String message) {
        this.field = field;
        this.message = message;
    }

    public String getField() { return field; }
    public String getMessage() { return message; }

    @Override
    public String toString() {
        return "ValidationError{field='" + field + "', message='" + message + "'}";
    }
}
JAVAEOF

# Validator.java (Stub)
cat > "$PROJECT_DIR/src/main/java/com/chinook/validation/Validator.java" << 'JAVAEOF'
package com.chinook.validation;

import java.util.ArrayList;
import java.util.List;

public class Validator {

    public static List<ValidationError> validate(Object object) {
        List<ValidationError> errors = new ArrayList<>();
        // TODO: Implement validation using Reflection
        // 1. Iterate over all fields of the object
        // 2. Check for annotations (@NotNull, @StringLength, @Range, @Pattern)
        // 3. Validate values and add to errors list if invalid
        return errors;
    }
}
JAVAEOF

# Annotations (Stubs - Empty)
for ANN in NotNull StringLength Range Pattern; do
    cat > "$PROJECT_DIR/src/main/java/com/chinook/validation/${ANN}.java" << JAVAEOF
package com.chinook.validation;

public @interface ${ANN} {
    // TODO: Define retention, target, and attributes
}
JAVAEOF
done

# ==============================================================================
# 4. Create Tests
# ==============================================================================

cat > "$PROJECT_DIR/src/test/java/com/chinook/validation/ValidatorTest.java" << 'JAVAEOF'
package com.chinook.validation;

import com.chinook.model.Album;
import com.chinook.model.Artist;
import com.chinook.model.Track;
import org.junit.jupiter.api.Test;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;

class ValidatorTest {

    @Test
    void testValidArtist() {
        Artist artist = new Artist(1, "AC/DC");
        assertTrue(Validator.validate(artist).isEmpty(), "Valid artist should have no errors");
    }

    @Test
    void testNotNullArtistName() {
        Artist artist = new Artist(1, null);
        List<ValidationError> errors = Validator.validate(artist);
        assertEquals(1, errors.size());
        assertEquals("name", errors.get(0).getField());
        assertTrue(errors.get(0).getMessage().contains("null"));
    }

    @Test
    void testStringLengthMin() {
        Artist artist = new Artist(1, ""); // Min length is 1
        List<ValidationError> errors = Validator.validate(artist);
        assertEquals(1, errors.size());
        assertEquals("name", errors.get(0).getField());
    }

    @Test
    void testStringLengthMax() {
        String longName = "A".repeat(121); // Max is 120
        Artist artist = new Artist(1, longName);
        List<ValidationError> errors = Validator.validate(artist);
        assertEquals(1, errors.size());
        assertEquals("name", errors.get(0).getField());
    }

    @Test
    void testValidAlbum() {
        Album album = new Album(1, "Let There Be Rock", 1);
        assertTrue(Validator.validate(album).isEmpty());
    }

    @Test
    void testAlbumRange() {
        Album album = new Album(1, "Title", 0); // ArtistId min is 1
        List<ValidationError> errors = Validator.validate(album);
        assertEquals(1, errors.size());
        assertEquals("artistId", errors.get(0).getField());
    }

    @Test
    void testValidTrack() {
        Track track = new Track("Track 1", "Composer Name", 300000, 0.99);
        assertTrue(Validator.validate(track).isEmpty());
    }

    @Test
    void testPatternValid() {
        Track track = new Track("Track 1", "Mozart", 300000, 0.99);
        assertTrue(Validator.validate(track).isEmpty());
    }

    @Test
    void testPatternInvalid() {
        Track track = new Track("Track 1", "Mozart123", 300000, 0.99); // Numbers not allowed in regex
        List<ValidationError> errors = Validator.validate(track);
        assertEquals(1, errors.size());
        assertEquals("composer", errors.get(0).getField());
    }

    @Test
    void testPatternNullIgnored() {
        // Pattern should usually skip nulls (only NotNull checks nulls)
        Track track = new Track("Track 1", null, 300000, 0.99);
        assertTrue(Validator.validate(track).isEmpty());
    }

    @Test
    void testMultipleErrors() {
        // Null name + invalid price range
        Track track = new Track(null, "Mozart", 300000, 101.00);
        List<ValidationError> errors = Validator.validate(track);
        assertEquals(2, errors.size());
    }

    @Test
    void testRangeDouble() {
        Track track = new Track("Track", "Comp", 1, -0.01);
        List<ValidationError> errors = Validator.validate(track);
        assertEquals(1, errors.size());
        assertEquals("unitPrice", errors.get(0).getField());
    }

    @Test
    void testRangeInt() {
        Track track = new Track("Track", "Comp", 0, 0.99); // min is 1
        List<ValidationError> errors = Validator.validate(track);
        assertEquals(1, errors.size());
        assertEquals("milliseconds", errors.get(0).getField());
    }
    
    @Test
    void testGenericObject() {
        // Test that validator works on ad-hoc object
        class AdHoc {
            @NotNull String val = null;
        }
        List<ValidationError> errors = Validator.validate(new AdHoc());
        assertEquals(1, errors.size());
    }
}
JAVAEOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record anti-gaming timestamps and hashes
date +%s > /tmp/task_start_time.txt
md5sum "$PROJECT_DIR/src/test/java/com/chinook/validation/ValidatorTest.java" > /tmp/initial_test_hash.txt

# ==============================================================================
# 5. Initialize IDE
# ==============================================================================

# Launch project
setup_intellij_project "$PROJECT_DIR" "chinook-validator" 120

# Force a compile to download dependencies (will likely fail tests, that's expected)
su - ga -c "cd $PROJECT_DIR && mvn compile -q 2>/dev/null || true"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="