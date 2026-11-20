//
//  SiriTools.swift
//  FluxHaus
//
//  Intents that Siri can call while handling a request (iOS/visionOS 27.3 Siri AI
//  developer preview). Apple's `@AppIntent(.tool)` macro just adds a `ToolIntent`
//  conformance, but it's only available from 27.3 and the apps deploy to 27.0, so we
//  add the conformance in availability-limited extensions instead.
//
//  The AppIntents version check keeps this file building with Xcode 27.2 (AppIntents
//  301.1.16), which doesn't have `ToolIntent`.
//
//  CleanRoomIntent and SetCarLockIntent stay as App Shortcuts only, so Siri sees one
//  tool per action.
//

import AppIntents

#if canImport(AppIntents, _version: 301.1.17)
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension LockCarIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension UnlockCarIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension StartCarClimateIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension StopCarClimateIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension ResyncCarIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension AnalyzeCarUsageIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension StartRobotIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension StopRobotIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension DeepCleanIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension CleanRoomsIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension ActivateSceneIntent: ToolIntent {}

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension DeviceStatusIntent: ToolIntent {}
#endif
