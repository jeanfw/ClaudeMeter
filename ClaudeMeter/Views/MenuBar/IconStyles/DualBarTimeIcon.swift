//
//  DualBarTimeIcon.swift
//  ClaudeMeter
//

import SwiftUI

/// Per-row data for the `dualBarTime` menu bar style: the compact time remaining and the pacing
/// verdict for the session (top) and weekly (bottom) windows. Computed by `MenuBarManager` so the
/// rendered string is consistent with the cache key.
struct DualBarTimeInfo: Equatable {
    let sessionRemaining: String
    let weeklyRemaining: String
    let sessionPacing: PacingState
    let weeklyPacing: PacingState
}

/// Dual bar menu bar icon showing session (top) and weekly (bottom) usage, each with the time
/// remaining in its window and — when a verdict is available — a pacing indicator (flame/target/
/// tortoise) matching the popover.
struct DualBarTimeIcon: View {
    let percentage: Double        // Session percentage
    let weeklyPercentage: Double  // Weekly percentage
    let status: UsageStatus
    let isLoading: Bool
    let isStale: Bool
    var useColor: Bool = true
    /// Time-remaining strings + pacing verdicts. Nil in previews/tests; rows then show a placeholder.
    var info: DualBarTimeInfo? = nil

    private let barWidth: CGFloat = 26
    private let barHeight: CGFloat = 5
    private let rowSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: 4) {
            if isLoading {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MenuBarIconColors.text(useColor: useColor, status: status, isStale: isStale))
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    row(
                        percentage: percentage,
                        fill: MenuBarIconColors.fill(useColor: useColor, status: status, isStale: isStale),
                        remaining: info?.sessionRemaining,
                        pacing: info?.sessionPacing
                    )
                    row(
                        percentage: weeklyPercentage,
                        fill: MenuBarIconColors.secondary(useColor: useColor, isStale: isStale),
                        remaining: info?.weeklyRemaining,
                        pacing: info?.weeklyPacing
                    )
                }

                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 4)
        .accessibilityLabel("Session: \(Int(percentage)) percent, Weekly: \(Int(weeklyPercentage)) percent")
        .accessibilityValue(status.accessibilityDescription)
    }

    @ViewBuilder
    private func row(percentage: Double, fill: Color, remaining: String?, pacing: PacingState?) -> some View {
        HStack(spacing: 3) {
            ProgressBar(percentage: percentage, color: fill, useColor: useColor)
                .frame(width: barWidth, height: barHeight)

            Text(remaining ?? "—")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(MenuBarIconColors.text(useColor: useColor, status: status, isStale: isStale))
                .fixedSize()

            if let pacing, pacing != .indeterminate {
                pacingIcon(pacing)
            }
        }
    }

    @ViewBuilder
    private func pacingIcon(_ state: PacingState) -> some View {
        // In monochrome mode the whole image is rendered as a template, so these colours collapse
        // to the system tint — the distinct symbol shapes still convey the verdict.
        switch state {
        case .overConsumption:
            Image(systemName: "flame.fill")
                .font(.system(size: 8))
                .foregroundColor(useColor ? .orange : .black)
        case .onTrack:
            Image(systemName: "target")
                .font(.system(size: 8))
                .foregroundColor(useColor ? .green : .black)
        case .underConsumption:
            Image(systemName: "tortoise.fill")
                .font(.system(size: 8))
                .foregroundColor(useColor ? .blue : .black)
        case .indeterminate:
            EmptyView()
        }
    }
}

/// Individual progress bar component
private struct ProgressBar: View {
    let percentage: Double
    let color: Color
    let useColor: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(MenuBarIconColors.track(useColor: useColor))

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: geo.size.width * min(percentage / 100, 1.0))
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DualBarTimeIcon(
            percentage: 65, weeklyPercentage: 45, status: .warning, isLoading: false, isStale: false,
            info: DualBarTimeInfo(sessionRemaining: "2h", weeklyRemaining: "4d", sessionPacing: .overConsumption, weeklyPacing: .onTrack)
        )
        DualBarTimeIcon(
            percentage: 20, weeklyPercentage: 80, status: .safe, isLoading: false, isStale: false, useColor: false,
            info: DualBarTimeInfo(sessionRemaining: "47m", weeklyRemaining: "99h", sessionPacing: .underConsumption, weeklyPacing: .overConsumption)
        )
        DualBarTimeIcon(
            percentage: 30, weeklyPercentage: 30, status: .safe, isLoading: false, isStale: false
        )
    }
    .padding()
}
