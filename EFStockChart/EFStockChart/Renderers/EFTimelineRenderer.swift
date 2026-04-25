//
//  EFTimelineRenderer.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 分时图渲染器 
// 规则：
//   - mainImageView.bounds 就是渲染区域，infoBar 是独立 UIView 不参与计算
//   - 每个子面板的 imageView.bounds 就是副图渲染区域（titleBar 已在 UIView 层）
//   - 副图顶部 16pt 保留给图例文字，图例画在 content 上方不与图表重叠
//   - 分时/K线双模式均使用 visibleRange 控制副图同步

import UIKit
import CoreGraphics

// MARK: - 渲染结果（供 StockChartView 直接使用）

struct EFRenderResult {
    let mainImage:  CGImage?
    let subImages:  [(imageView: UIImageView, image: CGImage)]
}

// MARK: - 分时图渲染器

final class EFTimelineRenderer {

    private let scale: CGFloat

    init(scale: CGFloat = UIScreen.main.scale) {
        self.scale = scale
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 公开入口
    // ─────────────────────────────────────────────────────────────

    /// 渲染主图（分时价格线 + 均价线 + 指数家数柱 + 网格）
    func renderMain(data: EFTimelineData, rect: CGRect, crosshairIdx: Int?) -> CGImage? {
        guard let ctx = makeCtx(rect.size) else { return nil }
        drawTimelineMain(ctx: ctx, data: data,
                         rect: CGRect(origin: .zero, size: rect.size),
                         crosshairIdx: crosshairIdx)
        return ctx.makeImage()
    }

    /// 渲染单个副图（MACD / VOL）
    /// - rect: imageView.bounds（不含 titleBar）
    func renderSub(data: EFTimelineData,
                   indicator: EFSubIndicator,
                   rect: CGRect,
                   crosshairIdx: Int?) -> CGImage? {
        guard let ctx = makeCtx(rect.size) else { return nil }
        let r = CGRect(origin: .zero, size: rect.size)
        ctx.setFillColor(EFColor.panel.cgColor); ctx.fill(r)
        switch indicator {
        case .macd:   drawTimelineMACDSub(ctx: ctx, data: data, rect: r, crosshairIdx: crosshairIdx)
        case .volume: drawTimelineVolumeSub(ctx: ctx, data: data, rect: r, crosshairIdx: crosshairIdx)
        default: break
        }
        return ctx.makeImage()
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 主图绘制
    // ─────────────────────────────────────────────────────────────

    private func drawTimelineMain(ctx: CGContext,
                                  data: EFTimelineData,
                                  rect: CGRect,
                                  crosshairIdx: Int?) {
        let pts    = data.points
        let total  = EFTimelineRenderer.totalSlots(for: data.period)
        let cr     = mainContentRect(rect)  // chart 内容区域
        let pRange = data.priceRange

        // 背景
        ctx.setFillColor(EFColor.panel.cgColor); ctx.fill(rect)

        // 指数：内嵌涨跌家数柱（画在主图底部 30%，在价格线之前）
        if data.securityType == .index {
            drawIndexAdvancerBars(ctx: ctx, pts: pts, total: total, cr: cr)
        }

        // 网格 + 轴标签
        drawTimelineGrid(ctx: ctx, rect: rect, cr: cr, data: data, pRange: pRange)

        // 昨收虚线
        let prevY = yFor(price: data.prevClose, range: pRange, rect: cr)
        ctx.strokeDashedLine(from: CGPoint(x: cr.minX, y: prevY),
                             to:   CGPoint(x: cr.maxX, y: prevY),
                             color: EFColor.prevClose, lineWidth: 0.5)

        guard pts.count >= 2 else { return }

        // 渐变填充
        drawTimelineGradient(ctx: ctx, pts: pts, total: total, cr: cr, pRange: pRange)

        // 价格折线
        drawTimelinePriceLine(ctx: ctx, pts: pts, total: total, cr: cr, pRange: pRange)

        // 均价线
        drawTimelineAvgLine(ctx: ctx, pts: pts, total: total, cr: cr, pRange: pRange)

        // 十字线（最后绘制，在最上层）
        if let idx = crosshairIdx, pts.indices.contains(idx) {
            drawTimelineCrosshair(ctx: ctx, idx: idx, pts: pts,
                                  total: total, rect: rect, cr: cr,
                                  pRange: pRange, data: data)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 指数内嵌涨跌柱
    // ─────────────────────────────────────────────────────────────

    private func drawIndexAdvancerBars(ctx: CGContext,
                                       pts: [EFTimePoint],
                                       total: Int,
                                       cr: CGRect) {
        guard !pts.isEmpty else { return }
        let zoneH  = cr.height * 0.30
        let zoneY  = cr.maxY - zoneH
        let slotW  = cr.width / CGFloat(total)
        let barW   = Swift.max(1, slotW * 0.8)
        let maxAdv = pts.compactMap(\.advancers).max().map(Double.init) ?? 1
        let maxDec = pts.compactMap(\.decliners).max().map(Double.init) ?? 1

        let advPath = CGMutablePath(), decPath = CGMutablePath()
        for (i, p) in pts.enumerated() {
            let x = cr.minX + (CGFloat(i) + 0.5) * slotW
            if let adv = p.advancers, adv > 0 {
                let h = zoneH * CGFloat(Double(adv) / maxAdv)
                advPath.addRect(CGRect(x: x - barW/2, y: zoneY + zoneH - h, width: barW, height: h))
            }
            if let dec = p.decliners, dec > 0 {
                let h = zoneH * CGFloat(Double(dec) / maxDec)
                decPath.addRect(CGRect(x: x - barW/2, y: zoneY + zoneH - h, width: barW, height: h))
            }
        }
        ctx.addPath(advPath); ctx.setFillColor(EFColor.indexAdvancer.cgColor); ctx.fillPath()
        ctx.addPath(decPath); ctx.setFillColor(EFColor.indexDecliner.cgColor); ctx.fillPath()
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 网格 + 轴标签
    // ─────────────────────────────────────────────────────────────

    private func drawTimelineGrid(ctx: CGContext, rect: CGRect, cr: CGRect,
                                  data: EFTimelineData,
                                  pRange: ClosedRange<Double>) {
        let rows  = 5
        let span  = pRange.upperBound - pRange.lowerBound
        let dec   = data.prevClose < 10 ? 3 : 2

        // 水平网格 + 右侧价格/涨跌幅标签
        for i in 0..<rows {
            let ratio = Double(i) / Double(rows - 1)
            let price = pRange.upperBound - ratio * span
            let y     = cr.minY + CGFloat(ratio) * cr.height
            let pct   = (price - data.prevClose) / data.prevClose * 100

            ctx.strokeLine(from: CGPoint(x: cr.minX, y: y),
                           to:   CGPoint(x: cr.maxX, y: y),
                           color: EFColor.grid, lineWidth: 0.5)

            let pColor: UIColor = pct > 0.001 ? EFColor.rising :
                                  pct < -0.001 ? EFColor.falling : EFColor.textSecondary
            ctx.drawString(EFFormat.price(price, decimals: dec),
                           at: CGPoint(x: cr.maxX + 3, y: y),
                           font: EFLayout.axisFont, color: pColor, align: .left)

            // 左侧涨跌幅（指数不显示）
            if data.securityType != .index {
                ctx.drawString(EFFormat.percent(pct, signed: true),
                               at: CGPoint(x: cr.minX + 2, y: y),
                               font: EFLayout.axisFont, color: pColor, align: .left)
            }
        }

        // 垂直网格 + 底部时间标签
        let ticks = EFTimelineRenderer.timeTicks(for: data.period)
        let labelY = cr.maxY + EFLayout.timeAxisH / 2
        for (label, ratio) in ticks {
            let x = cr.minX + ratio * cr.width
            if ratio > 0 && ratio < 1 {
                ctx.strokeLine(from: CGPoint(x: x, y: cr.minY),
                               to:   CGPoint(x: x, y: cr.maxY),
                               color: EFColor.grid, lineWidth: 0.5)
            }
            let align: NSTextAlignment = ratio < 0.1 ? .left : ratio > 0.9 ? .right : .center
            let lx = ratio < 0.1 ? cr.minX : ratio > 0.9 ? cr.maxX : x
            ctx.drawString(label, at: CGPoint(x: lx, y: labelY),
                           font: EFLayout.axisFont, color: EFColor.textSecondary, align: align)
        }

        // 边框
        ctx.setStrokeColor(EFColor.border.cgColor); ctx.setLineWidth(0.5); ctx.stroke(cr)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 分时线 + 渐变 + 均价
    // ─────────────────────────────────────────────────────────────

    private func drawTimelineGradient(ctx: CGContext, pts: [EFTimePoint],
                                      total: Int, cr: CGRect,
                                      pRange: ClosedRange<Double>) {
        let slotW = cr.width / CGFloat(total)
        let path  = CGMutablePath()
        for (i, p) in pts.enumerated() {
            let x = cr.minX + CGFloat(i) * slotW
            let y = yFor(price: p.price, range: pRange, rect: cr)
            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        let lastX = cr.minX + CGFloat(pts.count - 1) * slotW
        path.addLine(to: CGPoint(x: lastX,    y: cr.maxY))
        path.addLine(to: CGPoint(x: cr.minX,  y: cr.maxY))
        path.closeSubpath()

        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        let colors = [EFColor.timelineFillTop.cgColor,
                      EFColor.timelineFillBot.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                start: CGPoint(x: cr.midX, y: cr.minY),
                end:   CGPoint(x: cr.midX, y: cr.maxY), options: [])
        }
        ctx.restoreGState()
    }

    private func drawTimelinePriceLine(ctx: CGContext, pts: [EFTimePoint],
                                       total: Int, cr: CGRect,
                                       pRange: ClosedRange<Double>) {
        let slotW = cr.width / CGFloat(total)
        let ps: [CGPoint?] = pts.enumerated().map { i, p in
            CGPoint(x: cr.minX + CGFloat(i) * slotW,
                    y: yFor(price: p.price, range: pRange, rect: cr))
        }
        ctx.strokePolyline(points: ps, color: EFColor.timelineMain, lineWidth: 1.5)
    }

    private func drawTimelineAvgLine(ctx: CGContext, pts: [EFTimePoint],
                                     total: Int, cr: CGRect,
                                     pRange: ClosedRange<Double>) {
        let slotW = cr.width / CGFloat(total)
        let ps: [CGPoint?] = pts.enumerated().map { i, p in
            CGPoint(x: cr.minX + CGFloat(i) * slotW,
                    y: yFor(price: p.avgPrice, range: pRange, rect: cr))
        }
        ctx.strokePolyline(points: ps, color: EFColor.timelineAvg, lineWidth: 1.0)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 十字线
    // ─────────────────────────────────────────────────────────────

    private func drawTimelineCrosshair(ctx: CGContext, idx: Int,
                                       pts: [EFTimePoint], total: Int,
                                       rect: CGRect, cr: CGRect,
                                       pRange: ClosedRange<Double>,
                                       data: EFTimelineData) {
        let p     = pts[idx]
        let slotW = cr.width / CGFloat(total)
        let x     = cr.minX + CGFloat(idx) * slotW
        let y     = yFor(price: p.price, range: pRange, rect: cr)

        ctx.strokeDashedLine(from: CGPoint(x: cr.minX, y: y),
                             to:   CGPoint(x: cr.maxX, y: y), color: EFColor.crosshair)
        ctx.strokeDashedLine(from: CGPoint(x: x, y: cr.minY),
                             to:   CGPoint(x: x, y: cr.maxY), color: EFColor.crosshair)

        let r: CGFloat = 3
        ctx.setFillColor(EFColor.timelineMain.cgColor)
        ctx.fillEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))

        let dec = data.prevClose < 10 ? 3 : 2
        let pColor = p.changePercent >= 0 ? EFColor.rising : EFColor.falling
        ctx.drawLabelBadge(EFFormat.price(p.price, decimals: dec),
                           at: CGPoint(x: cr.maxX + 1, y: y),
                           font: EFLayout.axisFont, fg: .white, bg: pColor)
        ctx.drawLabelBadge(EFFormat.time(p.time),
                           at: CGPoint(x: x, y: cr.maxY + EFLayout.timeAxisH/2),
                           font: EFLayout.axisFont, fg: EFColor.background, bg: EFColor.crosshairLabel)

        drawTooltip(ctx: ctx, rows: [
            ("时间", EFFormat.full(p.time),                              EFColor.textPrimary),
            ("价格", EFFormat.price(p.price, decimals: dec),              pColor),
            ("均价", EFFormat.price(p.avgPrice, decimals: dec),           EFColor.timelineAvg),
            ("涨跌", EFFormat.percent(p.changePercent, signed: true),     pColor),
            ("成交", EFFormat.volume(p.volume),                           EFColor.textPrimary),
            ("金额", EFFormat.amount(p.amount),                           EFColor.textPrimary),
        ], at: CGPoint(x: x, y: y), cr: cr)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 副图：MACD（分时）
    // ─────────────────────────────────────────────────────────────

    private func drawTimelineMACDSub(ctx: CGContext, data: EFTimelineData,
                                     rect: CGRect, crosshairIdx: Int?) {
        let closes = data.points.map(\.price)
        guard closes.count > 26 else {
            drawSubBorder(ctx: ctx, rect: rect)
            return
        }
        let macd   = EFIndicatorEngine.macd(closes: closes)
        let total  = EFTimelineRenderer.totalSlots(for: data.period)
        let cr     = subContentRect(rect)   // 图表区域（顶部留图例空间）

        drawMACDContent(ctx: ctx, macd: macd,
                        visRange: 0..<closes.count,
                        total: total, cr: cr, crosshairIdx: crosshairIdx)
        drawSubBorder(ctx: ctx, rect: rect)

        // 图例（画在 imageView 顶部，content 上方）
        let lastI = closes.count - 1
        let legend = makeMACDLegend(macd: macd, idx: lastI)
        ctx.drawString(legend, at: CGPoint(x: rect.minX + 4, y: rect.minY + 10),
                       font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 副图：成交量（分时）
    // ─────────────────────────────────────────────────────────────

    private func drawTimelineVolumeSub(ctx: CGContext, data: EFTimelineData,
                                       rect: CGRect, crosshairIdx: Int?) {
        let pts   = data.points
        guard !pts.isEmpty else { drawSubBorder(ctx: ctx, rect: rect); return }

        let total  = EFTimelineRenderer.totalSlots(for: data.period)
        let cr     = subContentRect(rect)
        let maxVol = pts.map(\.volume).max() ?? 1
        let slotW  = cr.width / CGFloat(total)
        let barW   = Swift.max(1, slotW * 0.8)

        ctx.saveGState(); ctx.clip(to: cr)
        let upPath = CGMutablePath(), dnPath = CGMutablePath()
        for (i, p) in pts.enumerated() {
            let x = cr.minX + (CGFloat(i) + 0.5) * slotW
            let h = cr.height * CGFloat(p.volume / maxVol)
            let r = CGRect(x: x - barW/2, y: cr.maxY - h, width: barW, height: h)
            p.changePercent >= 0 ? upPath.addRect(r) : dnPath.addRect(r)
        }
        ctx.addPath(upPath); ctx.setFillColor(EFColor.rising.withAlphaComponent(0.85).cgColor); ctx.fillPath()
        ctx.addPath(dnPath); ctx.setFillColor(EFColor.falling.withAlphaComponent(0.85).cgColor); ctx.fillPath()

        // 十字竖线
        if let ci = crosshairIdx, pts.indices.contains(ci) {
            let x = cr.minX + CGFloat(ci) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: cr.minY),
                                 to:   CGPoint(x: x, y: cr.maxY), color: EFColor.crosshair)
        }
        ctx.restoreGState()

        drawSubBorder(ctx: ctx, rect: rect)
        let legend = "成交量 \(EFFormat.volume(maxVol))"
        ctx.drawString(legend, at: CGPoint(x: rect.minX + 4, y: rect.minY + 10),
                       font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 公用 MACD 内容绘制（K线也复用）
    // ─────────────────────────────────────────────────────────────

    /// 只画 MACD 柱 + DIF/DEA 线，不画图例、不画边框
    func drawMACDContent(ctx: CGContext, macd: EFMACDResult,
                         visRange: Range<Int>, total: Int,
                         cr: CGRect, crosshairIdx: Int?) {
        let visBar = Array(macd.bar[clampRange(visRange, count: macd.bar.count)])
        let visDif = Array(macd.dif[clampRange(visRange, count: macd.dif.count)])
        let visDea = Array(macd.dea[clampRange(visRange, count: macd.dea.count)])
        let allV   = visBar + visDif + visDea
        guard !allV.isEmpty else { return }

        let absMax = allV.map(abs).max() ?? 1
        let pRange = (-absMax * 1.15)...(absMax * 1.15)
        let slotW  = cr.width / CGFloat(visRange.count > 0 ? visRange.count : total)
        let barW   = Swift.max(1, slotW * 0.7)
        let zeroY  = yFor(price: 0, range: pRange, rect: cr)

        ctx.saveGState(); ctx.clip(to: cr)

        let upP = CGMutablePath(), dnP = CGMutablePath()
        for (li, v) in visBar.enumerated() {
            let x = cr.minX + (CGFloat(li) + 0.5) * slotW
            let y = yFor(price: v, range: pRange, rect: cr)
            let r = CGRect(x: x - barW/2, y: Swift.min(y, zeroY),
                           width: barW, height: abs(y - zeroY))
            v >= 0 ? upP.addRect(r) : dnP.addRect(r)
        }
        ctx.addPath(upP); ctx.setFillColor(EFColor.macdBarUp.withAlphaComponent(0.85).cgColor); ctx.fillPath()
        ctx.addPath(dnP); ctx.setFillColor(EFColor.macdBarDown.withAlphaComponent(0.85).cgColor); ctx.fillPath()

        ctx.strokeDashedLine(from: CGPoint(x: cr.minX, y: zeroY),
                             to:   CGPoint(x: cr.maxX, y: zeroY),
                             color: EFColor.grid, lineWidth: 0.3, dash: [2, 2])

        func line(_ vals: [Double], color: UIColor) {
            let ps: [CGPoint?] = vals.enumerated().map { li, v in
                CGPoint(x: cr.minX + CGFloat(li) * slotW, y: yFor(price: v, range: pRange, rect: cr))
            }
            ctx.strokePolyline(points: ps, color: color, lineWidth: 1.0)
        }
        line(visDif, color: EFColor.difLine)
        line(visDea, color: EFColor.deaLine)

        if let ci = crosshairIdx {
            let localI: Int?
            if visRange.count > 0 {
                localI = visRange.contains(ci) ? ci - visRange.lowerBound : nil
            } else {
                localI = ci < macd.bar.count ? ci : nil
            }
            if let li = localI {
                let x = cr.minX + (CGFloat(li) + 0.5) * slotW
                ctx.strokeDashedLine(from: CGPoint(x: x, y: cr.minY),
                                     to:   CGPoint(x: x, y: cr.maxY), color: EFColor.crosshair)
            }
        }
        ctx.restoreGState()
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Tooltip（通用）
    // ─────────────────────────────────────────────────────────────

    func drawTooltip(ctx: CGContext,
                     rows: [(String, String, UIColor)],
                     at pt: CGPoint, cr: CGRect) {
        let pad: CGFloat = 6, lh: CGFloat = 16
        let lw: CGFloat  = 36, vw: CGFloat = 90
        let tw = pad*2 + lw + vw
        let th = pad*2 + CGFloat(rows.count) * lh

        var tx: CGFloat
        if pt.x + 8 + tw <= cr.maxX { tx = pt.x + 8 }
        else if pt.x - 8 - tw >= cr.minX { tx = pt.x - 8 - tw }
        else { tx = pt.x + 8 }
        tx = Swift.max(cr.minX + 2, Swift.min(cr.maxX - tw - 2, tx))
        var ty = pt.y - th / 2
        ty = Swift.max(cr.minY + 2, Swift.min(cr.maxY - th - 2, ty))

        let tr = CGRect(x: tx, y: ty, width: tw, height: th)
        ctx.fillRoundedRect(tr, radius: 4, color: EFColor.tooltipBg)
        ctx.setStrokeColor(EFColor.tooltipBorder.cgColor)
        ctx.setLineWidth(0.5); ctx.stroke(tr)

        for (i, (label, value, vc)) in rows.enumerated() {
            let ry = ty + pad + CGFloat(i) * lh + lh/2
            ctx.drawString(label, at: CGPoint(x: tx+pad, y: ry),
                           font: EFLayout.tooltipFont, color: EFColor.textSecondary, align: .left)
            ctx.drawString(value, at: CGPoint(x: tx+tw-pad, y: ry),
                           font: EFLayout.tooltipFont, color: vc, align: .right)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 工具方法（公开，供 KLineRenderer 复用）
    // ─────────────────────────────────────────────────────────────

    /// 主图内容区域：rect 即 mainImageView.bounds，只留顶部 topPad 和底部 timeAxisH
    func mainContentRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: rect.minY + EFLayout.topPad,
               width: rect.width - EFLayout.priceAxisW,
               height: rect.height - EFLayout.topPad - EFLayout.timeAxisH)
    }

    /// 副图内容区域：顶部 16pt 留给图例，底部 2pt 留空
    func subContentRect(_ rect: CGRect) -> CGRect {
        let labelH: CGFloat = 16
        return CGRect(x: rect.minX,
                      y: rect.minY + labelH,
                      width: rect.width - EFLayout.priceAxisW,
                      height: rect.height - labelH - 2)
    }

    func yFor(price: Double, range: ClosedRange<Double>, rect: CGRect) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return rect.midY }
        let ratio = CGFloat((price - range.lowerBound) / span)
        return rect.maxY - ratio * rect.height
    }

    func clampRange(_ r: Range<Int>, count: Int) -> Range<Int> {
        let s = Swift.max(0, r.lowerBound)
        let e = Swift.min(count, r.upperBound)
        return s < e ? s..<e : 0..<Swift.min(1, count)
    }

    func makeMACDLegend(macd: EFMACDResult, idx: Int) -> String {
        let i   = Swift.min(idx, macd.bar.count - 1)
        let dif = i >= 0 && i < macd.dif.count ? macd.dif[i] : 0
        let dea = i >= 0 && i < macd.dea.count ? macd.dea[i] : 0
        let bar = i >= 0 && i < macd.bar.count ? macd.bar[i] : 0
        return "DIF:\(EFFormat.price(dif, decimals: 3))  DEA:\(EFFormat.price(dea, decimals: 3))  M:\(EFFormat.price(bar, decimals: 3))"
    }

    private func drawSubBorder(ctx: CGContext, rect: CGRect) {
        ctx.setStrokeColor(EFColor.border.cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(subContentRect(rect))
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 静态工具
    // ─────────────────────────────────────────────────────────────

    static func totalSlots(for period: EFChartPeriod) -> Int {
        switch period {
        case .fiveDay: return 1200
        default:       return 240
        }
    }

    static func timeTicks(for period: EFChartPeriod) -> [(String, CGFloat)] {
        switch period {
        case .fiveDay:
            return [("", 0), ("", 0.2), ("", 0.4), ("", 0.6), ("", 0.8), ("", 1.0)]
        default:
            return [("09:30", 0), ("11:30/13:00", 0.5), ("15:00", 1.0)]
        }
    }

    private func makeCtx(_ size: CGSize) -> CGContext? {
        makeOffscreenContext(size: size, scale: scale)
    }
}
