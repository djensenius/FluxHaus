# FluxHaus

A home monitor application for my various smart home things. Talks to [FluxHaus Server](https://github.com/djensenius/FluxHaus-Server/).

Available on the [App Store](https://apps.apple.com/ca/app/fluxhaus/id6478994447).

## Building and Testing

This project includes a `Makefile` to simplify running tests on the correct simulators.

### Run iOS Tests
```bash
make test-ios
```

### Run VisionOS Tests
```bash
make test-visionos
```

### Run All Tests
```bash
make test
```

## Climate

The Climate section brings the home's environment together: the Ecobee thermostat
(current temperature, activity, humidity, setpoints, mode, comfort setting, fan, and
“Resume schedule”), every room's temperature named after its Home Assistant area, the
air purifier, and indoor history. It is a tab on iPad and Vision Pro and a sidebar item
on Mac; on iPhone it heads the **More** list. Tapping the indoor summary on Home opens it.

Setpoint taps are combined and sent after a short pause, and the change shows right away
while the request is in flight. Changes reach the thermostat one at a time in the order
they were made, and setpoints use the thermostat's own unit. Every Climate screen shares one
queue per signed-in session; if the account changes, changes not yet sent are discarded.
Controls need FluxHaus Server's `/thermostat/*` routes (admin accounts only); with an older
server the readings still appear.

## Siri, Shortcuts & Apple Intelligence

FluxHaus exposes its controls and AI assistant to the system through [App Intents](https://developer.apple.com/documentation/appintents).
These ship in the iOS, visionOS, and macOS apps and are available in Siri, Spotlight, the
Shortcuts app, and Apple Intelligence.

Intent definitions live in `Shared/Intents/`:

- **Robots** — start, stop, and deep clean (Cleanbot)
- **Car** — lock, unlock, start/stop climate (defrost, heated features, temperature), and resync
- **Scenes** — activate a HomeKit scene (the scene list is provided dynamically)
- **Thermostat** — set the temperature and/or mode, and resume the schedule (Shortcuts actions only, no Siri phrase)
- **Status** — car, robot, dishwasher, and scooter status queries
- **Ask FluxHaus** — a free-text question routed to the FluxHaus AI assistant

`FluxHausShortcuts` (an `AppShortcutsProvider`) registers Siri phrases such as
“Lock my car with FluxHaus” and “Ask FluxHaus”. The system caps an app at **10** phrased
App Shortcuts, so the remaining intents are still available as actions in the Shortcuts app.

Intents reuse the shared `AuthManager` session and require the user to be signed in.

### Adding a new intent

1. Add the intent (and any `AppEnum`/`AppEntity`) to `Shared/Intents/`.
2. Use `static let` for `title`/`description` (Swift 6 strict concurrency).
3. Optionally register a phrase in `FluxHausShortcuts` (keep total ≤ 10).
4. Add the file to the `FluxHaus (iOS)`, `VisionOS`, and `FluxHaus (macOS)` targets.

