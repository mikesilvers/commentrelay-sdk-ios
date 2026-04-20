import SwiftUI
import XCTest
import SnapshotTesting

/// Shared config for UI snapshot tests. Tuned so snapshots are stable across local runs.
enum SnapshotCfg {
    /// Flip to true (locally only) to regenerate baselines.
    static let isRecording = false
}
