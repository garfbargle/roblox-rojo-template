# getInstance

The `getInstance` module provides a **safe and convenient way to access instances** within a Roblox hierarchy by specifying a path of child names.  
It will throw an error if any part of the path does not exist, helping you catch issues early in development.

---

## 🧩 Usage

You can require this module and call it with the root instance and a sequence of child names:

```lua
local getInstance = require(ReplicatedStorage.Utils.getInstance)

local remoteEventsFolder: Folder = getInstance(game.ReplicatedStorage, "RemoteFolder", "RemoteEvents")
```

* **Parameters:**

  * `instance: Instance` — The root instance to start searching from.
  * `...: string` — A sequence of child names to traverse.
* **Returns:**
  The instance corresponding to the final child name in the path. The function is generic, so you can specify the expected type if desired.

> 💡 *Tip:* Use `getInstance` when accessing objects created at runtime or deeply nested folders to avoid repetitive `FindFirstChild` calls and to catch errors immediately if the path is invalid.

---

## 🧱 Design Philosophy

* **Safety First** — Errors immediately if a child is missing to prevent silent failures.
* **Simplicity** — Minimal API: just the root instance and a path of names.
* **Generics Support** — Compatible with typed Luau for type-safe access.
* **Reusable** — Works anywhere in your Roblox project where instances need to be accessed safely.
