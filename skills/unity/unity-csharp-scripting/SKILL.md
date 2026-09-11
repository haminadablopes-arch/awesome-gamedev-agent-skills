---
name: unity-csharp-scripting
description: >
  Write Unity 6 (6.3 LTS / 6.6 / 6.7 Ready) C# gameplay scripts: the MonoBehaviour
  lifecycle (Awake/OnEnable/Start/Update/FixedUpdate/LateUpdate), Fast Enter Play Mode,
  static state cleanup, GameObject and component access, native Dictionary serialization,
  and coroutines. Use when creating or editing .cs scripts in a Unity project, or when
  the user mentions MonoBehaviour, Start/Update, GetComponent, SerializeField, coroutines,
  Fast Enter Play Mode, or "Unity script".
---

# Unity C# Scripting (MonoBehaviour)

Write correct, idiomatic gameplay scripts in Unity 6. Get the lifecycle, component
access, Inspector serialization, static state cleanup, and coroutines right so behaviour
is deterministic and iteration in Play Mode is instant. Targets **Unity 6 (6.3 LTS / 6.6 / 6.7 Ready)**,
C# / .NET Standard 2.1 and CoreCLR (.NET 10 / C# 14 roadmap).

## When to use

- Use when authoring or fixing a `MonoBehaviour`: choosing the right lifecycle callback,
  reading/caching components, exposing fields to the Inspector (including native dictionaries),
  handling static state in Fast Enter Play Mode, or running timed logic with coroutines.
- Use when the project has `*.cs` files, an `Assembly-CSharp` or `*.asmdef`, and a
  `ProjectSettings/` folder.

**When *not* to use:** moving rigidbodies / collision response → `unity-physics`; reading
player input → `unity-input-system`; shared data assets / config → `unity-scriptableobjects`;
Animator parameters → `unity-animation`. This skill owns the *script lifecycle and C#
plumbing*, not those subsystems.

## Core workflow

1. **Pick the callback by purpose, not habit.** `Awake` (cache references, self-setup),
   `OnEnable` (subscribe to events), `Start` (cross-object wiring), `Update` (per-frame
   input/logic), `FixedUpdate` (physics), `LateUpdate` (camera follow/IK),
   `OnDisable`/`OnDestroy` (unsubscribe/cleanup).
2. **Cache component lookups in `Awake`** — never call `GetComponent` inside `Update`.
3. **Expose tunables with `[SerializeField] private`**, not public fields, so other code
   can't mutate them while designers edit them in the Inspector.
4. **Clean up static fields and events for Fast Enter Play Mode** (the default in Unity 6.6+).
   Because domain reloads are skipped on Play, static data persists across Play sessions unless
   explicitly reset.
5. **Scale per-frame values by `Time.deltaTime`** in `Update` (and `Time.fixedDeltaTime`
   semantics in `FixedUpdate`).
6. **Use coroutines for time-sequenced logic** (delays, step sequences); start with
   `StartCoroutine` and stop by handle.
7. **Verify in Play mode**: test entering/exiting Play Mode multiple times without domain
   reload to confirm static events and references do not leak or throw null references.

## Patterns

### 1. Lifecycle + cached components (the canonical skeleton)

```csharp
using UnityEngine;

[RequireComponent(typeof(Rigidbody))]      // auto-adds the dependency, prevents null refs
public class PlayerController : MonoBehaviour
{
    [SerializeField] private float moveSpeed = 6f;   // editable in Inspector, private in code
    private Rigidbody _rb;                            // cached, not fetched per frame

    private void Awake() => _rb = GetComponent<Rigidbody>();  // cache once on load

    private void Update()
    {
        // Per-frame, non-physics work. Scale by deltaTime so it is frame-rate independent.
        transform.Rotate(0f, 90f * Time.deltaTime, 0f);
    }

    private void FixedUpdate()
    {
        // Physics work belongs here (fixed timestep). See the unity-physics skill.
        _rb.MovePosition(_rb.position + transform.forward * moveSpeed * Time.fixedDeltaTime);
    }
}
```

### 2. Fast Enter Play Mode & static state cleanup

