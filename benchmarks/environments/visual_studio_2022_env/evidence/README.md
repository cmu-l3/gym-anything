# Visual Studio 2022 Community Environment - Evidence Documentation

## Environment Overview

- **Environment ID**: `visual_studio_2022_env@0.1`
- **Base**: Windows 11 (dockur/windows QEMU VM)
- **Application**: Visual Studio 2022 Community (17.14.36930.0)
- **Installation**: VS bootstrapper from https://aka.ms/vs/17/release/vs_Community.exe (~4.4 MB bootstrapper, ~6-8 GB workload download)
- **Workload**: Microsoft.VisualStudio.Workload.ManagedDesktop (C#/.NET desktop development)
- **.NET SDK**: 9.0.311
- **Login/Activation**: 62-day Enterprise Evaluation grace period, no sign-in required
- **Resolution**: 1280x720

## Installation

VS 2022 installs via the bootstrapper with `--passive --norestart --wait`. The ManagedDesktop workload includes .NET SDK, C# compiler, IntelliSense, NuGet, and console/WinForms/WPF templates.

**Installation path**: `C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe`
**Version**: 17.14.36930.0

### Install Script Log (pre_start hook)

```
=== Installing Visual Studio 2022 Community ===
Downloading VS 2022 Community bootstrapper...
Bootstrapper downloaded: 4357 KB
Starting VS 2022 installation (this takes 15-30 minutes)...
  Workload: Microsoft.VisualStudio.Workload.ManagedDesktop
VS installer exited with code: 0
Verifying installation...
Visual Studio 2022 installed successfully.
  Path: C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe
  Version: 17.14.36930.0
  Size: 1066056 bytes

Checking .NET SDK...
.NET SDKs installed:
  9.0.311 [C:\Program Files\dotnet\sdk]
=== VS 2022 installation complete ===
```

### Setup Script Log (post_start hook)

```
=== Setting up Visual Studio 2022 environment ===
Configuring registry keys...
Registry and environment configured.
Disabling OneDrive...
OneDrive uninstalled.

=== Creating C# projects ===
Creating InventoryManager console app...
InventoryManager project created.
InventoryManager Program.cs written.
Building InventoryManager to warm NuGet cache...
  InventoryManager -> C:\Users\Docker\source\repos\InventoryManager\bin\Debug\net9.0\InventoryManager.dll
  Build succeeded. 0 Warning(s) 0 Error(s)
InventoryManager build complete.
Creating InventoryManager_broken console app...
InventoryManager_broken Program.cs written (with 2 injected errors).

=== Warming up Visual Studio 2022 ===
VS executable: C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe
Launching VS for first-run warm-up...
Dismissing first-run dialogs...
Dialog dismissal attempted.
VS warm-up complete.

Projects created in C:\Users\Docker\source\repos :
  - InventoryManager
  - InventoryManager_broken
=== Visual Studio 2022 environment setup complete ===
```

## Task Start States Verified

### 1. create_console_project (Easy)
- **Screenshot**: `create_console_project_start_state.png`
- **VS state**: Start Window (no solution open)
- **Title**: "Visual Studio 2022"
- **Options visible**: Clone a repository, Open a project or solution, Open a local folder, Create a new project, Continue without code
- **Status**: VERIFIED - Start Window loads correctly, "Create a new project" option visible

### 2. build_existing_solution (Easy)
- **Screenshot**: `build_existing_solution_start_state.png`
- **VS state**: InventoryManager.sln open
- **Title bar**: "InventoryManager"
- **Solution Explorer**: Shows "Solution 'InventoryManager' (1 of 1 project)"
- **Status bar**: "Restored C:\Users\Docker\source\repos\InventoryManager\InventoryManager.csproj"
- **Build menu**: Available with Build Solution option
- **Status**: VERIFIED - solution loads, Build menu accessible

### 3. fix_build_error (Medium)
- **Screenshot**: `fix_build_error_start_state.png`
- **VS state**: InventoryManager_broken.sln open
- **Title bar**: "InventoryManager_broken"
- **Solution Explorer**: Shows "Solution 'InventoryManager_broken' (1 of 1 project)"
- **Status bar**: "Restoring NuGet packages..."
- **Status**: VERIFIED - broken solution loads, ready for build attempt

### 4. add_nuget_package (Medium)
- **Screenshot**: `add_nuget_package_start_state.png`
- **VS state**: InventoryManager.sln open
- **Title bar**: "InventoryManager"
- **Solution Explorer**: Shows project tree
- **Status**: VERIFIED - solution loads, right-click context menu available for NuGet

### 5. create_class_file (Medium)
- **Screenshot**: `create_class_file_start_state.png`
- **VS state**: InventoryManager.sln open
- **Title bar**: "InventoryManager"
- **Solution Explorer**: Shows project tree
- **Status**: VERIFIED - solution loads, right-click context menu available for Add > Class

## Task Completability Verified

### build_existing_solution - Interactive Completion Test
- **Screenshot**: `build_existing_solution_completed.png`
- **Action performed**: Pressed Ctrl+Shift+B to build solution
- **Result**: Build succeeded in 5.855 seconds
- **Output window**: "Build: 1 succeeded, 0 failed, 0 up-to-date, 0 skipped"
- **DLL output**: `C:\Users\Docker\source\repos\InventoryManager\bin\Debug\net9.0\InventoryManager.dll`
- **Status bar**: "Build succeeded"
- **Status**: COMPLETABLE - Ctrl+Shift+B builds successfully with 0 errors

## First-Run Dialog Sequence

On first launch after install (1280x720 coordinates):

| Order | Dialog | Dismissal | Coordinates |
|-------|--------|-----------|-------------|
| 1 | "Sign in to Visual Studio" | Click "Skip and add accounts later" | (930, 442) |
| 2 | "Personalize your Visual Studio experience" | Click "Start Visual Studio" | (930, 487) |
| 3 | "Are you sure you want to exit?" (if Escape pressed) | Click "No" | (755, 418) |

After first-run completion, subsequent launches go directly to Start Window or solution.

## Technical Notes

- **Non-ASCII characters in PS1 files**: PowerShell on Windows cannot parse em dashes and other non-ASCII characters in script files transferred via SCP. Use ASCII-only characters in all .ps1 scripts.
- **GitHub Copilot Chat**: VS 2022 shows a Copilot Chat panel on first solution open. It does not block functionality but occupies the right panel area. Solution Explorer tab is also available.
- **Enterprise Evaluation**: VS 2022 Community shows "Enterprise Evaluation, license valid for 62 days" on first launch. This is sufficient for ephemeral VMs.
- **schtasks /IT pattern**: Required to launch GUI apps from SSH Session 0
- **Batch file wrapper**: Required because devenv.exe path contains spaces
- **Solution files**: dotnet new console does not create .sln files. The setup scripts create them with `dotnet new sln` + `dotnet sln add`.
- **.NET SDK 9.0**: The ManagedDesktop workload installs .NET SDK 9.0.311. Projects target net9.0 by default.

## VM Details (Testing Session)

- **SSH Port**: 2308
- **VNC Port**: 5979
- **PyAutoGUI TCP Port**: 5742 (host) -> 5555 (guest)
- **User**: Docker / GymAnything123!
- **Windows version**: Windows 11 (NT 10.0.26200.0)
- **VS version**: 17.14.36930.0
- **devenv.exe size**: 1,066,056 bytes
