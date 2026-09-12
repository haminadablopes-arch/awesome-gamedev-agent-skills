# Unity CLI argument matrix & CI/CD recipes

Deep reference for `unity-cli`. Targets Unity 6 (6.3 LTS / 6.6 / 6.7 Ready).

## 1. Editor arguments

| Argument | Purpose | Notes |
| :--- | :--- | :--- |
| `-batchmode` | Run without a GUI, never show dialogs | Required for every automated run |
| `-quit` | Quit after the command finishes | Omit for `-runTests`; mandatory otherwise |
| `-nographics` | Do not initialize a graphics device | Required on GPU-less runners |
| `-projectPath <path>` | Project to open | Use an absolute path |
| `-logFile -` | Stream the Editor log to stdout | Without it output goes to the platform log path |
| `-executeMethod <T.M>` | Invoke `public static void` in an Editor assembly | Fully qualified: `Namespace.Class.Method` |
| `-buildTarget <target>` | Switch active target before running | `StandaloneLinux64`, `StandaloneWindows64`, `StandaloneOSX`, `Android`, `iOS`, `WebGL` |
| `-disable-assembly-updater` | Skip the API updater | Fail fast instead of auto-rewriting scripts in CI |
| `-noUpm` | Disable the package manager | Debugging package resolution hangs |
| `-accept-apiupdate` | Allow the API updater to run non-interactively | Pair with an explicit review step |
| `-silent-crashes` | Suppress crash dialogs | Batch servers |
| `-cacheServerEndpoint <host:port>` | Use an Accelerator | Big speedup on cold CI checkouts |
| `-createProject <path>` | Create an empty project | Useful for smoke-testing a package |
| `-importPackage <pkg>` | Import a `.unitypackage` | Legacy asset delivery |

## 2. Test Runner arguments

| Argument | Purpose |
| :--- | :--- |
| `-runTests` | Enter test mode (do **not** combine with `-quit`) |
| `-testPlatform <EditMode\|PlayMode\|<BuildTarget>>` | Which suite; a build target runs tests on a player |
| `-testResults <file.xml>` | NUnit3 XML report path |
| `-testFilter <regex,regex>` | Filter by full test name |
| `-testCategory <a,!b>` | Filter by `[Category]`, `!` negates |
| `-assemblyNames <A,B>` | Restrict to test assemblies |
| `-playerHeartbeatTimeout <s>` | Player test timeout |
| `-runSynchronously` | Run EditMode tests in one editor update |

### Exit codes

| Code | Meaning |
| :--- | :--- |
| 0 | Success / all tests passed |
| 1 | Editor failed to run (bad args, license, crash) |
| 2 | At least one test failed |
| 3 | The test run could not be started/completed |

### Parsing the report

```bash
python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
run = ET.parse(sys.argv[1]).getroot()
print(run.get("result"), run.get("total"), "failed:", run.get("failed"))
sys.exit(0 if run.get("result") == "Passed" else 2)
PY
```

## 3. Unity Hub CLI

```bash
unityhub --headless help
unityhub --headless editors --installed
unityhub --headless editors --releases
unityhub --headless install-path --get
unityhub --headless install --version 6000.3.0f1 --changeset <hash> --module android ios --childModules
unityhub --headless install-modules --version 6000.3.0f1 --module webgl
unityhub --headless uninstall --version 6000.3.0f1
```

Binaries: macOS `/Applications/Unity Hub.app/Contents/MacOS/Unity Hub`,
Windows `C:\Program Files\Unity Hub\Unity Hub.exe`, Linux `UnityHub.AppImage`.
When installing a specific version, always pass the matching `--changeset`.

## 4. Licensing in headless environments

```bash
# Activate a Plus/Pro serial
Unity -batchmode -quit -nographics -logFile - \
  -serial "$UNITY_SERIAL" -username "$UNITY_EMAIL" -password "$UNITY_PASSWORD"

# Always release the seat (floating/serial seats are limited)
Unity -batchmode -quit -nographics -logFile - -returnlicense

# Personal license: use a manual activation file produced by -createManualActivationFile
Unity -batchmode -quit -nographics -logFile - -manualLicenseFile Unity_v6.x.ulf
```

Never echo secrets into logs; pass them from CI secret stores only.

## 5. CI/CD recipes

### GitHub Actions (GameCI)

```yaml
jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - uses: actions/cache@v4
        with:
          path: Library
          key: Library-${{ hashFiles('Assets/**','Packages/**','ProjectSettings/**') }}
      - uses: game-ci/unity-test-runner@v4
        env:
          UNITY_LICENSE: ${{ secrets.UNITY_LICENSE }}
        with:
          testMode: all
          artifactsPath: artifacts
      - uses: game-ci/unity-builder@v4
        env:
          UNITY_LICENSE: ${{ secrets.UNITY_LICENSE }}
        with:
          targetPlatform: StandaloneLinux64
```

### GitLab CI (Docker)

```yaml
test:
  image: unityci/editor:ubuntu-6000.3.0f1-linux-il2cpp-3
  script:
    - ./scripts/activate-license.sh
    - ./skills/unity/unity-cli/scripts/run-tests.sh -p "$CI_PROJECT_DIR" -m EditMode -o artifacts
  artifacts:
    when: always
    paths: [artifacts/]
    reports:
      junit: artifacts/*.xml
```

### Raw docker invocation

```bash
docker run --rm -v "$PWD":/project -w /project \
  -e UNITY_LICENSE_CONTENT \
  unityci/editor:ubuntu-6000.3.0f1-base-3 \
  unity-editor -batchmode -quit -nographics -projectPath /project -logFile -
```

## 6. Packages from the command line

```bash
npm install -g openupm-cli
openupm add com.cysharp.unitask com.neuecc.unirx
openupm add -f com.company.pkg@1.2.3      # force a specific version
openupm ls
openupm remove com.neuecc.unirx
```

Manifest-only alternative (no extra tooling): edit `Packages/manifest.json`
`dependencies` / `scopedRegistries`, delete `Library/PackageCache` if a stale
resolution is suspected, then launch a `-batchmode -quit` run to re-resolve and
regenerate `Packages/packages-lock.json`.

## 7. Determinism checklist for CI

- Pin the editor version and changeset; never resolve "latest".
- Cache `Library/` keyed on `Assets/**`, `Packages/**`, `ProjectSettings/**`.
- Commit `Packages/packages-lock.json`.
- Stream logs with `-logFile -` and archive them as build artifacts.
- One Unity process per project path (`Temp/UnityLockfile`).
- Return the license in an `always()` teardown step.
