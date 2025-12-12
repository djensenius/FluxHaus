test: test-ios test-visionos

test-ios:
	xcodebuild test -project FluxHaus.xcodeproj -scheme "FluxHaus (iOS)" -destination 'platform=iOS Simulator,name=iPhone 17'

test-visionos:
	xcodebuild test -project FluxHaus.xcodeproj -scheme "VisionOS" -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
