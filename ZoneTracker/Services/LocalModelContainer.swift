import Foundation
import SwiftData

// MARK: - Local Model Container

/// Builds the app's shared `ModelContainer` with CloudKit auto-mirroring
/// explicitly disabled.
///
/// ### Why not rely on SwiftData's default container
/// The default `.modelContainer(for:)` modifier inspects the app's
/// entitlements and, when a `com.apple.developer.icloud-container-identifiers`
/// entry exists, transparently wires the store up to CloudKit. That mirroring
/// path has strict schema requirements that our models intentionally violate:
///
/// - `WorkoutEntry.id` uses `@Attribute(.unique)`, which is unsupported by
///   CloudKit-backed stores.
/// - Several non-optional scalar attributes (`date`, `duration`,
///   `exerciseTypeRaw`, `phaseRaw`, `sessionTypeRaw`, `weekNumber`) have no
///   SwiftData defaults, which CloudKit also refuses at validation time.
///
/// Relaxing those constraints to appease CloudKit would weaken our local
/// invariants for no practical benefit, because cloud backup in this app is
/// already handled manually via `CloudSyncService` / `AppSyncCoordinator`
/// using dedicated `ZTProfile` / `ZTWorkout` record types. That manual path is
/// the source of truth for cross-device sync.
///
/// So the correct architecture is: **local-only SwiftData** (this container)
/// + **manual CloudKit sync** (the existing service). This factory encodes
/// that decision by passing `cloudKitDatabase: .none` to
/// `ModelConfiguration`, which prevents SwiftData from attempting the
/// incompatible auto-mirroring even when the iCloud entitlement is present.
enum LocalModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema([WorkoutEntry.self, UserProfile.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create local SwiftData container: \(error)")
        }
    }
}
