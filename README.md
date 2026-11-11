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

## Siri, Shortcuts & Apple Intelligence

FluxHaus exposes its controls and AI assistant to the system through [App Intents](https://developer.apple.com/documentation/appintents).
These ship in the iOS, visionOS, and macOS apps and are available in Siri, Spotlight, the
Shortcuts app, and Apple Intelligence.

Intent definitions live in `Shared/Intents/`:

- **Robots** — start, stop, deep clean, and clean one or more rooms (Cleanbot)
- **Car** — lock, unlock, start/stop climate (defrost, heated features, temperature), and resync
- **Scenes** — activate a HomeKit scene (the scene list is provided dynamically)
- **Status** — car, robot, dishwasher, and scooter status queries
- **Ask FluxHaus** — a free-text question routed to the FluxHaus AI assistant

`FluxHausShortcuts` (an `AppShortcutsProvider`) registers Siri phrases such as
“Lock my car with FluxHaus” and “Ask FluxHaus”. The system caps an app at **10** phrased
App Shortcuts, so the remaining intents are still available as actions in the Shortcuts app.

Intents reuse the shared `AuthManager` session and require the user to be signed in.
Unlock Car and Set Car Lock also require the device to be unlocked. That includes
“Lock my car with FluxHaus”, which runs Set Car Lock; the separate Lock Car action doesn't.

### Siri AI developer preview (iOS/visionOS 27.3)

FluxHaus opts into the 27.3 Siri AI developer preview:

- **Tool intents** — `SiriTools.swift` makes the car, robot, scene, and device-status
  actions `ToolIntent`s so Siri can call them while handling a request.
  `CleanRoomsIntent` accepts several rooms at once. Set Car Lock and the single-room
  Clean Room action stay App Shortcuts only, so Siri doesn't see duplicate tools.
- **Device results** — Device Status returns the `DeviceAppEntity` with a `status`
  property, which Siri can show as a card (`DeviceSnippet.swift`) or share as text.
- **App skills** — `Shared/Skills.skillsbundle` contains instructions for leaving home,
  preparing the car, cleaning, and laundry/dishes.

The apps still deploy to 27.0, so the tool conformances and snippet are marked
`@available(… 27.3, *)` instead of using the 27.3-only `@AppIntent(.tool)` macro.
They're also wrapped in `#if canImport(AppIntents, _version: 301.1.17)` so the
project builds with Xcode 27.2, which leaves them out. The skills bundle is a plain
resource folder, so it ships in every build. The preview only works in development-signed and
internal TestFlight builds.

`Tests iOS/SiriEvaluationsTests.swift` (compiled only when the SiriEvaluations
framework is available) checks that Siri picks the right tools and skills. It needs a
27.3 device with Apple Intelligence, a signed-in FluxHaus, and
`FLUXHAUS_SIRI_EVALUATIONS=1` in the test scheme's environment.

### Adding a new intent

1. Add the intent (and any `AppEnum`/`AppEntity`) to `Shared/Intents/`.
2. Use `static let` for `title`/`description` (Swift 6 strict concurrency).
3. Optionally register a phrase in `FluxHausShortcuts` (keep total ≤ 10).
4. Add the file to the `FluxHaus (iOS)`, `VisionOS`, and `FluxHaus (macOS)` targets.
5. If Siri should be able to call it, add a `ToolIntent` conformance in `SiriTools.swift`.

