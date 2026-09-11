---
name: unity-build-pipeline
description: >
  Build and ship Unity 6 (6.3 LTS / 6.6 / 6.7 Ready) players: Build Profiles,
  scenes, scripting backend (IL2CPP vs Mono), managed code stripping, Content Directories
  vs AssetBundles (Addressables 4.0+), Build Analysis history, and headless CI builds.
  Use when configuring player builds, switching build targets, shrinking binary size,
  packaging Addressables/Content Directories, or running automated CI/CD pipelines.
---

# Unity Build Pipeline

Configure, script, and automate Unity 6 player builds: Build Profiles, scenes, platform target,
scripting backend, stripping levels, Content Directories / Addressables, and CI/headless builds.
Targets **Unity 6 (6.3 LTS / 6.6 / 6.7 Ready)**.

## When to use

- Use when setting up Build Settings or Build Profiles, choosing a platform and scripting backend
  (Mono vs IL2CPP), reducing build size with managed stripping, scripting repeatable builds
  with `BuildPipeline.BuildPlayer`, configuring Content Directories vs AssetBundles, or wiring a CI build.
- Use when the project has `ProjectSettings/EditorBuildSettings.asset` or a CI build script.

**When *not* to use:** authoring a cloud CI service config end-to-end (GitHub Actions, GitLab CI)
is DevOps; this skill covers the Unity-side build APIs, settings, and content packaging.
Storefront submission → `steam-publish` / `itch-publish`.

## Core workflow

1. **Configure Build Profiles and scenes** (File → Build Profiles, or `EditorBuildSettings.scenes`).
   Ensure all gameplay and UI scenes are registered; scene 0 is the entry point.
2. **Pick the platform target** and active backend (`BuildTarget` / `EditorUserBuildSettings`).
3. **Choose the scripting backend** (Player Settings): **Mono** (fast iteration for desktop/dev) vs
   **IL2CPP** (AOT C++; required for mobile/consoles, superior performance and code protection).
4. **Choose Content Distribution Pipeline:**
   - **Local project content:** use **Content Directories** (Unity 6.6+ / Addressables 4.0+) for
     zero-compression-overhead fast iteration and direct disk mapping.
   - **Remote CDN/Patching content:** use **AssetBundles** via Addressables with LZ4/LZMA compression.
5. **Tune size/perf:** set Managed Stripping Level (Disabled → Low → Medium → High) and protect
   reflection or JSON serialization types with a `link.xml`.
6. **Script the build** with `BuildPipeline.BuildPlayer(BuildPlayerOptions)` and verify the
   returned `BuildReport.summary.result == BuildResult.Succeeded`.
7. **Inspect build metrics** using the **Build Analysis window** and `Library/BuildHistory/` logs.

## Content Management: AssetBundles vs Content Directories

| Feature | Content Directories (Unity 6.6+ / Addressables 4.0+) | Traditional AssetBundles |
| :--- | :--- | :--- |
| **Primary Use Case** | Local content, large PC/Console assets, fast local iteration | Remote CDN delivery, live game patching, DLC |
| **Build Overhead** | Near zero (direct disk layout / containerization) | High (requires serialization and archive compression) |
| **Memory Footprint** | Direct streaming from storage | Archive header overhead + decompressed blocks |
| **Addressables Integration** | Default local group schema | Default remote group schema |

## Patterns

### 1. Scripted build with BuildReport validation

```csharp
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

public static class BuildScript
{
    [MenuItem("Build/Windows x64 Release")]
    public static void BuildWindows()
    {
        var options = new BuildPlayerOptions
        {
            scenes = new[] { "Assets/Scenes/Boot.unity", "Assets/Scenes/MainMenu.unity", "Assets/Scenes/Game.unity" },
            locationPathName = "Builds/Windows/Game.exe",
            target = BuildTarget.StandaloneWindows64,
            options = BuildOptions.None, // Use BuildOptions.Development for profiling builds
        };

        BuildReport report = BuildPipeline.BuildPlayer(options);
        BuildSummary summary = report.summary;

        if (summary.result != BuildResult.Succeeded)
            throw new System.Exception($"Build failed with {summary.totalErrors} errors!");

        Debug.Log($"[Build] Success: {summary.totalSize} bytes in {summary.totalTime.TotalSeconds:F1}s");
    }
}
```

### 2. Headless CI invocation

```bash
# Unity headless execution for CI runners
Unity -batchmode -quit -nographics \
  -projectPath "/workspace/MyProject" \
  -executeMethod BuildScript.BuildWindows \
  -logFile -
```

### 3. Managed code stripping protection (`link.xml`)

```xml
<!-- Assets/link.xml — prevents the linker from stripping reflection/data models -->
<linker>
  <assembly fullname="MyGameRuntime" preserve="all"/>
  <assembly fullname="UnityEngine.CoreModule">
    <type fullname="UnityEngine.GameObject" preserve="all"/>
  </assembly>
</linker>
```

## Pitfalls

- **Scene missing in standalone player** — scene was created but not registered in Build Settings
  or the active Build Profile.
- **IL2CPP toolchain missing on clean runner** — IL2CPP requires the platform C++ compiler (Visual Studio C++
  build tools, Android NDK, Xcode toolchain). Mono runs without C++ compiler toolchains.
- **`MissingMethodException` after enabling High Stripping** — Managed Stripping removed classes
  invoked via reflection or serialization. Add an entry to `link.xml`.
- **Addressables / Content Directories missing from build output** — Content groups must be built
  (`AddressableAssetSettings.BuildPlayerContent()`) prior to launching the player build.
- **Ignoring `BuildReport.summary.result`** — `BuildPlayer` can complete without throwing an unhandled C#
  exception while still failing compilation or packaging. Always check `summary.result == BuildResult.Succeeded`.

## References

- For complete multi-platform CI scripts, argument parsing, version stamping, and automated
  Addressables / Content Directories builds, read `references/ci-build-script.md`.
- Primary docs: Unity Manual "Build Profiles", "Managed code stripping", and "Addressable Asset System".

## Related skills

- `steam-publish` / `itch-publish` — distributing the exported player packages.
- `unity-csharp-scripting` — script compilation, assembly definitions, and editor scripting.
