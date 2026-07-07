# DayNightCycle

A configurable, event-driven day/night cycle system for Roblox experiences. This module simulates a full 24-hour game day over a customizable real-world duration and allows developers to hook into specific times of day with named events.

## 🚀 Features

- Smoothly updates `Lighting.ClockTime` based on real-world time
- Supports flexible configuration for cycle speed, named events, and start time
- **Event-Driven**: Fires custom events at specific in-game hours (e.g. "Dawn", "Sunset")
- **Dynamic Events**: Add or remove custom time-based events at runtime.
- **Lifecycle Ready**: Integrates seamlessly with the `ModuleLoader` framework (`Setup` and `Start`).
- Self-contained debug logging with no external module dependency.

## 📦 Installation

This is a server-side module. An optimal place for storing `DayNightCycle.luau` in your project:

```
ServerScriptService/
└── Services/
    └── Environment/
        └── DayNightCycle.luau
```

## ⚙️ Configuration

The following options are available in the `config` table along with their default settings:

```lua
{
    DayLengthInMinutes = 180, -- The duration of a full 24-hour game day in real-world minutes.
    StartTimeOfDay = nil,     -- A specific hour (0-24) to start at. `nil` uses current `Lighting` time.
    TimeEvents = { -- A dictionary mapping event names to game hours.
        Dawn = 6.0,
        Sunrise = 7.0,
        Midday = 12.0,
        Sunset = 18.0,
        Dusk = 19.0,
        Midnight = 0.0,
    }
}
```

Use `DayNightCycle.Configure(...)` before calling `StartCycle()` to override defaults.

## 🧠 Usage

### With ModuleLoader
The module is designed to work out-of-the-box. If you're using the [`ModuleLoader`](/PublicModules/ModularFramework/) framework, the `ModuleLoader` will automatically call its `Start()` method, beginning the cycle with the default configuration.

### Standalone
If you're not using the loader, you can start the cycle manually:

```lua
local ServerScriptService = game:GetService("ServerScriptService")

local DayNightCycle = require(ServerScriptService.Services.Environment.DayNightCycle)

DayNightCycle.Configure({
    DayLengthInMinutes = 30,
    StartTimeOfDay = 8,
})
DayNightCycle.StartCycle()
```

### Adding Custom Time Events
```lua
DayNightCycle.AddTimeEvent("EveningRush", 17.5) -- Fires at 5:30 PM
```

### Listening for Events
The module fires named events via a `BindableEvent` located at `ReplicatedStorage.Remotes.DayNightEvents`. `BindableEvent` signals are same-context only; server-fired events are for server scripts. Use a `RemoteEvent` if clients need day/night notifications.

**Example: A script that controls streetlights.**
```lua
-- Location: ServerScriptService/Services/Systems/LightingManager.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- As events can be created dynamically, best practice is to use `WaitForChild` here.
-- Also note that you could require the module and directly reference DayNightCycle.Events.
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DayNightEvents = Remotes:WaitForChild("DayNightEvents")

local function onTimeChanged(eventName: string, eventHour: number)
    if eventName == "Dusk" then
        print("It's getting dark! Turning on streetlights.")
        -- Add your logic to turn on lights here
    elseif eventName == "Dawn" then
        print("The sun is rising! Turning off streetlights.")
        -- Add your logic to turn off lights here
    end
end

-- Connect to the event signal
DayNightEvents.Event:Connect(onTimeChanged)
```

## 🔧 API Reference

| Method                        | Description                                   |
|-------------------------------|-----------------------------------------------|
| `StartCycle()`                | Begins the day/night cycle                    |
| `StopCycle()`                 | Stops the cycle and disconnects updates       |
| `Configure(config)`           | Overrides defaults before the cycle starts    |
| `GetConfig()`                 | Returns a copy of the current configuration   |
| `AddTimeEvent(name, hour)`    | Adds or updates a named time event            |
| `RemoveTimeEvent(name)`       | Removes a named time event                    |
| `GetCurrentTime()`            | Returns the current in-game time (0–24)       |
| `Start()`                     | Lifecycle method for ModuleLoader integration |

### Public Properties
`DayNightCycle.Events: BindableEvent`  
The event that fires when a configured time is reached. It passes two arguments: `eventName: string` and `eventHour: number`.

## 📈 Performance Notes
- The update frequency can be lowered to reduce performance impact.
- Events are triggered once per day and reset at midnight.
- Uses `RunService.Heartbeat` for smooth time progression.

## 🧪 Debugging
Verbose logging can be enabled before start:

```lua
DayNightCycle.Configure({
    Debug = true,
})
```
This will print detailed messages about time progression and event triggers.

---

This module provides a solid foundation for creating dynamic, time-aware experiences and is designed to be flexible, lightweight, and easy to integrate into any Roblox experience. Feel free to adapt it to your needs or contribute improvements!
