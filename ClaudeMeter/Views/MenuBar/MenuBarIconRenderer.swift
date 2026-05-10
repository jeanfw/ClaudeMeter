//
//  MenuBarIconRenderer.swift
//  ClaudeMeter
//
//  Created by Edd on 2026-01-09.
//

import AppKit
import SwiftUI

/// Renders SwiftUI MenuBarIconView to NSImage using ImageRenderer.
@MainActor
struct MenuBarIconRenderer {
    func render(
        percentage: Double,
        status: UsageStatus,
        isLoading: Bool,
        isStale: Bool,
        iconStyle: IconStyle,
        weeklyPercentage: Double = 0,
        useColor: Bool = true,
        accountLabel: String? = nil
    ) -> NSImage {
        let iconView = MenuBarIconView(
            percentage: percentage,
            status: status,
            isLoading: isLoading,
            isStale: isStale,
            iconStyle: iconStyle,
            weeklyPercentage: weeklyPercentage,
            useColor: useColor,
            accountLabel: accountLabel
        )

        let renderer = ImageRenderer(content: iconView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let nsImage = renderer.nsImage else {
            return NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Error"
            ) ?? NSImage()
        }

        // In monochrome mode the menu bar handles tinting (white on dark, black on light) via
        // template rendering. In coloured mode we want the original status colours preserved.
        nsImage.isTemplate = !useColor
        return nsImage
    }
}
