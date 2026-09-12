---
name: unity-cli
description: >
  Execute Unity 6 automation and command-line workflows: batchmode headless compilation,
  Unity Test Framework (UTF) CLI runs, Unity Hub CLI management, UPM/OpenUPM package
  operations, and -executeMethod invocation. Use when running headless builds, validating
  C# compilation via terminal, running tests from CLI, or automating Unity in CI/CD.
---

# Unity CLI & Headless Automation (Unity 6 / Hub CLI)

Drive Unity from a terminal with deterministic, reproducible commands: locate the editor binary,
compile and validate C# without opening the Editor, run EditMode/PlayMode tests, invoke static
methods in batchmode, and manage packages. Targets **Unity 6 (6.3 LTS / 6.6 / 6.7 Ready)**.

## When to use

- Verifying that a project's C# compiles **without opening the Editor**.
- Running Unity Test Framework suites from the terminal and parsing the XML result file.
- Automating Unity inside CI/CD runners (headless, no GPU, license activated from secrets).
- Managing installed editors, modules, and licenses through **Unity Hub CLI**.
- Adding/removing packages via **UPM / OpenUPM** or by editing `Packages/manifest.json`.

**When *not* to use:**

- Configuring build settings, Build Profiles, or `BuildPipeline` C# code → `unity-build-pipeline`.
- Writing the C# test logic, assemblies, or gameplay scripts themselves → `unity-csharp-scripting`.

## Core workflow

1. **Detect the Unity binary.** Prefer an explicit `UNITY_PATH`; otherwise resolve the editor
   through Unity Hub (`unityhub --headless editors --installed`) or the default install roots
   (`/Applications/Unity/Hub/Editor/<ver>/Unity.app/Contents/MacOS/Unity`,
   `C:\Program Files\Unity\Hub\Editor\<ver>\Editor\Unity.exe`,
   `~/Unity/Hub/Editor/<ver>/Editor/Unity`).
2. **Verify compilation** with a batchmode run that quits immediately and streams the log to
   stdout; treat a non-zero exit code or any `error CS` line as failure.
3. **Run tests** for `EditMode` and/or `PlayMode`, exporting NUnit XML, then inspect the
   `<test-run result="...">` attribute rather than trusting console output alone.
4. **Automate anything else** with `-executeMethod` against a static, exception-throwing method
   so failures surface as a non-zero exit code.

Use the bundled helpers instead of retyping flags:

- `scripts/validate-compile.sh` — headless C# compilation check with log capture.
- `scripts/run-tests.sh` — EditMode/PlayMode run with XML report export.

## Patterns

### 1. Unity Hub CLI — editors, modules, licenses

```bash
# List installed editors (path + version), machine-readable enough for scripting
unityhub --headless editors --installed

# Install an editor version with extra platform modules
unityhub --headless install --version 6000.3.0f1 --module linux-il2cpp android --childModules

# Inspect modules already installed for a version
unityhub --headless im --version 6000.3.0f1
```

On macOS the binary lives at `/Applications/Unity Hub.app/Contents/MacOS/Unity Hub`; on Linux
it is the AppImage. Always pass `--headless` before the subcommand or the GUI is launched.

### 2. Headless compilation check

```bash
Unity -batchmode -quit -nographics \
  -projectPath "$PWD" \
  -logFile - \
  -buildTarget StandaloneLinux64 | tee /tmp/unity-compile.log

# Compilation errors are reported in-log even when the exit code is 0 on some versions:
grep -E "error CS[0-9]+" /tmp/unity-compile.log && exit 1
```

`-quit` is mandatory: without it the Editor stays resident forever in CI. `-logFile -` streams to
stdout; `-nographics` avoids requiring a GPU/display.

### 3. Test Runner CLI (UTF)

```bash
Unity -batchmode -runTests -nographics \
  -projectPath "$PWD" \
  -testPlatform EditMode \
  -testResults "$PWD/artifacts/editmode-results.xml" \
  -logFile - \
  -testCategory "!Performance"      # optional filters: -testFilter, -assemblyNames
```

Do **not** pass `-quit` with `-runTests` — Unity exits on its own and `-quit` can terminate the
run before results are written. Exit code `0` = all passed, `2` = test failures, `3` = run failure.

### 4. Batchmode method execution

```bash
Unity -batchmode -quit -nographics \
  -projectPath "$PWD" \
  -executeMethod CI.BuildEntry.PerformBuild \
  -logFile - \
  -- --customArg value        # read back with System.Environment.GetCommandLineArgs()
```

The target must be a `public static` method with no arguments on a class inside an **Editor**
assembly. Call `EditorApplication.Exit(1)` (or throw) on failure so the shell sees it.

### 5. Package operations (UPM / OpenUPM)

```bash
# OpenUPM CLI: adds the scoped registry entry and the dependency to Packages/manifest.json
openupm add com.cysharp.unitask
openupm remove com.cysharp.unitask
openupm ls

# Pure UPM: edit the manifest deterministically, then let Unity resolve on next launch
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("Packages/manifest.json")
m = json.loads(p.read_text())
m["dependencies"]["com.unity.test-framework"] = "1.4.5"
p.write_text(json.dumps(m, indent=2) + "\n")
PY
```

Resolution happens on the next Editor launch; a `-quit -batchmode` run is the cheapest way to
force it and surface resolution errors in `Packages/packages-lock.json`.

## Pitfalls

- **Unity never exits in CI** — `-quit` missing on non-test runs, or a modal dialog was triggered
  (`-nographics -batchmode` avoids most of them).
- **No output to diagnose a failure** — the default log path is used instead of `-logFile -`;
  in CI always stream to stdout and archive the log file.
- **`RenderTexture` / GPU errors on a headless runner** — missing `-nographics`, or the test
  genuinely needs a display; use a software GL driver or mark those tests as excluded.
- **License not activated** — headless Unity fails with "No valid Unity Editor license found".
  Activate with `-serial`/`-username`/`-password` or `-manualLicenseFile`, and always run
  `-returnlicense` on teardown for seat-based licenses.
- **Two Unity processes on one project** — the second aborts on the `Temp/UnityLockfile`.
  Serialize CLI jobs per project path.
- **Trusting exit code alone for tests** — parse the XML `result` attribute; a crashed run can
  leave a stale or missing report.
- **`-executeMethod` silently "succeeds"** — an unhandled exception is only logged unless you
  exit explicitly with a non-zero code.

## References

- `references/cli-arguments-matrix.md` — full argument matrix, exit codes, license activation,
  and CI/CD recipes (GitHub Actions, GitLab CI, Docker images).
- Primary docs: Unity Manual "Unity Editor command line arguments", "Unity Hub command line
  arguments", and Unity Test Framework "Running tests from the command line".

## Related skills

- `unity-build-pipeline` — the C#-side Build Profiles and `BuildPipeline` code these commands invoke.
- `unity-csharp-scripting` — assembly definitions and the test/gameplay code being compiled.
