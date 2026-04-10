//
//  EFFiveDayRenderer.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// EFFiveDayRenderer.swift
// 五日分时图渲染器（复用 EFTimelineRenderer 扩展）
// 五日分时 = 5个交易日连接在一起，每天240分钟，共1200个数据点
// 区别于单日分时：底部时间轴显示每天的日期，不显示HH:mm

import UIKit
import CoreGraphics

// 五日分时图通过在 EFTimelineData 中设置 period = .fiveDay 来触发
// EFTimelineRenderer 已在 totalSlots/timeTicks 中处理了五日逻辑
// 本文件提供五日专属的时间轴标签计算

extension EFTimelineRenderer {

    /// 五日图底部时间标签（每个交易日中间位置显示日期）
    static func fiveDayTimeTicks(points: [EFTimePoint]) -> [(label: String, ratio: CGFloat)] {
        guard points.count > 1 else { return [] }

        let cal   = Calendar.current
        let total = 1200  // 5 * 240

        // 找到每天的分界线（以日期变化为准）
        var dayBoundaries = [Int]()  // 每天第一个点的索引
        var lastDay = -1
        for (i, p) in points.enumerated() {
            let day = cal.component(.day, from: p.time)
            if day != lastDay { dayBoundaries.append(i); lastDay = day }
        }

        var ticks = [(String, CGFloat)]()
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "M/d"

        for (di, start) in dayBoundaries.enumerated() {
            let end   = di + 1 < dayBoundaries.count ? dayBoundaries[di + 1] : points.count
            let mid   = (start + end) / 2
            let ratio = CGFloat(mid) / CGFloat(total - 1)
            let label = dateFmt.string(from: points[start].time)
            ticks.append((label, ratio))
        }
        return ticks
    }
}
