//
//  EFTimelineRenderer.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// EFTimelineRenderer.swift
// 分时图渲染器 — 支持个股（含右侧盘口预留区）和指数（全宽+涨跌家数柱）

import UIKit
import CoreGraphics

final class EFTimelineRenderer {

    private let scale: CGFloat

    init(scale: CGFloat = UIScreen.main.scale) { self.scale = scale }

    // MARK: ── 主入口 ─────────────────────────────────────────

    /// 渲染主图（价格线 + 均价线 + 背景 + 网格 + 指数内嵌家数柱）
    func renderMain(
        data: EFTimelineData,
        rect: CGRect,
        crosshairIdx: Int? = nil,
        subIndicator: EFSubIndicator = .volume
    ) -> CGImage? {
        guard let ctx = makeOffscreenContext(size: rect.size, scale: scale) else { return nil }
        drawMain(ctx: ctx, data: data, rect: rect.withOrigin(.zero), crosshairIdx: crosshairIdx)
        return ctx.makeImage()
    }

    /// 渲染副图（MACD / 成交量等）
    func renderSub(
        data: EFTimelineData,
        subType: EFSubIndicator,
        rect: CGRect,
        crosshairIdx: Int? = nil
    ) -> CGImage? {
        guard let ctx = makeOffscreenContext(size: rect.size, scale: scale) else { return nil }
        drawSub(ctx: ctx, data: data, subType: subType,
                rect: rect.withOrigin(.zero), crosshairIdx: crosshairIdx)
        return ctx.makeImage()
    }

    // MARK: ── 主图绘制 ───────────────────────────────────────

    private func drawMain(ctx: CGContext, data: EFTimelineData, rect: CGRect, crosshairIdx: Int?) {
        let pts     = data.points
        let total   = EFTimelineRenderer.totalSlots(for: data.period)
        let content = mainContentRect(rect)
        let range   = data.priceRange
        let map     = EFCoordMap(rect: content, minV: range.lowerBound, maxV: range.upperBound)

        // ── 背景
        ctx.setFillColor(EFColor.panel.cgColor)
        ctx.fill(rect)

        // 指数：在主图区域内嵌涨跌家数柱（底部 30% 区域）
        if data.securityType == .index {
            drawIndexBars(ctx: ctx, pts: pts, total: total, content: content)
        }

        // ── 网格 & 轴标签
        drawPriceGrid(ctx: ctx, rect: rect, content: content, data: data, map: map)

        // ── 昨收虚线
        let prevY = map.y(data.prevClose)
        ctx.strokeDashedLine(
            from: CGPoint(x: content.minX, y: prevY),
            to:   CGPoint(x: content.maxX, y: prevY),
            color: EFColor.prevClose, lineWidth: 0.5
        )

        guard pts.count >= 2 else { return }

        // ── 渐变填充
        drawGradientFill(ctx: ctx, pts: pts, total: total, content: content, map: map)

        // ── 价格线
        drawPriceLine(ctx: ctx, pts: pts, total: total, content: content, map: map)

        // ── 均价线
        drawAvgLine(ctx: ctx, pts: pts, total: total, content: content, map: map)

        // ── 十字线
        if let idx = crosshairIdx, idx < pts.count {
            drawCrosshair(ctx: ctx, idx: idx, pts: pts, total: total,
                         rect: rect, content: content, map: map, data: data)
        }
    }

    // MARK: ── 指数内嵌涨跌柱 ──────────────────────────────────

    private func drawIndexBars(ctx: CGContext, pts: [EFTimePoint], total: Int, content: CGRect) {
        guard !pts.isEmpty else { return }
        let maxAdv = pts.compactMap(\.advancers).max().map(Double.init) ?? 1
        let maxDec = pts.compactMap(\.decliners).max().map(Double.init) ?? 1
        let barZoneH = content.height * 0.30
        let barZoneY = content.maxY - barZoneH
        let slotW    = content.width / CGFloat(total)
        let barW     = Swift.max(1, slotW * 0.8)

        let advPath = CGMutablePath()
        let decPath = CGMutablePath()

        for (i, p) in pts.enumerated() {
            let x = content.minX + (CGFloat(i) + 0.5) * slotW
            if let adv = p.advancers, adv > 0 {
                let h = barZoneH * CGFloat(Double(adv) / maxAdv)
                advPath.addRect(CGRect(x: x - barW/2, y: barZoneY + barZoneH - h, width: barW, height: h))
            }
            if let dec = p.decliners, dec > 0 {
                let h = barZoneH * CGFloat(Double(dec) / maxDec)
                decPath.addRect(CGRect(x: x - barW/2, y: barZoneY + barZoneH - h, width: barW, height: h))
            }
        }
        ctx.addPath(advPath); ctx.setFillColor(EFColor.indexAdvancer.cgColor); ctx.fillPath()
        ctx.addPath(decPath); ctx.setFillColor(EFColor.indexDecliner.cgColor); ctx.fillPath()
    }

