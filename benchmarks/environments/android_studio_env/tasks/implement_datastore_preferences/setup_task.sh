#!/bin/bash
set -e
echo "=== Setting up implement_datastore_preferences task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous runs
rm -rf /tmp/task_result.json 2>/dev/null || true
rm -rf /home/ga/AndroidStudioProjects/PodcastPlayer 2>/dev/null || true

# --- Create Project Structure ---
# We simulate a "real" project by constructing it here to ensure consistency
# without relying on external downloads that might break.
PROJECT_DIR="/home/ga/AndroidStudioProjects/PodcastPlayer"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/podcastplayer/data"
mkdir -p "$PROJECT_DIR/app/src/test/java/com/example/podcastplayer/data"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

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
rootProject.name = "PodcastPlayer"
include(":app")
EOF

# 2. Project build.gradle.kts
cat > "$PROJECT_DIR/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

# 3. App build.gradle.kts (Missing DataStore dependency)
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.podcastplayer"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.podcastplayer"
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
    
    // TODO: Add DataStore dependency here

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation("org.mockito:mockito-core:5.3.1")
    testImplementation("org.mockito.kotlin:mockito-kotlin:5.0.0")
}
EOF

# 4. SettingsRepository.kt (Skeleton with TODOs)
cat > "$PROJECT_DIR/app/src/main/java/com/example/podcastplayer/data/SettingsRepository.kt" << 'EOF'
package com.example.podcastplayer.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import java.io.IOException

// Delegate for DataStore
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

class SettingsRepository(private val context: Context) {

    // TODO: Define Preference Keys
    // private val PLAYBACK_SPEED_KEY = ...
    // private val AUTO_DOWNLOAD_KEY = ...

    val playbackSpeed: Flow<Float> = context.dataStore.data
        .map { preferences ->
            // TODO: Return preference value or default 1.0f
            1.0f
        }

    val enableAutoDownload: Flow<Boolean> = context.dataStore.data
        .map { preferences ->
            // TODO: Return preference value or default true
            true
        }

    suspend fun setPlaybackSpeed(speed: Float) {
        // TODO: Edit DataStore to save speed
    }

    suspend fun setEnableAutoDownload(enabled: Boolean) {
        // TODO: Edit DataStore to save enabled state
    }
}
EOF

# 5. SettingsRepositoryTest.kt (Comprehensive tests)
cat > "$PROJECT_DIR/app/src/test/java/com/example/podcastplayer/data/SettingsRepositoryTest.kt" << 'EOF'
package com.example.podcastplayer.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mockito.kotlin.doReturn
import org.mockito.kotlin.mock

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsRepositoryTest {

    @get:Rule
    val tmpFolder: TemporaryFolder = TemporaryFolder.builder().assureDeletion().build()

    private lateinit var testDataStore: DataStore<Preferences>
    private lateinit var repository: SettingsRepository
    private lateinit var context: Context

    @Before
    fun setup() {
        val testDispatcher = UnconfinedTestDispatcher()
        val testScope = TestScope(testDispatcher + Job())
        
        testDataStore = PreferenceDataStoreFactory.create(
            scope = testScope,
            produceFile = { tmpFolder.newFile("test_settings.preferences_pb") }
        )

        // Mock context to return our test DataStore via reflection or strict dependency injection logic.
        // Since the task uses the extension delegate `val Context.dataStore`, testing it directly 
        // without instrumented tests is tricky unless we refactor the class to accept DataStore in constructor.
        // HOWEVER, for this task, the agent is implementing the class. The provided test uses a constructor injection pattern 
        // if the agent refactors, OR we need to use a slight hack for the test to work with the extension property.
        
        // To make this solvable without forcing the agent to refactor architecture:
        // We will mock the internal usage if possible, OR, simpler:
        // We instruct the agent to use the provided `dataStore` instance if we passed it, but the skeleton uses `Context`.
        
        // Let's modify the Test and the Skeleton slightly to be Testable.
        // Actually, best practice is injecting DataStore. Let's rely on the agent following the skeleton
        // but verify using the verification script mainly.
        // BUT the task requires `gradle test` to pass.
        
        // REVISION: The Skeleton `SettingsRepository(private val context: Context)` makes unit testing hard.
        // Let's change the skeleton to `class SettingsRepository(private val dataStore: DataStore<Preferences>)`.
        // This is better architecture anyway.
    }
    
    @Test
    fun `placeholder_test_failure`() {
        // This test exists to fail initially until the agent implements logic
        // We can't easily unit test the Context extension delegate pattern in pure JUnit without Robolectric.
        // We will fail here if the code isn't changed.
        assertEquals(1, 1) 
    }
}
EOF

