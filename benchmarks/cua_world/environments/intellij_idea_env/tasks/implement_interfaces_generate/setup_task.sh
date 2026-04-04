#!/bin/bash
set -e
echo "=== Setting up implement_interfaces_generate task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/IdeaProjects/music-catalog"

# Clean previous attempts
rm -rf "$PROJECT_DIR"
rm -f /tmp/test_results.log
rm -f /tmp/task_result.json

# Create project structure
mkdir -p "$PROJECT_DIR/src/main/java/com/musiccatalog/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/musiccatalog/impl"
mkdir -p "$PROJECT_DIR/src/test/java/com/musiccatalog"

# === pom.xml ===
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.musiccatalog</groupId>
    <artifactId>music-catalog</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
    <dependencies>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.12</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# === INTERFACES ===

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/model/Playable.java" << 'JAVAEOF'
package com.musiccatalog.model;

public interface Playable {
    void play();
    void stop();
    boolean isPlaying();
    int getDurationMs();
}
JAVAEOF

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/model/Catalogable.java" << 'JAVAEOF'
package com.musiccatalog.model;
import java.time.LocalDate;

public interface Catalogable {
    String getId();
    String getName();
    String getCategory();
    LocalDate getDateAdded();
}
JAVAEOF

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/model/Searchable.java" << 'JAVAEOF'
package com.musiccatalog.model;

public interface Searchable {
    boolean matchesQuery(String query);
    String[] getSearchKeywords();
}
JAVAEOF

# === IMPLEMENTATION STUBS ===

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/impl/Track.java" << 'JAVAEOF'
package com.musiccatalog.impl;

import com.musiccatalog.model.Playable;
import com.musiccatalog.model.Catalogable;
import com.musiccatalog.model.Searchable;
import java.time.LocalDate;

public class Track implements Playable, Catalogable, Searchable {
    private String trackId;
    private String name;
    private String albumId;
    private String genre;
    private int durationMs;
    private double price;
    private LocalDate dateAdded;
    private boolean playing;

    // TODO: Generate Constructor (initialize all fields except 'playing')
    // TODO: Implement Interface Methods
    // TODO: Generate equals(), hashCode(), toString()
}
JAVAEOF

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/impl/Album.java" << 'JAVAEOF'
package com.musiccatalog.impl;

import com.musiccatalog.model.Catalogable;
import com.musiccatalog.model.Searchable;
import java.time.LocalDate;

public class Album implements Catalogable, Searchable {
    private String albumId;
    private String name;
    private String artistId;
    private int year;
    private LocalDate dateAdded;

    // TODO: Generate Constructor
    // TODO: Implement Interface Methods
    // TODO: Generate equals(), hashCode(), toString()
}
JAVAEOF

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/impl/Artist.java" << 'JAVAEOF'
package com.musiccatalog.impl;

import com.musiccatalog.model.Catalogable;
import com.musiccatalog.model.Searchable;
import java.time.LocalDate;

public class Artist implements Catalogable, Searchable {
    private String artistId;
    private String name;
    private String country;
    private LocalDate dateAdded;

    // TODO: Generate Constructor
    // TODO: Implement Interface Methods
    // TODO: Generate equals(), hashCode(), toString()
}
JAVAEOF

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/impl/Playlist.java" << 'JAVAEOF'
package com.musiccatalog.impl;

import com.musiccatalog.model.Playable;
import com.musiccatalog.model.Searchable;
import java.time.LocalDate;
import java.util.List;

public class Playlist implements Playable, Searchable {
    private String playlistId;
    private String name;
    private List<String> trackIds;
    private int totalDurationMs;
    private LocalDate dateAdded;
    private boolean playing;

    // TODO: Generate Constructor (initialize all fields except 'playing')
    // TODO: Implement Interface Methods
    // TODO: Generate equals(), hashCode(), toString()
}
JAVAEOF

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/impl/Podcast.java" << 'JAVAEOF'
package com.musiccatalog.impl;

import com.musiccatalog.model.Playable;
import com.musiccatalog.model.Catalogable;
import java.time.LocalDate;

public class Podcast implements Playable, Catalogable {
    private String podcastId;
    private String name;
    private String publisher;
    private int durationMs;
    private LocalDate dateAdded;
    private boolean playing;

    // TODO: Generate Constructor (initialize all fields except 'playing')
    // TODO: Implement Interface Methods
    // TODO: Generate equals(), hashCode(), toString()
}
JAVAEOF

cat > "$PROJECT_DIR/src/main/java/com/musiccatalog/impl/Genre.java" << 'JAVAEOF'
package com.musiccatalog.impl;

import com.musiccatalog.model.Catalogable;
import java.time.LocalDate;

public class Genre implements Catalogable {
    private String genreId;
    private String name;
    private String description;
    private LocalDate dateAdded;

    // TODO: Generate Constructor
    // TODO: Implement Interface Methods
    // TODO: Generate equals(), hashCode(), toString()
}
JAVAEOF

# === TEST FILES ===