    // MARK: ── 渐变填充 ───────────────────────────────────────

    private func drawGradientFill(ctx: CGContext, pts: [EFTimePoint], total: Int,
                                   content: CGRect, map: EFCoordMap) {
        let path = CGMutablePath()
        let slotW = content.width / CGFloat(total)
        var started = false
        for (i, p) in pts.enumerated() {
            let x = content.minX + CGFloat(i) * slotW
            let y = map.y(p.price)
            if !started { path.move(to: CGPoint(x: x, y: y)); started = true }
            else        { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        let lastX = content.minX + CGFloat(pts.count - 1) * slotW
        path.addLine(to: CGPoint(x: lastX, y: content.maxY))
        path.addLine(to: CGPoint(x: content.minX, y: content.maxY))
        path.closeSubpath()

        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let colors = [EFColor.timelineFillTop.cgColor, EFColor.timelineFillBot.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: content.midX, y: content.minY),
                end:   CGPoint(x: content.midX, y: content.maxY),
                options: []
            )
        }
        ctx.restoreGState()
    }

    // MARK: ── 价格折线 ───────────────────────────────────────

    private func drawPriceLine(ctx: CGContext, pts: [EFTimePoint], total: Int,
                                content: CGRect, map: EFCoordMap) {
        let slotW = content.width / CGFloat(total)
        let points: [CGPoint?] = pts.enumerated().map { i, p in
            CGPoint(x: content.minX + CGFloat(i) * slotW, y: map.y(p.price))
        }
        ctx.strokePolyline(points: points, color: EFColor.timelineMain, lineWidth: 1.5)
    }

    // MARK: ── 均价线 ──────────────────────────────────────────

    private func drawAvgLine(ctx: CGContext, pts: [EFTimePoint], total: Int,
                              content: CGRect, map: EFCoordMap) {
        let slotW = content.width / CGFloat(total)
        let points: [CGPoint?] = pts.enumerated().map { i, p in
            CGPoint(x: content.minX + CGFloat(i) * slotW, y: map.y(p.avgPrice))
        }
        ctx.strokePolyline(points: points, color: EFColor.timelineAvg, lineWidth: 1.0)
    }

    // MARK: ── 网格 & 轴标签 ──────────────────────────────────

    private func drawPriceGrid(ctx: CGContext, rect: CGRect, content: CGRect,
                                data: EFTimelineData, map: EFCoordMap) {
        let rows   = EFLayout.mainRows
        let range  = data.priceRange
        let span   = range.upperBound - range.lowerBound

        // 水平网格线 + 右侧价格/涨跌幅
        for i in 0..<rows {
            let ratio = Double(i) / Double(rows - 1)
            let price = range.upperBound - ratio * span
            let y     = map.y(price)
            let pct   = (price - data.prevClose) / data.prevClose * 100

            // 格线
            ctx.strokeLine(from: CGPoint(x: content.minX, y: y),
                            to:   CGPoint(x: content.maxX, y: y),
                            color: EFColor.grid, lineWidth: 0.5)

            // 右侧价格标签
            let priceColor: UIColor = pct > 0 ? EFColor.rising : (pct < 0 ? EFColor.falling : EFColor.textSecondary)
            ctx.drawString(EFFormat.price(price, decimals: priceDecimalPlaces(data.prevClose)),
                            at: CGPoint(x: content.maxX + 3, y: y),
                            font: EFLayout.axisFont, color: priceColor, align: .left)

            // 左侧涨跌幅（指数不显示）
            if data.securityType != .index {
                ctx.drawString(EFFormat.percent(pct, signed: true),
                                at: CGPoint(x: content.minX + 2, y: y),
                                font: EFLayout.axisFont, color: priceColor, align: .left)
            }
        }

        // 垂直网格线 + 底部时间标签
        let timeTicks = EFTimelineRenderer.timeTicks(for: data.period)
        for (label, ratio) in timeTicks {
            let x = content.minX + ratio * content.width
            if ratio > 0 && ratio < 1 {
                ctx.strokeLine(from: CGPoint(x: x, y: content.minY),
                                to:   CGPoint(x: x, y: content.maxY),
                                color: EFColor.grid, lineWidth: 0.5)
            }
            let labelX: CGFloat = ratio < 0.1 ? content.minX : (ratio > 0.9 ? content.maxX : x)
            let align: NSTextAlignment = ratio < 0.1 ? .left : (ratio > 0.9 ? .right : .center)
            let labelY = content.maxY + EFLayout.timeAxisH / 2
            ctx.drawString(label, at: CGPoint(x: labelX, y: labelY),
                            font: EFLayout.axisFont, color: EFColor.textSecondary, align: align)
        }

        // 外边框
        ctx.setStrokeColor(EFColor.border.cgColor); ctx.setLineWidth(0.5)
        ctx.stroke(content)

        // 上角：+10%/-10% 标签（个股）
        if data.securityType == .stock {
            ctx.drawString("+10.00%", at: CGPoint(x: content.maxX + 3, y: content.minY + 6),
                            font: EFLayout.axisFont, color: EFColor.rising, align: .left)
            ctx.drawString("-10.00%", at: CGPoint(x: content.maxX + 3, y: content.maxY - 6),
                            font: EFLayout.axisFont, color: EFColor.falling, align: .left)
        }
    }

