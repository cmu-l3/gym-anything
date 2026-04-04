#!/bin/bash
set -e
echo "=== Setting up migrate_kapt_to_ksp task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="NoteApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_PATH="com/example/noteapp"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/$PACKAGE_PATH"

# Cleanup previous attempts
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

echo "Generating NoteApp project files..."

# 1. settings.gradle.kts
cat > "$PROJECT_DIR/settings.gradle.kts" << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "NoteApp"
include(":app")
EOF

# 2. build.gradle.kts (Project Level)
# Note: Intentionally NOT including KSP plugin yet
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
EOF

# 3. app/build.gradle.kts (App Level)
# Configured with KAPT
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.kapt")
}

android {
    namespace = "com.example.noteapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.noteapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    
    // Room components
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    kapt("androidx.room:room-compiler:$roomVersion")
}

// KAPT Configuration block (needs to be removed during migration)
kapt {
    correctErrorTypes = true
}
EOF

# 4. Create Source Files
mkdir -p "$PACKAGE_DIR/data"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"

# AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.NoteApp"
        tools:targetApi="31">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

# XML Resources (dummy files to prevent build errors)
mkdir -p "$PROJECT_DIR/app/src/main/res/xml"
echo "<data-extraction-rules></data-extraction-rules>" > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml"
echo "<full-backup-content></full-backup-content>" > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml"

cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">NoteApp</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.NoteApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@color/white</item>
    </style>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

# Note Entity
cat > "$PACKAGE_DIR/data/Note.kt" << 'EOF'
package com.example.noteapp.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "notes")
data class Note(
    @PrimaryKey(autoGenerate = true)
    val id: Int = 0,
    val title: String,
    val content: String,
    val timestamp: Long
)
EOF

# Note DAO
cat > "$PACKAGE_DIR/data/NoteDao.kt" << 'EOF'
package com.example.noteapp.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface NoteDao {
    @Insert
    suspend fun insert(note: Note)

    @Update
    suspend fun update(note: Note)

    @Delete
    suspend fun delete(note: Note)

    @Query("SELECT * FROM notes ORDER BY timestamp DESC")
    fun getAllNotes(): Flow<List<Note>>
}
EOF

# Note Database
cat > "$PACKAGE_DIR/data/NoteDatabase.kt" << 'EOF'
package com.example.noteapp.data

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [Note::class], version = 1, exportSchema = false)
abstract class NoteDatabase : RoomDatabase() {
    abstract fun noteDao(): NoteDao
}
EOF

# Main Activity (Minimal)
cat > "$PACKAGE_DIR/MainActivity.kt" << 'EOF'
package com.example.noteapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // No layout needed for build test
    }
}
EOF

# 5. Gradle Wrapper
echo "Copying Gradle wrapper..."
# We assume the environment has a standard wrapper or we can copy from another project
# If not available, we can rely on Android Studio to fix it, but let's try to copy from template
if [ -d "/workspace/data/SunflowerApp/gradle" ]; then
    mkdir -p "$PROJECT_DIR/gradle"
    cp -r /workspace/data/SunflowerApp/gradle "$PROJECT_DIR/"
    cp /workspace/data/SunflowerApp/gradlew "$PROJECT_DIR/"
    cp /workspace/data/SunflowerApp/gradlew.bat "$PROJECT_DIR/"
    cp /workspace/data/SunflowerApp/gradle.properties "$PROJECT_DIR/"
else
    # Fallback: create a basic gradle.properties
    cat > "$PROJECT_DIR/gradle.properties" << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF
    # We will let Android Studio creating the wrapper or assume it's there
    # But for CLI builds we need it. Let's try to copy from /opt/android-studio/plugins/android/lib/templates if possible
    # Or just assume the standard `gradle` command is available in path if wrapper is missing
fi

# Ensure executable permissions
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true
chown -R ga:ga "$PROJECT_DIR"

# 6. Pre-build to ensure initial state is valid and download dependencies
echo "Pre-building project to cache dependencies..."
cd "$PROJECT_DIR"
su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew assembleDebug" || {
    echo "WARNING: Initial build failed. Agent will need to fix this or it's an env issue."
    # We don't exit here because sometimes first build fails on envs but IDE fixes it
}

# Record initial checksums of build files for anti-gaming
md5sum "$PROJECT_DIR/build.gradle.kts" > /tmp/initial_build_gradle_checksum.txt
md5sum "$PROJECT_DIR/app/build.gradle.kts" > /tmp/initial_app_build_gradle_checksum.txt

# 7. Open Project
setup_android_studio_project "$PROJECT_DIR" "NoteApp" 180

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="