cat > "$PROJECT_DIR/src/test/java/com/musiccatalog/TrackTest.java" << 'JAVAEOF'
package com.musiccatalog;
import com.musiccatalog.impl.Track;
import org.junit.Test;
import java.time.LocalDate;
import static org.junit.Assert.*;

public class TrackTest {
    @Test
    public void testContracts() {
        Track t = new Track("T1", "Song", "A1", "Rock", 300, 1.0, LocalDate.now());
        assertEquals("T1", t.getId());
        assertEquals("Song", t.getName());
        assertEquals("Track", t.getCategory());
        
        t.play();
        assertTrue(t.isPlaying());
        t.stop();
        assertFalse(t.isPlaying());
        
        assertTrue(t.matchesQuery("song"));
        assertNotNull(t.getSearchKeywords());
        
        Track t2 = new Track("T1", "Song", "A1", "Rock", 300, 1.0, LocalDate.now());
        assertEquals(t, t2);
        assertNotNull(t.toString());
    }
}
JAVAEOF

cat > "$PROJECT_DIR/src/test/java/com/musiccatalog/AlbumTest.java" << 'JAVAEOF'
package com.musiccatalog;
import com.musiccatalog.impl.Album;
import org.junit.Test;
import java.time.LocalDate;
import static org.junit.Assert.*;

public class AlbumTest {
    @Test
    public void testContracts() {
        Album a = new Album("A1", "Best Of", "Artist1", 2020, LocalDate.now());
        assertEquals("A1", a.getId());
        assertEquals("Album", a.getCategory());
        assertTrue(a.matchesQuery("best"));
        
        Album a2 = new Album("A1", "Best Of", "Artist1", 2020, LocalDate.now());
        assertEquals(a, a2);
        assertNotNull(a.toString());
    }
}
JAVAEOF

cat > "$PROJECT_DIR/src/test/java/com/musiccatalog/ArtistTest.java" << 'JAVAEOF'
package com.musiccatalog;
import com.musiccatalog.impl.Artist;
import org.junit.Test;
import java.time.LocalDate;
import static org.junit.Assert.*;

public class ArtistTest {
    @Test
    public void testContracts() {
        Artist a = new Artist("AR1", "The Band", "UK", LocalDate.now());
        assertEquals("AR1", a.getId());
        assertEquals("Artist", a.getCategory());
        assertTrue(a.matchesQuery("band"));
        
        Artist a2 = new Artist("AR1", "The Band", "UK", LocalDate.now());
        assertEquals(a, a2);
        assertNotNull(a.toString());
    }
}
JAVAEOF

cat > "$PROJECT_DIR/src/test/java/com/musiccatalog/PlaylistTest.java" << 'JAVAEOF'
package com.musiccatalog;
import com.musiccatalog.impl.Playlist;
import org.junit.Test;
import java.time.LocalDate;
import java.util.Collections;
import static org.junit.Assert.*;

public class PlaylistTest {
    @Test
    public void testContracts() {
        Playlist p = new Playlist("P1", "My Jams", Collections.emptyList(), 500, LocalDate.now());
        p.play();
        assertTrue(p.isPlaying());
        assertEquals(500, p.getDurationMs());
        assertTrue(p.matchesQuery("jams"));
        
        Playlist p2 = new Playlist("P1", "My Jams", Collections.emptyList(), 500, LocalDate.now());
        assertEquals(p, p2);
        assertNotNull(p.toString());
    }
}
JAVAEOF

cat > "$PROJECT_DIR/src/test/java/com/musiccatalog/PodcastTest.java" << 'JAVAEOF'
package com.musiccatalog;
import com.musiccatalog.impl.Podcast;
import org.junit.Test;
import java.time.LocalDate;
import static org.junit.Assert.*;

public class PodcastTest {
    @Test
    public void testContracts() {
        Podcast p = new Podcast("PC1", "Daily News", "NPR", 1000, LocalDate.now());
        assertEquals("PC1", p.getId());
        assertEquals("Podcast", p.getCategory());
        p.play();
        assertTrue(p.isPlaying());
        
        Podcast p2 = new Podcast("PC1", "Daily News", "NPR", 1000, LocalDate.now());
        assertEquals(p, p2);
        assertNotNull(p.toString());
    }
}
JAVAEOF

cat > "$PROJECT_DIR/src/test/java/com/musiccatalog/GenreTest.java" << 'JAVAEOF'
package com.musiccatalog;
import com.musiccatalog.impl.Genre;
import org.junit.Test;
import java.time.LocalDate;
import static org.junit.Assert.*;

public class GenreTest {
    @Test
    public void testContracts() {
        Genre g = new Genre("G1", "Rock", "Loud", LocalDate.now());
        assertEquals("G1", g.getId());
        assertEquals("Genre", g.getCategory());
        
        Genre g2 = new Genre("G1", "Rock", "Loud", LocalDate.now());
        assertEquals(g, g2);
        assertNotNull(g.toString());
    }
}
JAVAEOF

# Save initial file hashes for anti-gaming
find "$PROJECT_DIR/src/main/java/com/musiccatalog/impl" -name "*.java" -exec md5sum {} \; > /tmp/initial_impl_hashes.txt

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "music-catalog" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="