    // MARK: ── 十字线 ──────────────────────────────────────────

    private func drawCrosshair(ctx: CGContext, idx: Int, pts: [EFTimePoint],
                                total: Int, rect: CGRect, content: CGRect,
                                map: EFCoordMap, data: EFTimelineData) {
        let slotW = content.width / CGFloat(total)
        let p     = pts[idx]
        let x     = content.minX + CGFloat(idx) * slotW
        let y     = map.y(p.price)

        // 十字线
        ctx.strokeDashedLine(from: CGPoint(x: content.minX, y: y),
                              to:   CGPoint(x: content.maxX, y: y),
                              color: EFColor.crosshair, lineWidth: 0.5)
        ctx.strokeDashedLine(from: CGPoint(x: x, y: content.minY),
                              to:   CGPoint(x: x, y: content.maxY),
                              color: EFColor.crosshair, lineWidth: 0.5)

        // 圆点
        let r: CGFloat = 3
        ctx.setFillColor(EFColor.timelineMain.cgColor)
        ctx.fillEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))

        // 右侧价格 badge
        let pColor = p.changePercent >= 0 ? EFColor.rising : EFColor.falling
        ctx.drawLabelBadge(EFFormat.price(p.price, decimals: priceDecimalPlaces(data.prevClose)),
                            at: CGPoint(x: content.maxX + 1, y: y),
                            font: EFLayout.axisFont, fg: .white, bg: pColor)

        // 底部时间 badge
        ctx.drawLabelBadge(EFFormat.time(p.time),
                            at: CGPoint(x: x, y: content.maxY + EFLayout.timeAxisH/2),
                            font: EFLayout.axisFont, fg: EFColor.background, bg: EFColor.crosshairLabel)

        // Tooltip
        drawTimelineTooltip(ctx: ctx, p: p, at: CGPoint(x: x, y: y),
                             content: content, data: data)
    }

    private func drawTimelineTooltip(ctx: CGContext, p: EFTimePoint,
                                      at pt: CGPoint, content: CGRect, data: EFTimelineData) {
        let dec  = priceDecimalPlaces(data.prevClose)
        let rows: [(String, String, UIColor)] = [
            ("时间", EFFormat.full(p.time),                           EFColor.textPrimary),
            ("价格", EFFormat.price(p.price, decimals: dec),          p.changePercent >= 0 ? EFColor.rising : EFColor.falling),
            ("均价", EFFormat.price(p.avgPrice, decimals: dec),       EFColor.timelineAvg),
            ("涨跌", EFFormat.percent(p.changePercent, signed: true), p.changePercent >= 0 ? EFColor.rising : EFColor.falling),
            ("成交", EFFormat.volume(p.volume),                       EFColor.textPrimary),
            ("金额", EFFormat.amount(p.amount),                       EFColor.textPrimary),
        ]
        drawTooltip(ctx: ctx, rows: rows, at: pt, content: content)
    }

    // MARK: ── 副图渲染 ───────────────────────────────────────

    private func drawSub(ctx: CGContext, data: EFTimelineData, subType: EFSubIndicator,
                          rect: CGRect, crosshairIdx: Int?) {
        ctx.setFillColor(EFColor.panel.cgColor); ctx.fill(rect)
        let content = subContentRect(rect)
        ctx.setStrokeColor(EFColor.border.cgColor); ctx.setLineWidth(0.5); ctx.stroke(content)

        let pts   = data.points
        let total = EFTimelineRenderer.totalSlots(for: data.period)

        switch subType {
        case .volume:
            drawVolumeInTimeline(ctx: ctx, pts: pts, total: total, content: content,
                                  crosshairIdx: crosshairIdx)
        case .macd:
            // 分时 MACD（基于收盘价序列）
            let closes = pts.map(\.price)
            if closes.count > 26 {
                let r = EFIndicatorEngine.macd(closes: closes)
                drawMACDSub(ctx: ctx, result: r, count: pts.count, total: total,
                             content: content, crosshairIdx: crosshairIdx)
            }
        default: break
        }
    }

    private func drawVolumeInTimeline(ctx: CGContext, pts: [EFTimePoint], total: Int,
                                       content: CGRect, crosshairIdx: Int?) {
        guard !pts.isEmpty else { return }
        let maxVol   = pts.map(\.volume).max() ?? 1
        let slotW    = content.width / CGFloat(total)
        let barW     = Swift.max(1, slotW * 0.8)

        let upPath   = CGMutablePath(), dnPath = CGMutablePath()
        for (i, p) in pts.enumerated() {
            let x = content.minX + (CGFloat(i) + 0.5) * slotW
            let h = content.height * CGFloat(p.volume / maxVol)
            let r = CGRect(x: x - barW/2, y: content.maxY - h, width: barW, height: h)
            if p.changePercent >= 0 { upPath.addRect(r) } else { dnPath.addRect(r) }
        }
        ctx.addPath(upPath); ctx.setFillColor(EFColor.rising.withAlphaComponent(0.85).cgColor); ctx.fillPath()
        ctx.addPath(dnPath); ctx.setFillColor(EFColor.falling.withAlphaComponent(0.85).cgColor); ctx.fillPath()

        // 最大成交量标签
        ctx.drawString(EFFormat.volume(maxVol),
                        at: CGPoint(x: content.maxX + 3, y: content.minY + 6),
                        font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)

        // 十字线竖线延伸
        if let idx = crosshairIdx, idx < pts.count {
            let x = content.minX + CGFloat(idx) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: content.minY),
                                  to:   CGPoint(x: x, y: content.maxY),
                                  color: EFColor.crosshair, lineWidth: 0.5)
        }
    }

    // MARK: ── MACD 副图（通用，K线也复用） ───────────────────

    func drawMACDSub(ctx: CGContext, result: EFMACDResult, count: Int, total: Int,
                      content: CGRect, crosshairIdx: Int?) {
        let allVals = result.dif + result.dea + result.bar
        guard !allVals.isEmpty else { return }
        let absMax = allVals.map(abs).max() ?? 1
        let range  = -absMax * 1.1...absMax * 1.1
        let map    = EFCoordMap(rect: content, minV: range.lowerBound, maxV: range.upperBound)
        let slotW  = content.width / CGFloat(total)
        let barW   = Swift.max(1, slotW * 0.7)
        let zeroY  = map.y(0)

        // MACD 柱
        let upP = CGMutablePath(), dnP = CGMutablePath()
        for i in 0..<count {
            let v = result.bar[i]
            let x = content.minX + (CGFloat(i) + 0.5) * slotW
            let y = map.y(v)
            let r = CGRect(x: x - barW/2, y: Swift.min(y, zeroY),
                            width: barW, height: abs(y - zeroY))
            if v >= 0 { upP.addRect(r) } else { dnP.addRect(r) }
        }
        ctx.addPath(upP); ctx.setFillColor(EFColor.macdBarUp.withAlphaComponent(0.85).cgColor); ctx.fillPath()
        ctx.addPath(dnP); ctx.setFillColor(EFColor.macdBarDown.withAlphaComponent(0.85).cgColor); ctx.fillPath()

        // 零轴虚线
        ctx.strokeDashedLine(from: CGPoint(x: content.minX, y: zeroY),
                              to:   CGPoint(x: content.maxX, y: zeroY),
                              color: EFColor.grid, lineWidth: 0.3, dash: [2, 2])

        // DIF / DEA 线
        func polyLine(_ vals: [Double], color: UIColor) {
            let pts: [CGPoint?] = vals.enumerated().map { i, v in
                i < count ? CGPoint(x: content.minX + CGFloat(i) * slotW, y: map.y(v)) : nil
            }
            ctx.strokePolyline(points: pts, color: color, lineWidth: 1.0)
        }
        polyLine(Array(result.dif.prefix(count)), color: EFColor.difLine)
        polyLine(Array(result.dea.prefix(count)), color: EFColor.deaLine)

        // 十字线竖延伸
        if let idx = crosshairIdx, idx < count {
            let x = content.minX + CGFloat(idx) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: content.minY),
                                  to:   CGPoint(x: x, y: content.maxY),
                                  color: EFColor.crosshair, lineWidth: 0.5)
        }

        // 图例
        let dif = result.dif.indices.contains(Swift.max(0, count-1)) ? result.dif[count-1] : 0
        let dea = result.dea.indices.contains(Swift.max(0, count-1)) ? result.dea[count-1] : 0
        let bar = result.bar.indices.contains(Swift.max(0, count-1)) ? result.bar[count-1] : 0
        let legend = "DIF:\(EFFormat.price(dif, decimals: 3))  DEA:\(EFFormat.price(dea, decimals: 3))  M:\(EFFormat.price(bar, decimals: 3))"
        ctx.drawString(legend, at: CGPoint(x: content.minX + 4, y: content.minY + 7),
                        font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
    }

    // MARK: ── 工具 ───────────────────────────────────────────

    func mainContentRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: rect.minY + EFLayout.topPad,
               width: rect.width - EFLayout.priceAxisW,
               height: rect.height - EFLayout.topPad - EFLayout.timeAxisH)
    }

    func subContentRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: rect.minY + EFLayout.subDivider,
               width: rect.width - EFLayout.priceAxisW,
               height: rect.height - EFLayout.subDivider - EFLayout.timeAxisH)
    }

    private func priceDecimalPlaces(_ price: Double) -> Int {
        price < 10 ? 3 : 2
    }

    static func totalSlots(for period: EFChartPeriod) -> Int {
        switch period {
        case .timeline: return 240     // 09:30–11:30 + 13:00–15:00 = 240 min
        case .fiveDay:  return 1200    // 5 * 240
        default:        return 240
        }
    }

    static func timeTicks(for period: EFChartPeriod) -> [(String, CGFloat)] {
        switch period {
        case .timeline:
            return [("09:30", 0), ("11:30/13:00", 0.5), ("15:00", 1.0)]
        case .fiveDay:
            return [("", 0), ("", 0.2), ("", 0.4), ("", 0.6), ("", 0.8), ("", 1.0)]
        default:
            return [("09:30", 0), ("15:00", 1.0)]
        }
    }

    // MARK: ── Tooltip（通用） ────────────────────────────────

    func drawTooltip(ctx: CGContext, rows: [(String, String, UIColor)],
                      at pt: CGPoint, content: CGRect) {
        let pad: CGFloat = 6, lh: CGFloat = 16
        let lw: CGFloat = 36, vw: CGFloat = 90
        let tw = pad*2 + lw + vw, th = pad*2 + CGFloat(rows.count) * lh

        let tx = pt.x + tw + 8 <= content.maxX ? pt.x + 6 : pt.x - tw - 6
        let ty = Swift.max(content.minY + 4, Swift.min(content.maxY - th - 4, pt.y - th/2))
        let tr = CGRect(x: tx, y: ty, width: tw, height: th)

        ctx.fillRoundedRect(tr, radius: 4, color: EFColor.tooltipBg)
        ctx.setStrokeColor(EFColor.tooltipBorder.cgColor); ctx.setLineWidth(0.5)
        ctx.stroke(tr)

        for (i, (label, value, vc)) in rows.enumerated() {
            let ry = ty + pad + CGFloat(i) * lh + lh/2
            ctx.drawString(label, at: CGPoint(x: tx+pad, y: ry),
                            font: EFLayout.tooltipFont, color: EFColor.textSecondary, align: .left)
            ctx.drawString(value, at: CGPoint(x: tx+tw-pad, y: ry),
                            font: EFLayout.tooltipFont, color: vc, align: .right)
        }
    }
}

//private extension CGRect {
//    func withOrigin(_ o: CGPoint) -> CGRect { CGRect(origin: o, size: size) }
//}