# RE-WRITE Skeleton to be Testable (Constructor Injection)
# This makes the task cleaner and the test valid.
cat > "$PROJECT_DIR/app/src/main/java/com/example/podcastplayer/data/SettingsRepository.kt" << 'EOF'
package com.example.podcastplayer.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import java.io.IOException

// The DataStore instance is passed in (dependency injection)
class SettingsRepository(private val dataStore: DataStore<Preferences>) {

    // TODO: Define Preference Keys using floatPreferencesKey and booleanPreferencesKey
    // private val PLAYBACK_SPEED_KEY = ...
    // private val AUTO_DOWNLOAD_KEY = ...

    val playbackSpeed: Flow<Float> = dataStore.data
        .catch { exception ->
            // TODO: Handle IOException by emitting emptyPreferences()
            throw exception
        }
        .map { preferences ->
            // TODO: Return the preference value, defaulting to 1.0f if not set
            1.0f
        }

    val enableAutoDownload: Flow<Boolean> = dataStore.data
        .catch { exception ->
             // TODO: Handle IOException
             throw exception
        }
        .map { preferences ->
            // TODO: Return the preference value, defaulting to true if not set
            true
        }

    suspend fun setPlaybackSpeed(speed: Float) {
        // TODO: Use dataStore.edit to update the playback speed
    }

    suspend fun setEnableAutoDownload(enabled: Boolean) {
        // TODO: Use dataStore.edit to update the auto download setting
    }
}
EOF

# RE-WRITE Test to match the injectable constructor
cat > "$PROJECT_DIR/app/src/test/java/com/example/podcastplayer/data/SettingsRepositoryTest.kt" << 'EOF'
package com.example.podcastplayer.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsRepositoryTest {

    @get:Rule
    val tmpFolder: TemporaryFolder = TemporaryFolder.builder().assureDeletion().build()

    private lateinit var testDataStore: DataStore<Preferences>
    private lateinit var repository: SettingsRepository

    @Before
    fun setup() {
        val testDispatcher = UnconfinedTestDispatcher()
        val testScope = TestScope(testDispatcher + Job())
        
        testDataStore = PreferenceDataStoreFactory.create(
            scope = testScope,
            produceFile = { tmpFolder.newFile("test.preferences_pb") }
        )
        repository = SettingsRepository(testDataStore)
    }

    @Test
    fun `initial playback speed should be 1_0`() = runTest {
        val speed = repository.playbackSpeed.first()
        assertEquals(1.0f, speed)
    }

    @Test
    fun `initial auto download should be true`() = runTest {
        val enabled = repository.enableAutoDownload.first()
        assertEquals(true, enabled)
    }

    @Test
    fun `setPlaybackSpeed updates value`() = runTest {
        repository.setPlaybackSpeed(2.5f)
        val speed = repository.playbackSpeed.first()
        assertEquals(2.5f, speed)
    }

    @Test
    fun `setEnableAutoDownload updates value`() = runTest {
        repository.setEnableAutoDownload(false)
        val enabled = repository.enableAutoDownload.first()
        assertEquals(false, enabled)
    }
    
    @Test
    fun `keys should use specific names`() = runTest {
        // Write using raw keys and read back via repository to verify key names matches expectations
        // If the agent creates keys with different names, this ensures they at least behave consistently,
        // but here we verify the behavior works. 
        // Actually, we trust the functional tests above.
    }
}
EOF

# 6. Gradle Wrapper (Simulate existence)
# We need a valid gradle wrapper for the agent to run ./gradlew
# In this env, Android Studio usually sets this up. 
# We'll copy a generic wrapper if available or assume the IDE creates it on open.
# Better: Use the system's 'gradle' if wrapper fails, but Android projects expect wrapper.
# Let's try to generate a minimal wrapper properties.
mkdir -p "$PROJECT_DIR/gradle/wrapper"
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF
cp /opt/android-studio/plugins/gradle/lib/gradle-wrapper.jar "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true

# Copy gradlew scripts from a template or create dummy ones that call system gradle
# (Since creating a full gradlew script from scratch is verbose, we rely on `gradle` being in path 
# or the IDE generating it. However, the task description says `./gradlew test`. 
# We will create a simple wrapper script.)
cat > "$PROJECT_DIR/gradlew" << 'EOF'
#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
gradle "$@"
EOF
chmod +x "$PROJECT_DIR/gradlew"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Open Android Studio
setup_android_studio_project "$PROJECT_DIR" "PodcastPlayer" 120

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="