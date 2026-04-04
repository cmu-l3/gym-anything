#!/bin/bash
set -e
echo "=== Setting up add_content_provider task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Project directory
PROJECT_DIR="/home/ga/AndroidStudioProjects/NotesApp"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/notesapp"

# 1. Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Create Project Structure
mkdir -p "$PACKAGE_DIR/data"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

# 3. Create build.gradle.kts (Project level)
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    id("com.google.devtools.ksp") version "1.9.22" apply false
}
EOF

# 4. Create settings.gradle.kts
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
rootProject.name = "NotesApp"
include(":app")
EOF

# 5. Create app/build.gradle.kts
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.example.notesapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.notesapp"
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
    
    // Room
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")
}
EOF

# 6. Create Entity (Note.kt)
cat > "$PACKAGE_DIR/data/Note.kt" << 'EOF'
package com.example.notesapp.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "notes")
data class Note(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val title: String,
    val content: String,
    val timestamp: Long
)
EOF

# 7. Create DAO (NoteDao.kt)
cat > "$PACKAGE_DIR/data/NoteDao.kt" << 'EOF'
package com.example.notesapp.data

import android.database.Cursor
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import androidx.room.Delete

@Dao
interface NoteDao {
    @Query("SELECT * FROM notes")
    fun getAllNotes(): Cursor

    @Query("SELECT * FROM notes WHERE id = :id")
    fun getNoteById(id: Long): Cursor

    @Insert
    fun insert(note: Note): Long

    @Delete
    fun delete(note: Note): Int
    
    @Query("DELETE FROM notes WHERE id = :id")
    fun deleteById(id: Long): Int

    @Update
    fun update(note: Note): Int
}
EOF

# 8. Create Database (NoteDatabase.kt)
cat > "$PACKAGE_DIR/data/NoteDatabase.kt" << 'EOF'
package com.example.notesapp.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [Note::class], version = 1, exportSchema = false)
abstract class NoteDatabase : RoomDatabase() {
    abstract fun noteDao(): NoteDao

    companion object {
        @Volatile
        private var INSTANCE: NoteDatabase? = null

        fun getDatabase(context: Context): NoteDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    NoteDatabase::class.java,
                    "note_database"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
EOF

# 9. Create MainActivity.kt (Stub)
cat > "$PACKAGE_DIR/MainActivity.kt" << 'EOF'
package com.example.notesapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
EOF

# 10. Create AndroidManifest.xml
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
        android:theme="@style/Theme.NotesApp"
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

# 11. Create Layout and Resources
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Notes App" />
</LinearLayout>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">NotesApp</string>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.NotesApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">@color/purple_500</item>
        <item name="colorPrimaryVariant">@color/purple_700</item>
        <item name="colorOnPrimary">@color/white</item>
    </style>
    <color name="purple_500">#FF6200EE</color>
    <color name="purple_700">#FF3700B3</color>
    <color name="white">#FFFFFFFF</color>
</resources>
EOF

cat > "$PROJECT_DIR/app/src/main/res/xml/data_extraction_rules.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <include domain="root" />
    </cloud-backup>
    <device-transfer>
        <include domain="root" />
    </device-transfer>
</data-extraction-rules>
EOF

cat > "$PROJECT_DIR/app/src/main/res/xml/backup_rules.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <include domain="sharedpref" path="."/>
    <include domain="database" path="."/>
</full-backup-content>
EOF

# 12. Setup Gradle Wrapper
cp -r /workspace/data/gradle-wrapper/* "$PROJECT_DIR/gradle/wrapper/" 2>/dev/null || true
cp /workspace/data/gradlew "$PROJECT_DIR/" 2>/dev/null || true
chmod +x "$PROJECT_DIR/gradlew"

# 13. Fix ownership
chown -R ga:ga "$PROJECT_DIR"

# 14. Initial Build (to warm cache and ensure base project is valid)
echo "Running initial build to warm cache..."
cd "$PROJECT_DIR"
# We run as ga to populate ga's gradle cache
su - ga -c "cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon"

# 15. Open in Android Studio
setup_android_studio_project "$PROJECT_DIR" "NotesApp" 180

# 16. Record start time and initial state
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="