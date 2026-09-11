# CI / headless build script (Unity 6.3 LTS / 6.6 / 6.7)

Depth for `unity-build-pipeline`: a reusable editor build script that handles command-line
arguments, target platform switching, version stamping, Content Directories / Addressables
builds, and exit codes for CI runners.

## Multi-Platform CI Build Script

```csharp
using System;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.AddressableAssets.Settings;
using UnityEngine;

public static class CIBuild
{
    // Invoke with: Unity -batchmode -quit -nographics -executeMethod CIBuild.Run -buildTarget Win64 -out Builds/Game.exe -version 1.0.4
    public static void Run()
    {
        string[] args = Environment.GetCommandLineArgs();

        string targetArg = ArgValue(args, "-buildTarget", "Win64");
        string outPath   = ArgValue(args, "-out", "Builds/Game.exe");
        string version   = ArgValue(args, "-version", PlayerSettings.bundleVersion);
        bool   dev       = args.Contains("-dev");
        bool   buildAddr = args.Contains("-buildContent");

        BuildTarget target = targetArg switch
        {
            "Win64"   => BuildTarget.StandaloneWindows64,
            "Mac"     => BuildTarget.StandaloneOSX,
            "Linux"   => BuildTarget.StandaloneLinux64,
            "Android" => BuildTarget.Android,
            "iOS"     => BuildTarget.iOS,
            _ => throw new ArgumentException($"Unsupported build target: {targetArg}")
        };

        // Switch active build target if necessary
        BuildTargetGroup group = BuildPipeline.GetBuildTargetGroup(target);
        if (EditorUserBuildSettings.activeBuildTarget != target)
        {
            EditorUserBuildSettings.SwitchActiveBuildTarget(group, target);
        }

        PlayerSettings.bundleVersion = version;

        // Build Addressables / Content Directories if requested
        if (buildAddr)
        {
            Debug.Log("[CIBuild] Building Addressables / Content Directories...");
            AddressableAssetSettings.BuildPlayerContent(out var addrResult);
            if (!string.IsNullOrEmpty(addrResult.Error))
            {
                Debug.LogError($"[CIBuild] Addressables content build failed: {addrResult.Error}");
                EditorApplication.Exit(1);
                return;
            }
        }

        var options = new BuildPlayerOptions
        {
            scenes = EnabledScenes(),
            locationPathName = outPath,
            target = target,
            options = dev ? (BuildOptions.Development | BuildOptions.AllowDebugging) : BuildOptions.None,
        };

        BuildReport report = BuildPipeline.BuildPlayer(options);
        BuildSummary s = report.summary;

        if (s.result == BuildResult.Succeeded)
        {
            Debug.Log($"[CIBuild] SUCCESS: Version {version} -> {outPath} ({s.totalSize} bytes in {s.totalTime.TotalSeconds:F1}s)");
            EditorApplication.Exit(0);
        }
        else
        {
            Debug.LogError($"[CIBuild] FAILED: {s.totalErrors} errors, status={s.result}");
            EditorApplication.Exit(1);
        }
    }

    private static string[] EnabledScenes() =>
        EditorBuildSettings.scenes.Where(sc => sc.enabled).Select(sc => sc.path).ToArray();

    private static string ArgValue(string[] args, string key, string fallback)
    {
        int i = Array.IndexOf(args, key);
        return (i >= 0 && i + 1 < args.Length) ? args[i + 1] : fallback;
    }
}
```

## CI Shell Runner Example

```bash
#!/usr/bin/env bash
set -eo pipefail

echo "==> Starting Unity automated build..."
Unity -batchmode -quit -nographics \
  -projectPath "$CI_PROJECT_DIR" \
  -executeMethod CIBuild.Run \
  -buildTarget Win64 \
  -out "Builds/Win64/Game.exe" \
  -version "1.0.$BUILD_NUMBER" \
  -buildContent \
  -logFile -

echo "==> Build finished successfully."
```
