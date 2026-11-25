//
//  IconCache.swift
//  ClaudeMeter
//
//  Created by Edd on 2026-01-09.
//

import AppKit

/// Simple in-memory cache for rendered menu bar icons.
final class IconCache {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = Constants.Cache.maxIconCacheSize
    }

    func get(
        percentage: Double,
        status: UsageStatus,
        isLoading: Bool,
        isStale: Bool,
        iconStyle: IconStyle,
        weeklyPercentage: Double,
        isColored: Bool,
        accountLabel: String?,
        dualBarTime: DualBarTimeInfo?
    ) -> NSImage? {
        cache.object(forKey: cacheKey(
            percentage: percentage,
            status: status,
            isLoading: isLoading,
            isStale: isStale,
            iconStyle: iconStyle,
            weeklyPercentage: weeklyPercentage,
            isColored: isColored,
            accountLabel: accountLabel,
            dualBarTime: dualBarTime
        ))
    }

    func set(
        _ image: NSImage,
        percentage: Double,
        status: UsageStatus,
        isLoading: Bool,
        isStale: Bool,
        iconStyle: IconStyle,
        weeklyPercentage: Double,
        isColored: Bool,
        accountLabel: String?,
        dualBarTime: DualBarTimeInfo?
    ) {
        cache.setObject(
            image,
            forKey: cacheKey(
                percentage: percentage,
                status: status,
                isLoading: isLoading,
                isStale: isStale,
                iconStyle: iconStyle,
                weeklyPercentage: weeklyPercentage,
                isColored: isColored,
                accountLabel: accountLabel,
                dualBarTime: dualBarTime
            )
        )
    }

    private func cacheKey(
        percentage: Double,
        status: UsageStatus,
        isLoading: Bool,
        isStale: Bool,
        iconStyle: IconStyle,
        weeklyPercentage: Double,
        isColored: Bool,
        accountLabel: String?,
        dualBarTime: DualBarTimeInfo?
    ) -> NSString {
        let percent = String(format: "%.2f", percentage)
        let weekly = String(format: "%.2f", weeklyPercentage)
        let label = accountLabel ?? ""
        // The dualBarTime fields (time remaining + pacing) change independently of the percentages,
        // so they must be part of the key or a stale image would be reused as the clock advances.
        let dual: String
        if let dualBarTime {
            dual = "\(dualBarTime.sessionRemaining)|\(dualBarTime.weeklyRemaining)|\(dualBarTime.sessionPacing.rawValue)|\(dualBarTime.weeklyPacing.rawValue)"
        } else {
            dual = ""
        }
        return "\(percent)|\(weekly)|\(status.rawValue)|\(isLoading)|\(isStale)|\(iconStyle.rawValue)|\(isColored)|\(label)|\(dual)" as NSString
    }
}
