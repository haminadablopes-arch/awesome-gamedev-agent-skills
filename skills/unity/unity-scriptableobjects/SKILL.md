---
name: unity-scriptableobjects
description: >
  Architect Unity 6 (6.3 LTS / 6.6 / 6.7 Ready) data and decoupling with ScriptableObjects:
  config/data assets, native Dictionary data, shared runtime variables, event channels,
  and Fast Enter Play Mode reset safety. Use when designing data-driven systems, replacing
  singletons/managers, creating .asset data with CreateAssetMenu, or when the user mentions
  ScriptableObject, SO architecture, or data assets.
---

# Unity ScriptableObject Architecture

Use `ScriptableObject` assets to store shared data and decouple systems in Unity 6 —
configuration, native dictionary collections, event channels, and registries that live as project
assets instead of being hard-wired into scenes or singletons. Targets **Unity 6 (6.3 LTS / 6.6 / 6.7 Ready)**.

## When to use

- Use when you need designer-editable config (weapon stats, level data), to share one value
  between unrelated systems, to decouple senders from listeners via event channels, or to
  build a runtime registry of active objects — without a `static`/singleton manager.
- Use when the project has `*.asset` data files backed by `: ScriptableObject` classes.

**When _not_ to use:** per-instance runtime state that differs per GameObject (that belongs on
a MonoBehaviour) — a ScriptableObject asset is _shared_ by everyone who references it. Saving
player progress to disk → `save-systems`. Plain DTOs that never need to be an asset can just be
`[System.Serializable]` classes.

## Core workflow

1. **Define the class** deriving from `ScriptableObject` and tag it with `[CreateAssetMenu]` so
   designers can create instances from the Assets menu.
2. **Create one or more `.asset` instances** in the Project window; each is a shared, named
   piece of data referenced by `[SerializeField]` fields.
3. **Reference, don't copy.** MonoBehaviours hold a reference to the asset; they all see the
   same data, so changing the asset changes every consumer.
4. **For decoupling**, model _signals_ and _shared variables_ as ScriptableObjects: a
   "FloatVariable" the HUD reads and the player writes; an "event channel" the player raises
   and many systems listen to. Neither side references the other.
5. **Handle Fast Enter Play Mode safely**: because domain reload is skipped by default in Unity 6.6+,
   never rely on static variables inside ScriptableObjects without explicit reset methods.
6. **Verify** by inspecting the asset values during Play mode and confirming consumers react.

## Patterns

### 1. Config/data asset with native Dictionary (Unity 6.6+)

```csharp
using System.Collections.Generic;
using UnityEngine;

[CreateAssetMenu(fileName = "WeaponData", menuName = "Game/Weapon Data", order = 0)]
public class WeaponData : ScriptableObject
{
    public string displayName = "Pistol";
    public int    damage = 10;
    public float  fireRate = 0.25f;
    public GameObject projectilePrefab;

    // Native Dictionary serialization in Unity 6.6+
    [SerializeField] private Dictionary<string, float> elementalMultipliers = new()
    {
        { "fire", 1.5f },
        { "ice", 0.8f },
        { "lightning", 1.0f }
    };
}
```

```csharp
public class Weapon : MonoBehaviour
{
    [SerializeField] private WeaponData data;   // assign the shared asset in the Inspector
    private void Fire() => Debug.Log($"{data.displayName} for {data.damage}");
}
```

### 2. Shared runtime variable (decouples producer from consumer)

```csharp
[CreateAssetMenu(menuName = "Game/Float Variable")]
public class FloatVariable : ScriptableObject
{
    [SerializeField] private float initialValue;
    [System.NonSerialized] public float runtimeValue;   // not saved to the asset

    private void OnEnable() => runtimeValue = initialValue;  // reset each play session
}
// Player writes playerHealth.runtimeValue; the HUD reads it — neither references the other.
```

### 3. Creating an instance at runtime (not an asset on disk)

```csharp
// For transient SO data you build in code (e.g. a generated config).
var temp = ScriptableObject.CreateInstance<WeaponData>();
temp.damage = 25;
// ...use temp...  Destroy(temp);   // clean up runtime-created instances
```

## Pitfalls

- **Editing an SO at runtime persists in the Editor** — values you change during Play stay
  changed on the asset after you stop. Keep mutable runtime state in `[NonSerialized]` fields
  reset in `OnEnable`, or it will surprise you. (In a _build_, asset edits do not persist
  across launches.)
- **Disabled Domain Reload skips your `OnEnable` reset** — with **Fast Enter Play Mode**
  (Enter Play Mode Options enabled and Reload Domain off), already-loaded SOs are
  _not_ re-created when you press Play, so `OnEnable` never fires and `runtimeValue` keeps its
  value from the previous session. Reset explicitly from a runtime initialization hook or
  scene-load manager.
- **Expecting per-object state** — every reference points to the _same_ asset. If two enemies
  need different current HP, store HP on the MonoBehaviour, not the shared SO.
- **No frame lifecycle** — ScriptableObjects have `OnEnable`/`OnDisable`/`OnDestroy` but no
  `Update`. Don't expect per-frame callbacks.
- **Using SOs as a save file** — they're authoring assets, not runtime persistence; write
  progress with `save-systems` instead.
- **Leaking `CreateInstance` objects** — runtime-created instances are not garbage-collected
  like plain C# objects; `Destroy` them when done.

## References

- For the **event-channel** pattern (a `GameEvent` SO + listeners, type-safe payloads) and
  **runtime sets/registries** (a shared list of active enemies), read
  `references/event-channels.md`.
- Primary docs: Unity Manual "ScriptableObject" (`/Manual/class-ScriptableObject.html`) and
  `ScriptReference/ScriptableObject`, `ScriptReference/CreateAssetMenuAttribute`.

## Related skills

- `unity-csharp-scripting` — the MonoBehaviours that consume these assets.
- `save-systems` — persisting state to disk (what SOs are _not_ for).
- `card-game` / `rpg` / `survival-crafting` — genres that lean on SO-driven data.
