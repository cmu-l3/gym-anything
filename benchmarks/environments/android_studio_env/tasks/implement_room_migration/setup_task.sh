#!/bin/bash
set -e
echo "=== Setting up implement_room_migration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Project configuration
PROJECT_NAME="TaskMaster"
PROJECT_DIR="/home/ga/AndroidStudioProjects/$PROJECT_NAME"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/taskmaster"

# Clean previous attempts
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# ------------------------------------------------------------------
# 1. Create Project Structure (Simulating a pre-existing app)
# ------------------------------------------------------------------
echo "Creating project files..."

# Root build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
// Top-level build file
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.jetbrains.kotlin.android) apply false
    alias(libs.plugins.ksp) apply false
}
EOF

# settings.gradle.kts
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
rootProject.name = "TaskMaster"
include(":app")
EOF

# App module directory
mkdir -p "$PROJECT_DIR/app"

# App build.gradle.kts (Correct dependencies for Room)
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.jetbrains.kotlin.android)
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.example.taskmaster"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.taskmaster"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        
        // Export schemas for migration testing
        javaCompileOptions {
            annotationProcessorOptions {
                arguments["room.schemaLocation"] = "$projectDir/schemas"
            }
        }
    }
    
    sourceSets {
        getByName("androidTest") {
            assets.srcDirs(files("$projectDir/schemas"))
        }
        getByName("test") {
            resources.srcDirs(files("$projectDir/schemas"))
        }
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
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    
    val room_version = "2.6.1"
    implementation("androidx.room:room-runtime:$room_version")
    implementation("androidx.room:room-ktx:$room_version")
    ksp("androidx.room:room-compiler:$room_version")
    testImplementation("androidx.room:room-testing:$room_version")
    
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
}
EOF

# libs.versions.toml
mkdir -p "$PROJECT_DIR/gradle"
cat > "$PROJECT_DIR/gradle/libs.versions.toml" << 'EOF'
[versions]
agp = "8.2.0"
kotlin = "1.9.0"
coreKtx = "1.10.1"
junit = "4.13.2"
junitVersion = "1.1.5"
espressoCore = "3.5.1"
appcompat = "1.6.1"
material = "1.10.0"
ksp = "1.9.0-1.0.13"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "coreKtx" }
junit = { group = "junit", name = "junit", version.ref = "junit" }
androidx-junit = { group = "androidx.test.ext", name = "junit", version.ref = "junitVersion" }
androidx-espresso-core = { group = "androidx.test.espresso", name = "espresso-core", version.ref = "espressoCore" }
androidx-appcompat = { group = "androidx.appcompat", name = "appcompat", version.ref = "appcompat" }
material = { group = "com.google.android.material", name = "material", version.ref = "material" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
jetbrains-kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
ksp = { id = "com.google.devtools.ksp", version.ref = "ksp" }
EOF

# Create source directories
mkdir -p "$PACKAGE_DIR/data"
mkdir -p "$PROJECT_DIR/app/src/test/java/com/example/taskmaster/data"

# ------------------------------------------------------------------
# 2. Write Application Code (State V1)
# ------------------------------------------------------------------

# Task.kt (Entity V1 - No priority)
cat > "$PACKAGE_DIR/data/Task.kt" << 'EOF'
package com.example.taskmaster.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "tasks")
data class Task(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val title: String,
    val isCompleted: Boolean = false
)
EOF

# TaskDao.kt
cat > "$PACKAGE_DIR/data/TaskDao.kt" << 'EOF'
package com.example.taskmaster.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface TaskDao {
    @Query("SELECT * FROM tasks")
    fun getAll(): List<Task>

    @Insert
    fun insert(task: Task)
}
EOF

# AppDatabase.kt (Version 1)
cat > "$PACKAGE_DIR/data/AppDatabase.kt" << 'EOF'
package com.example.taskmaster.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [Task::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun taskDao(): TaskDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "task_master_db"
                )
                .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
EOF

# ------------------------------------------------------------------
# 3. Create Migration Test
# ------------------------------------------------------------------
# This test is provided to the agent to verify their work.
# It uses Room's MigrationTestHelper.

cat > "$PROJECT_DIR/app/src/test/java/com/example/taskmaster/data/MigrationTest.kt" << 'EOF'
package com.example.taskmaster.data

import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import java.io.IOException

@RunWith(JUnit4::class)
class MigrationTest {

    private val TEST_DB = "migration-test"

    @get:Rule
    val helper: MigrationTestHelper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java.canonicalName,
        FrameworkSQLiteOpenHelperFactory()
    )

    @Test
    @Throws(IOException::class)
    fun migrate1To2() {
        var db = helper.createDatabase(TEST_DB, 1).apply {
            // Insert version 1 data
            execSQL("INSERT INTO tasks (id, title, isCompleted) VALUES (1, 'Test Task', 0)")
            close()
        }

        // Run migration
        db = helper.runMigrationsAndValidate(TEST_DB, 2, true, MIGRATION_1_2)

        // Verify data validity
        val cursor = db.query("SELECT * FROM tasks WHERE id = 1")
        cursor.moveToFirst()
        
        // Check if priority column exists and has default value
        val priorityIndex = cursor.getColumnIndex("priority")
        assert(priorityIndex != -1) { "Column 'priority' not found" }
        
        val priority = cursor.getInt(priorityIndex)
        assert(priority == 0) { "Default priority should be 0, found $priority" }
    }
}
EOF

# ------------------------------------------------------------------
# 4. Generate Initial Schema (Crucial for MigrationTestHelper)
# ------------------------------------------------------------------
echo "Generating initial schema..."
mkdir -p "$PROJECT_DIR/app/schemas/com.example.taskmaster.data.AppDatabase"
cat > "$PROJECT_DIR/app/schemas/com.example.taskmaster.data.AppDatabase/1.json" << 'EOF'
{
  "formatVersion": 1,
  "database": {
    "version": 1,
    "identityHash": "identity_hash_placeholder",
    "entities": [
      {
        "tableName": "tasks",
        "createSql": "CREATE TABLE IF NOT EXISTS `${TABLE_NAME}` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `title` TEXT NOT NULL, `isCompleted` INTEGER NOT NULL)",
        "fields": [
          {
            "fieldPath": "id",
            "columnName": "id",
            "affinity": "INTEGER",
            "notNull": true
          },
          {
            "fieldPath": "title",
            "columnName": "title",
            "affinity": "TEXT",
            "notNull": true
          },
          {
            "fieldPath": "isCompleted",
            "columnName": "isCompleted",
            "affinity": "INTEGER",
            "notNull": true
          }
        ],
        "primaryKey": {
          "columnNames": [
            "id"
          ],
          "autoGenerate": true
        },
        "indices": [],
        "foreignKeys": []
      }
    ],
    "views": [],
    "setupQueries": [
      "CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)",
      "INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, 'identity_hash_placeholder')"
    ]
  }
}
EOF

# ------------------------------------------------------------------
# 5. Environment Setup
# ------------------------------------------------------------------
# Ensure gradlew executable
cp /workspace/scripts/gradlew "$PROJECT_DIR/" 2>/dev/null || true
if [ ! -f "$PROJECT_DIR/gradlew" ]; then
    # Fallback if global gradlew missing
    echo "Creating dummy gradlew for structure (actual build uses IDE or system gradle if needed)"
    touch "$PROJECT_DIR/gradlew"
fi
chmod +x "$PROJECT_DIR/gradlew"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

# ------------------------------------------------------------------
# 6. Launch IDE
# ------------------------------------------------------------------
echo "Opening project in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "TaskMaster" 180

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="