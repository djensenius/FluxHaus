//
//  SiriEvaluationsTests.swift
//  Tests iOS
//
//  Siri AI developer preview (iOS 27.3) evaluations. They send real requests to
//  Siri, so they only run on an Apple Intelligence device that's signed in to
//  FluxHaus, with FLUXHAUS_SIRI_EVALUATIONS=1 set in the scheme's test environment.
//  Siri's replies vary between runs, so these check which tools, entities, and
//  skills Siri picks rather than the exact wording. Run them more than once.
//

#if canImport(SiriEvaluations)
import AppIntentsTesting
import Evaluations
import Foundation
import SiriEvaluations
import Testing

@available(iOS 27.3, *)
struct FluxHausSiriEvaluation: Evaluation {
    let name: String
    let dataset: SiriScenarioLoader

    func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
        try await SiriService.run(scenario: sample)
    }

    var evaluators: Evaluators {
        SiriExpectationEvaluator()
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        Self.computeSiriMetrics(into: &aggregator)
    }
}

@available(iOS 27.3, *)
private enum FluxHausSiriScenarios {
    static let bundleIdentifier = "org.davidjensenius.FluxHaus"

    static var tools: SiriScenarioLoader {
        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        let lockCar = definitions.intents["LockCarIntent"]
        let unlockCar = definitions.intents["UnlockCarIntent"]
        let deviceStatus = definitions.intents["DeviceStatusIntent"]
        let cleanRooms = definitions.intents["CleanRoomsIntent"]
        let device = definitions.entities["DeviceAppEntity"]

        return SiriScenarioLoader {
            SiriScenario {
                UserTurn("Use FluxHaus to make sure my car is locked") {
                    Calls {
                        lockCar
                    }
                    Calls(.disallowed) {
                        unlockCar
                    }
                }
            }
            SiriScenario {
                UserTurn("How long until the dishwasher is done in FluxHaus?") {
                    Calls {
                        deviceStatus
                            .expect(device: device.expectIdentifier("dishwasher"))
                    }
                }
            }
            SiriScenario {
                UserTurn("Have FluxHaus vacuum the kitchen and the hallway") {
                    Calls {
                        cleanRooms
                    }
                }
            }
        }
    }

    static var skills: SiriScenarioLoader {
        let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
        let unlockCar = definitions.intents["UnlockCarIntent"]

        return SiriScenarioLoader {
            SiriScenario {
                UserTurn("I'm heading out, get the house ready with FluxHaus") {
                    Loads(.required) {
                        definitions.skills["leaving-home"]
                    }
                    Calls(.disallowed) {
                        unlockCar
                    }
                }
            }
            SiriScenario {
                UserTurn("Is the laundry done in FluxHaus?") {
                    Loads(.required) {
                        definitions.skills["laundry-and-dishes"]
                    }
                }
            }
        }
    }
}

private let siriEvaluationsEnabled = ProcessInfo.processInfo.environment["FLUXHAUS_SIRI_EVALUATIONS"] == "1"

@available(iOS 27.3, *)
@Suite(.enabled(if: siriEvaluationsEnabled, "Set FLUXHAUS_SIRI_EVALUATIONS=1 on a Siri AI device"))
struct FluxHausSiriEvaluationTests {
    @Test(.evaluates(FluxHausSiriEvaluation(name: "FluxHaus tools", dataset: FluxHausSiriScenarios.tools)))
    func siriCallsFluxHausTools() {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
    }

    @Test(.evaluates(FluxHausSiriEvaluation(name: "FluxHaus skills", dataset: FluxHausSiriScenarios.skills)))
    func siriLoadsFluxHausSkills() {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .skillsLoadedPass)) == 1)
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
    }
}
#endif