In Unity 6.6+, Fast Enter Play Mode skips domain reload by default. Always reset static variables and event delegates:

```csharp
using System;
using UnityEngine;

public class GameManager : MonoBehaviour
{
    public static GameManager Instance { get; private set; }
    public static event Action<int> OnScoreChanged;

    private static int _highScore;

    // Reset static state when entering Play Mode without Domain Reload
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
    private static void ResetStatics()
    {
        Instance = null;
        OnScoreChanged = null;
        _highScore = 0;
    }

    private void Awake()
    {
        if (Instance != null && Instance != null)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
    }

    private void OnDestroy()
    {
        if (Instance == this)
            Instance = null;
    }
}
```

### 3. Native Dictionary and Inspector serialization

Unity 6.6+ natively serializes `Dictionary<TKey, TValue>` without requiring custom serialization wrappers:

```csharp
using System.Collections.Generic;
using UnityEngine;

public class InventoryConfig : MonoBehaviour
{
    [SerializeField, Range(0f, 1f)] private float dropRate = 0.8f;
    [SerializeField] private string characterId = "Hero_01";

    // Natively serialized in Inspector in Unity 6.6+ (no wrapper required)
    [SerializeField] private Dictionary<string, int> startingItems = new()
    {
        { "potion_health", 5 },
        { "potion_mana", 2 }
    };

    [System.Serializable]
    public class ItemAttributes
    {
        public int attackBonus;
        public int defenseBonus;
    }

    [SerializeField] private Dictionary<string, ItemAttributes> itemStats = new();
}
```

### 4. Safe component access with `TryGetComponent`

```csharp
// Avoids allocating a null check and is clearer than GetComponent + null check.
if (other.TryGetComponent<Health>(out var health))
    health.Apply(-10);
```

### 5. Coroutines for time-sequenced logic

```csharp
private Coroutine _flashRoutine;

private void OnEnable()
{
    _flashRoutine = StartCoroutine(FlashThenHide());
}

private void OnDisable()
{
    if (_flashRoutine != null)
        StopCoroutine(_flashRoutine);
}

private System.Collections.IEnumerator FlashThenHide()
{
    yield return new WaitForSeconds(0.5f);   // wait half a second of game time
    if (TryGetComponent<Renderer>(out var rend))
        rend.enabled = false;
    yield return null;                       // resume next frame
}
```

## Pitfalls

- **Static event / singleton leak across Play sessions (Fast Enter Play Mode)** — When domain
  reload is disabled, static events retain subscribers from previous Play runs, causing duplicate
  event execution and `MissingReferenceException`. Use `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]`
  to clear static state.
- **`GetComponent` inside `Update`** — searches the GameObject hierarchy every frame and tanks
  performance. Cache the reference in `Awake` or `Start`.
- **Physics movement inside `Update`** — moving a `Rigidbody` outside `FixedUpdate` causes jitter
  and variable timestep anomalies. Read input in `Update`, apply physics in `FixedUpdate`.
- **Relying on execution order between distinct `Start` or `Awake` calls** — all `Awake`s finish
  before any `Start`, but relative order across different objects is undefined unless configured
  in Script Execution Order.
- **`public` fields solely for Inspector visibility** — breaks encapsulation. Use
  `[SerializeField] private` instead.
- **`gameObject.tag == "Enemy"` allocation** — allocates a string comparison; use
  `gameObject.CompareTag("Enemy")`.
- **Mono vs CoreCLR workarounds** — Unity 6.7 introduces CoreCLR experimental runtimes; avoid
  brittle Mono-internal reflection hacks that break on modern runtime targets.

## References

- For the complete event-execution-order table, advanced coroutine yield types, and Fast Enter
  Play Mode domain reload patterns, read `references/lifecycle-and-coroutines.md`.
- Primary docs: Unity Manual "Event function execution order"
  (`https://docs.unity3d.com/Manual/execution-order.html`) and "Configuring Enter Play Mode".

## Related skills

- `unity-physics` — `Rigidbody`, collisions, and `FixedUpdate` motion with `linearVelocity`.
- `unity-input-system` — reading modern Input System actions into scripts.
- `unity-scriptableobjects` — shared configuration, event channels, and data architecture.
