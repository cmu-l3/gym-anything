#!/bin/bash
set -e

echo "=== Setting up Configure Product Flavors task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---- Environment variables ----
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_HOME=/opt/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH

PROJECT_DIR="/home/ga/AndroidStudioProjects/TodoApp"

# ---- Clean up any previous run ----
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR"
rm -f /tmp/task_result.json 2>/dev/null || true

# ---- Determine bundled Gradle version ----
BUNDLED_GRADLE=$(ls -d /opt/android-studio/gradle/gradle-* 2>/dev/null | sort -V | tail -1)
echo "Bundled Gradle: $BUNDLED_GRADLE"

# If no bundled Gradle found, download one
if [ -z "$BUNDLED_GRADLE" ] || [ ! -f "$BUNDLED_GRADLE/bin/gradle" ]; then
    echo "No bundled Gradle found, downloading Gradle 8.7..."
    wget -q "https://services.gradle.org/distributions/gradle-8.7-bin.zip" -O /tmp/gradle-dist.zip
    unzip -q /tmp/gradle-dist.zip -d /tmp/
    BUNDLED_GRADLE="/tmp/gradle-8.7"
    rm -f /tmp/gradle-dist.zip
fi

GRADLE_BIN="$BUNDLED_GRADLE/bin/gradle"
GRADLE_VER=$($GRADLE_BIN --version 2>/dev/null | grep "^Gradle " | awk '{print $2}' || echo "8.7")
echo "Using Gradle version: $GRADLE_VER"

# ---- Create project structure ----
echo "Creating TodoApp project structure..."

# -- settings.gradle.kts --
cat > "$PROJECT_DIR/settings.gradle.kts" << 'SETTINGS_EOF'
pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
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

rootProject.name = "TodoApp"
include(":app")
SETTINGS_EOF

# -- Root build.gradle.kts --
cat > "$PROJECT_DIR/build.gradle.kts" << 'ROOT_BUILD_EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
ROOT_BUILD_EOF

# -- gradle.properties --
cat > "$PROJECT_DIR/gradle.properties" << 'GRADLE_PROPS_EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
GRADLE_PROPS_EOF

# -- local.properties --
cat > "$PROJECT_DIR/local.properties" << LOCAL_PROPS_EOF
sdk.dir=/opt/android-sdk
LOCAL_PROPS_EOF

# -- Generate Gradle wrapper --
echo "Generating Gradle wrapper..."
cd "$PROJECT_DIR"
$GRADLE_BIN wrapper --gradle-version "$GRADLE_VER" --distribution-type bin 2>/dev/null || {
    echo "Wrapper generation failed, creating manually..."
    mkdir -p gradle/wrapper
    
    cat > gradle/wrapper/gradle-wrapper.properties << WRAPPER_PROPS_EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-${GRADLE_VER}-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
WRAPPER_PROPS_EOF

    # Copy wrapper jar from bundled Gradle
    if [ -f "$BUNDLED_GRADLE/lib/gradle-wrapper.jar" ]; then
        cp "$BUNDLED_GRADLE/lib/gradle-wrapper.jar" gradle/wrapper/gradle-wrapper.jar
    elif [ -f "$BUNDLED_GRADLE/lib/plugins/gradle-wrapper"*.jar ]; then
        cp $BUNDLED_GRADLE/lib/plugins/gradle-wrapper*.jar gradle/wrapper/gradle-wrapper.jar
    fi
    
    # Create gradlew script
    cat > gradlew << 'GRADLEW_EOF'
#!/bin/sh
exec java -jar "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" "$@"
GRADLEW_EOF
    chmod +x gradlew
}

# Ensure gradlew is executable
chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null || true

# -- App module build.gradle.kts (WITHOUT flavors - this is what the agent must add) --
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/build.gradle.kts" << 'APP_BUILD_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.todoapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.todoapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
APP_BUILD_EOF

# -- ProGuard rules --
cat > "$PROJECT_DIR/app/proguard-rules.pro" << 'PROGUARD_EOF'
# Add project specific ProGuard rules here.
PROGUARD_EOF

# -- AndroidManifest.xml --
mkdir -p "$PROJECT_DIR/app/src/main"
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'MANIFEST_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.TodoApp">
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
MANIFEST_EOF

# -- Main Activity --
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/todoapp"
cat > "$PROJECT_DIR/app/src/main/java/com/example/todoapp/MainActivity.kt" << 'MAIN_EOF'
package com.example.todoapp

import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ListView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private val todoItems = mutableListOf<String>()
    private lateinit var adapter: ArrayAdapter<String>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val editText = findViewById<EditText>(R.id.editTextTask)
        val addButton = findViewById<Button>(R.id.buttonAdd)
        val listView = findViewById<ListView>(R.id.listViewTodos)

        adapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, todoItems)
        listView.adapter = adapter

        addButton.setOnClickListener {
            val task = editText.text.toString().trim()
            if (task.isNotEmpty()) {
                todoItems.add(task)
                adapter.notifyDataSetChanged()
                editText.text.clear()
            }
        }

        listView.setOnItemLongClickListener { _, _, position, _ ->
            todoItems.removeAt(position)
            adapter.notifyDataSetChanged()
            true
        }
    }
}
MAIN_EOF

# -- Layout --
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'LAYOUT_EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">

        <EditText
            android:id="@+id/editTextTask"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:hint="@string/hint_add_task"
            android:inputType="text" />

        <Button
            android:id="@+id/buttonAdd"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="@string/button_add" />
    </LinearLayout>

    <ListView
        android:id="@+id/listViewTodos"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginTop="8dp" />

</LinearLayout>
LAYOUT_EOF

# -- String resources (default/main) --
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'STRINGS_EOF'
<resources>
    <string name="app_name">TodoApp</string>
    <string name="hint_add_task">Enter a task…</string>
    <string name="button_add">Add</string>
</resources>
STRINGS_EOF

# -- Theme --
cat > "$PROJECT_DIR/app/src/main/res/values/themes.xml" << 'THEME_EOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.TodoApp" parent="Theme.MaterialComponents.DayNight.DarkActionBar">
        <item name="colorPrimary">#6200EE</item>
        <item name="colorPrimaryVariant">#3700B3</item>
        <item name="colorOnPrimary">#FFFFFF</item>
        <item name="colorSecondary">#03DAC5</item>
        <item name="colorSecondaryVariant">#018786</item>
        <item name="colorOnSecondary">#000000</item>
    </style>
</resources>
THEME_EOF

# -- Minimal mipmap launcher icon (1x1 pixel PNG) --
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-hdpi"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > "$PROJECT_DIR/app/src/main/res/mipmap-hdpi/ic_launcher.png"

# ---- Save initial state of build.gradle.kts for comparison ----
cp "$PROJECT_DIR/app/build.gradle.kts" /tmp/initial_build_gradle.kts

# ---- Set ownership ----
chown -R ga:ga "$PROJECT_DIR"

# ---- Open project in Android Studio ----
echo "Opening TodoApp in Android Studio..."
setup_android_studio_project "$PROJECT_DIR" "TodoApp" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="