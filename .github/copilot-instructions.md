# FluxHaus - Smart Home Monitoring Application

FluxHaus is a multi-platform Swift/SwiftUI smart home monitoring application that runs on iOS and VisionOS. The app connects to the FluxHaus Server API (api.fluxhaus.io) to monitor and control various smart home devices including robots, cars, appliances, and HomeKit accessories. The app is available on the [App Store](https://apps.apple.com/ca/app/fluxhaus/id6478994447).

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the information here.**

## Working Effectively

### Prerequisites and Setup
- **macOS with Xcode 15.0+** required for building and running the application
- **Apple Developer Account** needed for testing on physical devices
- **API Access**: The app requires a valid password to connect to api.fluxhaus.io

### Building the Application
The application uses Xcode as the primary build system with multiple targets:

#### Core Build Commands (NEVER CANCEL - Set 90+ minute timeouts)
```bash
# Open the project in Xcode
open FluxHaus.xcodeproj

# Command line builds (if xcodebuild is available)
xcodebuild -project FluxHaus.xcodeproj -scheme "FluxHaus (iOS)" -configuration Debug build
xcodebuild -project FluxHaus.xcodeproj -scheme "VisionOS" -configuration Debug build
xcodebuild -project FluxHaus.xcodeproj -scheme "FluxWidgetExtension" -configuration Debug build
```

**CRITICAL BUILD TIMING:**
- **Initial build: 15-30 minutes** (includes Swift Package resolution and compilation)
- **Incremental builds: 2-5 minutes** for small changes
- **Clean builds: 10-20 minutes**
- **NEVER CANCEL** builds before 45 minutes - Swift compilation can be slow
- **Set timeouts to 90+ minutes** for all build commands

### Testing
#### Run Unit and UI Tests (NEVER CANCEL - Set 60+ minute timeouts)
```bash
# iOS Tests (takes 10-15 minutes)
xcodebuild test -project FluxHaus.xcodeproj -scheme "FluxHaus (iOS)" -destination 'platform=iOS Simulator,name=iPhone 15'

# VisionOS Tests (takes 10-15 minutes)
xcodebuild test -project FluxHaus.xcodeproj -scheme "VisionOS" -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

**Test Structure:**
- `Tests iOS/` - iOS UI tests that launch the app and test basic functionality
- `VisionOSTests/` - VisionOS unit and UI tests
- Note: macOS target exists in project structure but is not currently active
- All tests use XCTest framework with launch performance metrics

### Code Quality and Linting
#### SwiftLint (Required before commits)
```bash
# Install SwiftLint (if not already available)
brew install swiftlint

# Run linting (takes under 1 minute - very fast)
swiftlint --config .swiftlint.yml

# Run with strict mode (as used in CI)
swiftlint --strict --config .swiftlint.yml
```

**SwiftLint Configuration:**
- Configured in `.swiftlint.yml`
- Excludes `Packages/` directory
- Limits: file_length: 500, function_body_length: 60, type_body_length: 400
- **ALWAYS run SwiftLint before committing** - CI will fail otherwise

### Running the Application

#### iOS Application
```bash
# Build and run on iOS Simulator
xcodebuild -project FluxHaus.xcodeproj -scheme "FluxHaus (iOS)" -destination 'platform=iOS Simulator,name=iPhone 15' run

# Or open in Xcode and use Cmd+R to build and run
open FluxHaus.xcodeproj
```

#### VisionOS Application
```bash
# Build and run on VisionOS Simulator (requires Xcode 15+)
xcodebuild -project FluxHaus.xcodeproj -scheme "VisionOS" -destination 'platform=visionOS Simulator,name=Apple Vision Pro' run
```

#### Widget Extension
```bash
# Build the widget extension
xcodebuild -project FluxHaus.xcodeproj -scheme "FluxWidgetExtension" -configuration Debug build
```

**Note**: The project structure includes macOS files but the macOS target is not currently active in the build configuration.

## Validation and Testing Scenarios

### Manual Validation Requirements
After making changes, **ALWAYS** validate with these complete user scenarios:

#### 1. Login Flow Validation
- Launch the application
- Enter a test password (requires valid API credentials)
- Verify successful connection to api.fluxhaus.io
- Confirm data loads for all connected devices

#### 2. Smart Home Device Testing
- **Robot Controls**: Test start/stop actions for BroomBot and MopBot
- **Car Controls**: Test lock/unlock, climate on/off, resync actions  
- **Appliances**: Verify Miele and HomeConnect device status displays
- **HomeKit**: Test favorite scene activation
- **Weather**: Confirm weather data displays correctly

#### 3. Multi-Platform Consistency
- Test the same scenarios on iOS and VisionOS
- Verify UI layouts adapt correctly to each platform
- Confirm data synchronization across platforms

#### 4. Performance Validation
- Monitor app launch time (should be under 3 seconds)
- Verify API response times (should be under 2 seconds)
- Check memory usage during extended use

### CI/CD Validation
The project uses GitHub Actions for CI:
- **Linting**: Runs SwiftLint on all Swift files
- **Triggers**: On pull requests affecting Swift files or linting configuration
- **ALWAYS run `swiftlint --strict` before committing** to avoid CI failures

## Project Structure and Key Areas

### Core Directories
- `Shared/` - Business logic and models shared across all platforms
- `iOS/` - iOS-specific UI and app configuration  
- `VisionOS/` - VisionOS-specific UI and app configuration
- `FluxWidget/` - iOS widget extension
- `macOS/` - macOS files (target currently inactive)
- `Packages/RealityKitContent/` - VisionOS Reality Kit content

### Frequently Modified Files
- `Shared/Api.swift` - API response handling and data models
- `Shared/QueryFlux.swift` - Core API communication logic
- `Shared/Robots.swift` - Robot device control and status
- `Shared/Car.swift` - Car device control and status
- `Shared/HomeConnect.swift` - Home appliance integration
- `**/ContentView.swift` - Main UI views for each platform

### Key Configuration Files
- `FluxHaus.xcodeproj/` - Xcode project configuration
- `.swiftlint.yml` - Code style configuration
- `.github/workflows/lint.yml` - CI configuration
- `*/Info.plist` - App metadata for each platform

## Common Development Patterns

### API Integration
All API calls go through `queryFlux()` function in `QueryFlux.swift`:
- Uses HTTPS with basic authentication to api.fluxhaus.io
- Responses are decoded into `LoginResponse` models
- Data updates are broadcast via NotificationCenter

### Device Control Actions
Device actions follow a consistent pattern:
```swift
func performAction(action: String) {
    // Build API request
    // Make network call
    // Update UI state
    // Schedule resync after delay
}
```

### Platform-Specific Considerations
- **iOS**: Supports widgets, background refresh, and device battery monitoring
- **VisionOS**: Immersive UI elements and Reality Kit content
- **Note**: macOS target exists but is currently inactive in build configuration

### Data Flow
1. User authentication via `Login.swift`
2. API calls via `QueryFlux.swift` 
3. Data models updated in `Api.swift`
4. UI automatically updates via SwiftUI bindings
5. Device actions trigger immediate UI feedback and delayed data refresh

## Troubleshooting

### Common Build Issues
- **"Bundle.module not found"**: Normal on Linux - this only works on Apple platforms
- **SwiftLint violations**: Run `swiftlint --config .swiftlint.yml` and fix reported issues
- **Scheme not found**: Ensure you're using the correct scheme names: "FluxHaus (iOS)", "VisionOS", "FluxWidgetExtension"
- **Simulator issues**: Try resetting iOS/VisionOS simulators if apps won't launch
- **macOS references**: macOS files exist but target is inactive - focus on iOS and VisionOS

### API Connection Issues  
- Verify internet connectivity to api.fluxhaus.io
- Check that authentication credentials are valid
- API typically responds within 2 seconds - longer delays indicate server issues
- Car control actions take up to 90 seconds to complete

### Performance Issues
- Clean build folder if incremental builds become slow: Product → Clean Build Folder
- Restart Xcode if Interface Builder becomes unresponsive
- Reset simulators if apps crash frequently during development

**Remember**: This is a consumer smart home app requiring real API credentials to function fully. Most testing should be done with valid authentication to ensure complete validation of changes.