//
//  EFKLineRenderer.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// K线图渲染器 
// 规则：
//   - mainImageView.bounds → mainContentRect (仅减 topPad + timeAxisH，不减 infoBarH)
//   - 副图 imageView.bounds → subContentRect (顶部 16pt 图例 + 底部 2pt)
//   - 所有绘制内容均 clip 到 content 区域内，不超出边界
//   - MACD 图例只画一次（由 KLineRenderer 在 content 上方绘制）

import UIKit
import CoreGraphics

final class EFKLineRenderer {

    private let scale: CGFloat
    private let tlR: EFTimelineRenderer   // 复用 MACD 内容 + Tooltip + 工具方法

    init(scale: CGFloat = UIScreen.main.scale) {
        self.scale = scale
        self.tlR   = EFTimelineRenderer(scale: scale)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 公开入口
    // ─────────────────────────────────────────────────────────────

    /// 渲染主图（蜡烛 + MA 线 + 网格 + 十字线）
    func renderMain(data: EFKLineData,
                    rect: CGRect,
                    visibleRange: Range<Int>,
                    crosshairIdx: Int?,
                    candleWidth: CGFloat) -> CGImage? {
        guard let ctx = makeCtx(rect.size) else { return nil }
        drawMain(ctx: ctx, data: data,
                 rect: CGRect(origin: .zero, size: rect.size),
                 vis: visibleRange, ci: crosshairIdx, cw: candleWidth)
        return ctx.makeImage()
    }

    /// 渲染副图（imageView.bounds 传入）
    func renderSub(data: EFKLineData,
                   subIndex: Int,
                   rect: CGRect,
                   visibleRange: Range<Int>,
                   candleWidth: CGFloat,
                   crosshairIdx: Int?) -> CGImage? {
        guard subIndex < data.subData.count,
              let ctx = makeCtx(rect.size) else { return nil }
        let r = CGRect(origin: .zero, size: rect.size)
        ctx.setFillColor(EFColor.panel.cgColor); ctx.fill(r)
        drawSub(ctx: ctx, data: data, subIndex: subIndex,
                rect: r, vis: visibleRange, cw: candleWidth, ci: crosshairIdx)
        return ctx.makeImage()
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 主图绘制
    // ─────────────────────────────────────────────────────────────

    private func drawMain(ctx: CGContext, data: EFKLineData,
                          rect: CGRect, vis: Range<Int>,
                          ci: Int?, cw: CGFloat) {
        ctx.setFillColor(EFColor.panel.cgColor); ctx.fill(rect)
        guard !data.candles.isEmpty else { return }

        let safeVis = tlR.clampRange(vis, count: data.candles.count)
        let visC    = Array(data.candles[safeVis])
        let pRange  = computePriceRange(candles: visC, maData: data.maResults, vis: safeVis)
        let cr      = mainContentRect(rect)

        drawPriceGrid(ctx: ctx, rect: rect, cr: cr, pRange: pRange)

        // ── 蜡烛 + MA 均线：clip 到 cr，防止超出右边界
        ctx.saveGState()
        ctx.clip(to: cr)
        drawCandles(ctx: ctx, candles: visC, vis: safeVis, cr: cr, pRange: pRange, cw: cw)
        drawMALines(ctx: ctx, maData: data.maResults, vis: safeVis, cr: cr, pRange: pRange, cw: cw)
        ctx.restoreGState()

        drawTimeAxis(ctx: ctx, candles: visC, vis: safeVis, rect: rect, cr: cr, period: data.period)

        if let idx = ci, safeVis.contains(idx) {
            drawCrosshair(ctx: ctx, idx: idx, data: data, vis: safeVis,
                          rect: rect, cr: cr, pRange: pRange, cw: cw)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 蜡烛图（批量路径）
    // ─────────────────────────────────────────────────────────────

    private func drawCandles(ctx: CGContext, candles: [EFKLinePoint],
                              vis: Range<Int>, cr: CGRect,
                              pRange: ClosedRange<Double>, cw: CGFloat) {
        let slotW = cr.width / CGFloat(vis.count)
        let bodyW = Swift.max(1, slotW * (1 - EFLayout.candleGap))

        let rB = CGMutablePath(), fB = CGMutablePath()
        let rW = CGMutablePath(), fW = CGMutablePath()
        let dP = CGMutablePath()

        for (li, c) in candles.enumerated() {
            let x      = cr.minX + (CGFloat(li) + 0.5) * slotW
            let openY  = tlR.yFor(price: c.open,  range: pRange, rect: cr)
            let closeY = tlR.yFor(price: c.close, range: pRange, rect: cr)
            let highY  = tlR.yFor(price: c.high,  range: pRange, rect: cr)
            let lowY   = tlR.yFor(price: c.low,   range: pRange, rect: cr)
            let bTop   = Swift.min(openY, closeY)
            let bH     = Swift.max(1, abs(closeY - openY))
            let body   = CGRect(x: x - bodyW/2, y: bTop, width: bodyW, height: bH)

            if c.isBullish {
                rB.addRect(body)
                rW.move(to: CGPoint(x: x, y: highY));  rW.addLine(to: CGPoint(x: x, y: bTop))
                rW.move(to: CGPoint(x: x, y: bTop+bH)); rW.addLine(to: CGPoint(x: x, y: lowY))
            } else if c.close < c.open {
                fB.addRect(body)
                fW.move(to: CGPoint(x: x, y: highY));  fW.addLine(to: CGPoint(x: x, y: bTop))
                fW.move(to: CGPoint(x: x, y: bTop+bH)); fW.addLine(to: CGPoint(x: x, y: lowY))
            } else {
                dP.move(to: CGPoint(x: x - bodyW/2, y: openY))
                dP.addLine(to: CGPoint(x: x + bodyW/2, y: openY))
                dP.move(to: CGPoint(x: x, y: highY)); dP.addLine(to: CGPoint(x: x, y: lowY))
            }
        }

        ctx.addPath(rB); ctx.setFillColor(EFColor.rising.cgColor);   ctx.fillPath()
        ctx.addPath(fB); ctx.setFillColor(EFColor.falling.cgColor);  ctx.fillPath()
        ctx.setLineWidth(0.8)
        ctx.addPath(rW); ctx.setStrokeColor(EFColor.rising.cgColor); ctx.strokePath()
        ctx.addPath(fW); ctx.setStrokeColor(EFColor.falling.cgColor); ctx.strokePath()
        ctx.addPath(dP); ctx.setStrokeColor(EFColor.neutral.cgColor); ctx.strokePath()
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - MA 均线
    // ─────────────────────────────────────────────────────────────

    private func drawMALines(ctx: CGContext, maData: [EFMAResult],
                              vis: Range<Int>, cr: CGRect,
                              pRange: ClosedRange<Double>, cw: CGFloat) {
        let slotW = cr.width / CGFloat(vis.count)
        for ma in maData {
            let pts: [CGPoint?] = vis.enumerated().map { li, gi in
                guard gi < ma.values.count, let v = ma.values[gi] else { return nil }
                return CGPoint(x: cr.minX + (CGFloat(li) + 0.5) * slotW,
                               y: tlR.yFor(price: v, range: pRange, rect: cr))
            }
            ctx.strokePolyline(points: pts, color: ma.color, lineWidth: 1.0)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 价格网格
    // ─────────────────────────────────────────────────────────────

    private func drawPriceGrid(ctx: CGContext, rect: CGRect,
                                cr: CGRect, pRange: ClosedRange<Double>) {
        let rows = 5
        let span = pRange.upperBound - pRange.lowerBound

        for i in 0..<rows {
            let ratio = Double(i) / Double(rows - 1)
            let price = pRange.upperBound - ratio * span
            let y     = cr.minY + CGFloat(ratio) * cr.height
            let dec   = price < 100 ? 3 : 2

            ctx.strokeLine(from: CGPoint(x: cr.minX, y: y),
                           to:   CGPoint(x: cr.maxX, y: y),
                           color: EFColor.grid, lineWidth: 0.5)
            ctx.drawString(EFFormat.price(price, decimals: dec),
                           at: CGPoint(x: cr.maxX + 3, y: y),
                           font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
        }

        // 4条垂直网格线
        for i in 1..<5 {
            let x = cr.minX + CGFloat(i) / 5.0 * cr.width
            ctx.strokeLine(from: CGPoint(x: x, y: cr.minY),
                           to:   CGPoint(x: x, y: cr.maxY),
                           color: EFColor.grid, lineWidth: 0.5)
        }
        ctx.setStrokeColor(EFColor.border.cgColor)
        ctx.setLineWidth(0.5); ctx.stroke(cr)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 时间轴
    // ─────────────────────────────────────────────────────────────

    private func drawTimeAxis(ctx: CGContext, candles: [EFKLinePoint],
                               vis: Range<Int>, rect: CGRect,
                               cr: CGRect, period: EFKPeriod) {
        guard candles.count >= 2 else { return }
        let slotW  = cr.width / CGFloat(candles.count)
        let ticks  = stride(from: 0, through: candles.count-1,
                            by: Swift.max(1, candles.count/4))
        let y      = cr.maxY + EFLayout.timeAxisH / 2

        for (idx, t) in ticks.enumerated() {
            let x     = cr.minX + (CGFloat(t) + 0.5) * slotW
            let label = period.isIntraday ? EFFormat.time(candles[t].time)
                                          : EFFormat.date(candles[t].time)
            let align: NSTextAlignment = idx == 0 ? .left : (t == candles.count-1 ? .right : .center)
            ctx.drawString(label, at: CGPoint(x: x, y: y),
                           font: EFLayout.axisFont, color: EFColor.textSecondary, align: align)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 十字线
    // ─────────────────────────────────────────────────────────────

    private func drawCrosshair(ctx: CGContext, idx: Int, data: EFKLineData,
                                vis: Range<Int>, rect: CGRect, cr: CGRect,
                                pRange: ClosedRange<Double>, cw: CGFloat) {
        let c     = data.candles[idx]
        let slotW = cr.width / CGFloat(vis.count)
        let li    = idx - vis.lowerBound
        let x     = cr.minX + (CGFloat(li) + 0.5) * slotW
        let y     = tlR.yFor(price: c.close, range: pRange, rect: cr)

        ctx.strokeDashedLine(from: CGPoint(x: cr.minX, y: y),
                             to:   CGPoint(x: cr.maxX, y: y), color: EFColor.crosshair)
        ctx.strokeDashedLine(from: CGPoint(x: x, y: cr.minY),
                             to:   CGPoint(x: x, y: cr.maxY), color: EFColor.crosshair)

        let pColor = c.isBullish ? EFColor.rising : EFColor.falling
        ctx.drawLabelBadge(EFFormat.price(c.close),
                           at: CGPoint(x: cr.maxX + 1, y: y),
                           font: EFLayout.axisFont, fg: .white, bg: pColor)
        ctx.drawLabelBadge(EFFormat.date(c.time),
                           at: CGPoint(x: x, y: cr.maxY + EFLayout.timeAxisH/2),
                           font: EFLayout.axisFont, fg: EFColor.background, bg: EFColor.crosshairLabel)

        tlR.drawTooltip(ctx: ctx, rows: [
            ("日期",  EFFormat.ymd(c.time),                          EFColor.textPrimary),
            ("开盘",  EFFormat.price(c.open),                        pColor),
            ("收盘",  EFFormat.price(c.close),                       pColor),
            ("最高",  EFFormat.price(c.high),                        EFColor.rising),
            ("最低",  EFFormat.price(c.low),                         EFColor.falling),
            ("成交量", EFFormat.volume(c.volume),                    EFColor.textPrimary),
            ("涨跌幅", EFFormat.percent(c.changePercent, signed: true), pColor),
        ], at: CGPoint(x: x, y: y), cr: cr)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 副图
    // ─────────────────────────────────────────────────────────────

    private func drawSub(ctx: CGContext, data: EFKLineData, subIndex: Int,
                          rect: CGRect, vis: Range<Int>, cw: CGFloat, ci: Int?) {
        let cr      = subContentRect(rect)
        let safeVis = tlR.clampRange(vis, count: data.candles.count)

        ctx.setStrokeColor(EFColor.border.cgColor)
        ctx.setLineWidth(0.5); ctx.stroke(cr)

        switch data.subData[subIndex] {
        case .macd(let md):
            tlR.drawMACDContent(ctx: ctx, macd: md, visRange: safeVis,
                                total: safeVis.count, cr: cr, crosshairIdx: ci)
            // 图例：画在 imageView 顶部（cr 上方，不重叠）
            let lastI  = safeVis.upperBound - 1
            let legend = tlR.makeMACDLegend(macd: md, idx: lastI)
            ctx.drawString(legend, at: CGPoint(x: rect.minX + 4, y: rect.minY + 10),
                           font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)

        case .kdj(let kd):
            drawKDJ(ctx: ctx, kd: kd, vis: safeVis, cr: cr, ci: ci)
            let gi    = safeVis.upperBound - 1
            drawSubLegend(ctx: ctx, rect: rect, text: "KDJ", vals: [
                ("K", gi < kd.k.count ? kd.k[gi] : nil, EFColor.kLine),
                ("D", gi < kd.d.count ? kd.d[gi] : nil, EFColor.dLine),
                ("J", gi < kd.j.count ? kd.j[gi] : nil, EFColor.jLine),
            ])

        case .volume(let vd):
            drawVolume(ctx: ctx, vd: vd, candles: data.candles, vis: safeVis, cr: cr, ci: ci)
            let gi     = safeVis.upperBound - 1
            let vol    = gi < vd.volumes.count ? vd.volumes[gi] : 0
            let ma1v   = gi < vd.ma1.count ? vd.ma1[gi] : nil
            let ma2v   = gi < vd.ma2.count ? vd.ma2[gi] : nil
            var legend = "成交量 \(EFFormat.volume(vol))"
            if let v = ma1v { legend += "  MA5:\(EFFormat.volume(v))" }
            if let v = ma2v { legend += "  MA10:\(EFFormat.volume(v))" }
            ctx.drawString(legend, at: CGPoint(x: rect.minX + 4, y: rect.minY + 10),
                           font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)

        case .rsi(let rds):
            drawRSI(ctx: ctx, rds: rds, vis: safeVis, cr: cr, ci: ci)
            let gi   = safeVis.upperBound - 1
            let vals = rds.enumerated().map { i, rd -> (String, Double?, UIColor) in
                let color = EFColor.rsiColors[Swift.min(i, EFColor.rsiColors.count - 1)]
                let val   = gi < rd.values.count ? rd.values[gi] : nil
                return ("RSI\(rd.period)", val, color)
            }
            drawSubLegend(ctx: ctx, rect: rect, text: "RSI", vals: vals)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - KDJ
    // ─────────────────────────────────────────────────────────────

    private func drawKDJ(ctx: CGContext, kd: EFKDJResult,
                          vis: Range<Int>, cr: CGRect, ci: Int?) {
        let visK = vis.compactMap { $0 < kd.k.count ? kd.k[$0] : nil }
        let visD = vis.compactMap { $0 < kd.d.count ? kd.d[$0] : nil }
        let visJ = vis.compactMap { $0 < kd.j.count ? kd.j[$0] : nil }
        let all  = visK + visD + visJ
        guard !all.isEmpty else { return }

        let rawMin = (all.min() ?? 0)
        let rawMax = (all.max() ?? 100)
        let pad    = (rawMax - rawMin) * 0.12
        let pRange = (Swift.min(rawMin - pad, 0))...(Swift.max(rawMax + pad, 100))
        let slotW  = cr.width / CGFloat(vis.count)

        ctx.saveGState(); ctx.clip(to: cr)

        for level in [20.0, 50.0, 80.0] {
            let y = tlR.yFor(price: level, range: pRange, rect: cr)
            ctx.strokeDashedLine(from: CGPoint(x: cr.minX, y: y),
                                 to:   CGPoint(x: cr.maxX, y: y),
                                 color: EFColor.grid, lineWidth: 0.3, dash: [2, 2])
        }

        func line(_ vals: [Double], color: UIColor) {
            let ps: [CGPoint?] = vis.enumerated().map { li, gi in
                guard gi < vals.count else { return nil }
                return CGPoint(x: cr.minX + (CGFloat(li) + 0.5) * slotW,
                               y: tlR.yFor(price: vals[gi], range: pRange, rect: cr))
            }
            ctx.strokePolyline(points: ps, color: color, lineWidth: 1.0)
        }
        line(kd.k, color: EFColor.kLine)
        line(kd.d, color: EFColor.dLine)
        line(kd.j, color: EFColor.jLine)
        ctx.restoreGState()

        // 右侧参考刻度（在 clip 外画，不被裁剪）
        for level in [20.0, 80.0] {
            let y = tlR.yFor(price: level, range: pRange, rect: cr)
            ctx.drawString("\(Int(level))", at: CGPoint(x: cr.maxX + 3, y: y),
                           font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
        }

        if let idx = ci, vis.contains(idx) {
            let x = cr.minX + (CGFloat(idx - vis.lowerBound) + 0.5) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: cr.minY),
                                 to:   CGPoint(x: x, y: cr.maxY), color: EFColor.crosshair)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 成交量
    // ─────────────────────────────────────────────────────────────

    private func drawVolume(ctx: CGContext, vd: EFVolumeResult,
                             candles: [EFKLinePoint], vis: Range<Int>,
                             cr: CGRect, ci: Int?) {
        let visVols = vis.compactMap { $0 < vd.volumes.count ? vd.volumes[$0] : nil }
        let maxVol  = visVols.max() ?? 1
        let slotW   = cr.width / CGFloat(vis.count)
        let bodyW   = Swift.max(1, slotW * (1 - EFLayout.candleGap))

        ctx.saveGState(); ctx.clip(to: cr)

        let upP = CGMutablePath(), dnP = CGMutablePath()
        for (li, gi) in vis.enumerated() {
            guard gi < vd.volumes.count else { continue }
            let v    = vd.volumes[gi]
            let bull = gi < vd.isBullish.count ? vd.isBullish[gi] : true
            let x    = cr.minX + (CGFloat(li) + 0.5) * slotW
            let h    = cr.height * CGFloat(v / maxVol)
            let r    = CGRect(x: x - bodyW/2, y: cr.maxY - h, width: bodyW, height: h)
            bull ? upP.addRect(r) : dnP.addRect(r)
        }
        ctx.addPath(upP); ctx.setFillColor(EFColor.rising.withAlphaComponent(0.85).cgColor); ctx.fillPath()
        ctx.addPath(dnP); ctx.setFillColor(EFColor.falling.withAlphaComponent(0.85).cgColor); ctx.fillPath()

        // MA 线
        func volLine(_ vals: [Double?], color: UIColor) {
            let ps: [CGPoint?] = vis.enumerated().map { li, gi in
                guard gi < vals.count, let v = vals[gi] else { return nil }
                let y = cr.maxY - cr.height * CGFloat(v / maxVol)
                return CGPoint(x: cr.minX + (CGFloat(li) + 0.5) * slotW, y: y)
            }
            ctx.strokePolyline(points: ps, color: color, lineWidth: 1.0)
        }
        volLine(vd.ma1, color: EFColor.volMa1)
        volLine(vd.ma2, color: EFColor.volMa2)

        if let idx = ci, vis.contains(idx) {
            let x = cr.minX + (CGFloat(idx - vis.lowerBound) + 0.5) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: cr.minY),
                                 to:   CGPoint(x: x, y: cr.maxY), color: EFColor.crosshair)
        }
        ctx.restoreGState()
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - RSI
    // ─────────────────────────────────────────────────────────────

    private func drawRSI(ctx: CGContext, rds: [EFRSIResult],
                          vis: Range<Int>, cr: CGRect, ci: Int?) {
        guard !rds.isEmpty else { return }
        let pRange = 0.0...100.0
        let slotW  = cr.width / CGFloat(vis.count)

        ctx.saveGState(); ctx.clip(to: cr)

        for level in [30.0, 70.0] {
            let y = tlR.yFor(price: level, range: pRange, rect: cr)
            ctx.strokeDashedLine(from: CGPoint(x: cr.minX, y: y),
                                 to:   CGPoint(x: cr.maxX, y: y),
                                 color: EFColor.grid, lineWidth: 0.3, dash: [2, 2])
        }

        for (i, rd) in rds.enumerated() {
            let color = EFColor.rsiColors[Swift.min(i, EFColor.rsiColors.count - 1)]
            let ps: [CGPoint?] = vis.enumerated().map { li, gi in
                guard gi < rd.values.count else { return nil }
                return CGPoint(x: cr.minX + (CGFloat(li) + 0.5) * slotW,
                               y: tlR.yFor(price: rd.values[gi], range: pRange, rect: cr))
            }
            ctx.strokePolyline(points: ps, color: color, lineWidth: 1.0)
        }

        if let idx = ci, vis.contains(idx) {
            let x = cr.minX + (CGFloat(idx - vis.lowerBound) + 0.5) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: cr.minY),
                                 to:   CGPoint(x: x, y: cr.maxY), color: EFColor.crosshair)
        }
        ctx.restoreGState()
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 副图图例（统一画在 imageView 顶部 y=10）
    // ─────────────────────────────────────────────────────────────

    private func drawSubLegend(ctx: CGContext, rect: CGRect,
                                text: String,
                                vals: [(String, Double?, UIColor)]) {
        var x    = rect.minX + 4
        let y    = rect.minY + 10   // imageView 顶部，不与图表内容重叠

        ctx.drawString(text + " ", at: CGPoint(x: x, y: y),
                       font: EFLayout.infoFont, color: EFColor.textSecondary, align: .left)
        x += (text as NSString).size(withAttributes: [.font: EFLayout.infoFont]).width + 4

        for (label, val, color) in vals {
            guard let v = val else { continue }
            let s = "\(label):\(EFFormat.price(v, decimals: 2))  "
            ctx.drawString(s, at: CGPoint(x: x, y: y),
                           font: EFLayout.infoFont, color: color, align: .left)
            x += (s as NSString).size(withAttributes: [.font: EFLayout.infoFont]).width
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 工具方法
    // ─────────────────────────────────────────────────────────────

    func mainContentRect(_ rect: CGRect) -> CGRect {
        // rect = mainImageView.bounds；infoBar 是独立 UIView，不在这里减
        CGRect(x: rect.minX, y: rect.minY + EFLayout.topPad,
               width: rect.width - EFLayout.priceAxisW,
               height: rect.height - EFLayout.topPad - EFLayout.timeAxisH)
    }

    func subContentRect(_ rect: CGRect) -> CGRect {
        // rect = sub imageView.bounds；顶部 16pt 留图例，底部 2pt
        let labelH: CGFloat = 16
        return CGRect(x: rect.minX, y: rect.minY + labelH,
                      width: rect.width - EFLayout.priceAxisW,
                      height: rect.height - labelH - 2)
    }

    private func computePriceRange(candles: [EFKLinePoint],
                                    maData: [EFMAResult],
                                    vis: Range<Int>) -> ClosedRange<Double> {
        var lo = candles.map(\.low).min()  ?? 0
        var hi = candles.map(\.high).max() ?? 1
        for ma in maData {
            let vs = vis.compactMap { $0 < ma.values.count ? ma.values[$0] : nil }
                       .compactMap { $0 }
            if let v = vs.min() { lo = Swift.min(lo, v) }
            if let v = vs.max() { hi = Swift.max(hi, v) }
        }
        let pad = (hi - lo) * 0.05
        return (lo - pad)...(hi + pad)
    }

    private func makeCtx(_ size: CGSize) -> CGContext? {
        makeOffscreenContext(size: size, scale: scale)
    }
}

// MARK: - EFKPeriod helpers

private extension EFKPeriod {
    var isIntraday: Bool {
        switch self {
        case .min1, .min5, .min15, .min30, .min60, .min120: return true
        default: return false
        }
    }
}
