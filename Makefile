DEVICE_IOS ?= "iPhone 17"
DEVICE_VISION ?= "Apple Vision Pro"

test: test-ios test-visionos

test-ios:
	xcodebuild test -project FluxHaus.xcodeproj -scheme "FluxHaus (iOS)" -destination 'platform=iOS Simulator,name=$(DEVICE_IOS)'

test-visionos:
	xcodebuild test -project FluxHaus.xcodeproj -scheme "VisionOS" -destination 'platform=visionOS Simulator,name=$(DEVICE_VISION)'
