//
//  EFKLineRenderer.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// EFKLineRenderer.swift
// K线图渲染器 — 蜡烛图 + MA/EMA线 + 副图(MACD/KDJ/RSI/VOL)

import UIKit
import CoreGraphics

final class EFKLineRenderer {

    private let scale: CGFloat
    private let tlRenderer: EFTimelineRenderer  // 复用 MACD / Tooltip / 工具方法

    init(scale: CGFloat = UIScreen.main.scale) {
        self.scale = scale
        self.tlRenderer = EFTimelineRenderer(scale: scale)
    }

    // MARK: ── 主图 ────────────────────────────────────────────

    func renderMain(
        data: EFKLineData,
        rect: CGRect,
        visibleRange: Range<Int>,
        crosshairIdx: Int? = nil,
        candleWidth: CGFloat = EFLayout.candleDefW
    ) -> CGImage? {
        guard let ctx = makeOffscreenContext(size: rect.size, scale: scale) else { return nil }
        drawMain(ctx: ctx, data: data, rect: rect.withOrigin(.zero),
                 vis: visibleRange, crosshairIdx: crosshairIdx, cw: candleWidth)
        return ctx.makeImage()
    }

    // MARK: ── 副图 ────────────────────────────────────────────

    func renderSub(
        data: EFKLineData,
        subIndex: Int,
        rect: CGRect,
        visibleRange: Range<Int>,
        candleWidth: CGFloat = EFLayout.candleDefW,
        crosshairIdx: Int? = nil
    ) -> CGImage? {
        guard subIndex < data.subData.count,
              let ctx = makeOffscreenContext(size: rect.size, scale: scale) else { return nil }
        drawSub(ctx: ctx, data: data, subIndex: subIndex, rect: rect.withOrigin(.zero),
                vis: visibleRange, cw: candleWidth, crosshairIdx: crosshairIdx)
        return ctx.makeImage()
    }

    // MARK: ── 主图绘制 ───────────────────────────────────────

    private func drawMain(ctx: CGContext, data: EFKLineData, rect: CGRect,
                           vis: Range<Int>, crosshairIdx: Int?, cw: CGFloat) {
        ctx.setFillColor(EFColor.panel.cgColor); ctx.fill(rect)

        let candles = data.candles
        guard !candles.isEmpty, !vis.isEmpty else { return }

        let safeVis  = clampVis(vis, count: candles.count)
        let visCan   = Array(candles[safeVis])
        let priceRange = computePriceRange(candles: visCan, maData: data.maResults, vis: safeVis)
        let content  = mainContentRect(rect)
        let map      = EFCoordMap(rect: content, minV: priceRange.lowerBound, maxV: priceRange.upperBound)

        drawPriceGrid(ctx: ctx, rect: rect, content: content, map: map, range: priceRange)
        drawCandles(ctx: ctx, candles: visCan, vis: safeVis, content: content, map: map, cw: cw)
        drawMALines(ctx: ctx, maData: data.maResults, vis: safeVis, content: content, map: map, cw: cw)
        drawTimeAxis(ctx: ctx, candles: visCan, vis: safeVis, rect: rect, content: content, cw: cw, period: data.period)

        if let ci = crosshairIdx, safeVis.contains(ci) {
            drawCrosshair(ctx: ctx, idx: ci, data: data, vis: safeVis,
                          rect: rect, content: content, map: map, cw: cw)
        }
    }

    // MARK: ── 蜡烛绘制（批量路径）───────────────────────────

    private func drawCandles(ctx: CGContext, candles: [EFKLinePoint], vis: Range<Int>,
                              content: CGRect, map: EFCoordMap, cw: CGFloat) {
        let slotW   = content.width / CGFloat(vis.count)
        let bodyW   = Swift.max(1, slotW * (1 - EFLayout.candleGap))
        let wickW: CGFloat = 0.8

        let riseBody = CGMutablePath(), fallBody = CGMutablePath()
        let riseWick = CGMutablePath(), fallWick = CGMutablePath()
        let dojiPath = CGMutablePath()

        for (i, c) in candles.enumerated() {
            let gIdx  = vis.lowerBound + i
            let x     = content.minX + (CGFloat(i) + 0.5) * slotW
            let openY  = map.y(c.open)
            let closeY = map.y(c.close)
            let highY  = map.y(c.high)
            let lowY   = map.y(c.low)
            let bodyTop = Swift.min(openY, closeY)
            let bodyH   = Swift.max(1, abs(closeY - openY))
            let body    = CGRect(x: x - bodyW/2, y: bodyTop, width: bodyW, height: bodyH)

            if c.isBullish {
                riseBody.addRect(body)
                riseWick.move(to: CGPoint(x: x, y: highY));  riseWick.addLine(to: CGPoint(x: x, y: bodyTop))
                riseWick.move(to: CGPoint(x: x, y: bodyTop + bodyH)); riseWick.addLine(to: CGPoint(x: x, y: lowY))
            } else if c.close < c.open {
                fallBody.addRect(body)
                fallWick.move(to: CGPoint(x: x, y: highY));  fallWick.addLine(to: CGPoint(x: x, y: bodyTop))
                fallWick.move(to: CGPoint(x: x, y: bodyTop + bodyH)); fallWick.addLine(to: CGPoint(x: x, y: lowY))
            } else {
                dojiPath.move(to: CGPoint(x: x - bodyW/2, y: openY))
                dojiPath.addLine(to: CGPoint(x: x + bodyW/2, y: openY))
                dojiPath.move(to: CGPoint(x: x, y: highY))
                dojiPath.addLine(to: CGPoint(x: x, y: lowY))
            }
            let _ = gIdx // suppress warning
        }

        ctx.addPath(riseBody); ctx.setFillColor(EFColor.rising.cgColor);   ctx.fillPath()
        ctx.addPath(fallBody); ctx.setFillColor(EFColor.falling.cgColor);  ctx.fillPath()
        ctx.addPath(riseWick); ctx.setStrokeColor(EFColor.rising.cgColor); ctx.setLineWidth(wickW); ctx.strokePath()
        ctx.addPath(fallWick); ctx.setStrokeColor(EFColor.falling.cgColor); ctx.strokePath()
        ctx.addPath(dojiPath); ctx.setStrokeColor(EFColor.neutral.cgColor); ctx.strokePath()
    }

    // MARK: ── MA 线 ───────────────────────────────────────────

    private func drawMALines(ctx: CGContext, maData: [EFMAResult], vis: Range<Int>,
                              content: CGRect, map: EFCoordMap, cw: CGFloat) {
        let slotW = content.width / CGFloat(vis.count)
        for ma in maData {
            let pts: [CGPoint?] = vis.indices.map { i in
                let gi = vis.lowerBound + i
                guard gi < ma.values.count, let v = ma.values[gi] else { return nil }
                return CGPoint(x: content.minX + (CGFloat(i) + 0.5) * slotW, y: map.y(v))
            }
            ctx.strokePolyline(points: pts, color: ma.color, lineWidth: 1.0)
        }
    }

    // MARK: ── 价格网格 ───────────────────────────────────────

    private func drawPriceGrid(ctx: CGContext, rect: CGRect, content: CGRect,
                                map: EFCoordMap, range: ClosedRange<Double>) {
        let rows = EFLayout.mainRows
        let span = range.upperBound - range.lowerBound

        for i in 0..<rows {
            let ratio = Double(i) / Double(rows - 1)
            let price = range.upperBound - ratio * span
            let y     = map.y(price)
            ctx.strokeLine(from: CGPoint(x: content.minX, y: y),
                            to:   CGPoint(x: content.maxX, y: y),
                            color: EFColor.grid, lineWidth: 0.5)
            ctx.drawString(EFFormat.price(price, decimals: price < 100 ? 3 : 2),
                            at: CGPoint(x: content.maxX + 3, y: y),
                            font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
        }
        let cols = EFLayout.mainRows - 1
        for i in 1..<cols {
            let x = content.minX + CGFloat(i) / CGFloat(cols) * content.width
            ctx.strokeLine(from: CGPoint(x: x, y: content.minY),
                            to:   CGPoint(x: x, y: content.maxY),
                            color: EFColor.grid, lineWidth: 0.5)
        }
        ctx.setStrokeColor(EFColor.border.cgColor); ctx.setLineWidth(0.5); ctx.stroke(content)
    }

    // MARK: ── 时间轴 ─────────────────────────────────────────

    private func drawTimeAxis(ctx: CGContext, candles: [EFKLinePoint], vis: Range<Int>,
                               rect: CGRect, content: CGRect, cw: CGFloat, period: EFKPeriod) {
        guard candles.count >= 2 else { return }
        let slotW  = content.width / CGFloat(candles.count)
        let ticks  = [0, candles.count/4, candles.count/2, candles.count*3/4, candles.count-1]
        let y      = content.maxY + EFLayout.timeAxisH/2
        for t in ticks {
            guard t < candles.count else { continue }
            let c = candles[t]
            let x = content.minX + (CGFloat(t) + 0.5) * slotW
            let label: String
            switch period {
            case .min1,.min5,.min15,.min30,.min60,.min120: label = EFFormat.time(c.time)
            default: label = EFFormat.date(c.time)
            }
            let align: NSTextAlignment = t == 0 ? .left : (t == candles.count-1 ? .right : .center)
            ctx.drawString(label, at: CGPoint(x: x, y: y),
                            font: EFLayout.axisFont, color: EFColor.textSecondary, align: align)
        }
    }

    // MARK: ── 十字线（K线）──────────────────────────────────

    private func drawCrosshair(ctx: CGContext, idx: Int, data: EFKLineData, vis: Range<Int>,
                                rect: CGRect, content: CGRect, map: EFCoordMap, cw: CGFloat) {
        let c    = data.candles[idx]
        let slotW = content.width / CGFloat(vis.count)
        let i    = idx - vis.lowerBound
        let x    = content.minX + (CGFloat(i) + 0.5) * slotW
        let y    = map.y(c.close)

        ctx.strokeDashedLine(from: CGPoint(x: content.minX, y: y),
                              to:   CGPoint(x: content.maxX, y: y), color: EFColor.crosshair)
        ctx.strokeDashedLine(from: CGPoint(x: x, y: content.minY),
                              to:   CGPoint(x: x, y: content.maxY), color: EFColor.crosshair)

        let pColor = c.isBullish ? EFColor.rising : EFColor.falling
        ctx.drawLabelBadge(EFFormat.price(c.close),
                            at: CGPoint(x: content.maxX + 1, y: y),
                            font: EFLayout.axisFont, fg: .white, bg: pColor)
        ctx.drawLabelBadge(EFFormat.date(c.time),
                            at: CGPoint(x: x, y: content.maxY + EFLayout.timeAxisH/2),
                            font: EFLayout.axisFont, fg: EFColor.background, bg: EFColor.crosshairLabel)

        // Tooltip
        let rows: [(String, String, UIColor)] = [
            ("日期", EFFormat.ymd(c.time),                          EFColor.textPrimary),
            ("开盘", EFFormat.price(c.open),                        pColor),
            ("收盘", EFFormat.price(c.close),                       pColor),
            ("最高", EFFormat.price(c.high),                        EFColor.rising),
            ("最低", EFFormat.price(c.low),                         EFColor.falling),
            ("成交量", EFFormat.volume(c.volume),                   EFColor.textPrimary),
            ("涨跌幅", EFFormat.percent(c.changePercent, signed: true), pColor),
        ]
        tlRenderer.drawTooltip(ctx: ctx, rows: rows, at: CGPoint(x: x, y: y), content: content)
    }

    // MARK: ── 副图绘制 ───────────────────────────────────────

    private func drawSub(ctx: CGContext, data: EFKLineData, subIndex: Int, rect: CGRect,
                          vis: Range<Int>, cw: CGFloat, crosshairIdx: Int?) {
        ctx.setFillColor(EFColor.panel.cgColor); ctx.fill(rect)
        let content = subContentRect(rect)
        ctx.setStrokeColor(EFColor.border.cgColor); ctx.setLineWidth(0.5); ctx.stroke(content)

        let safeVis = clampVis(vis, count: data.candles.count)

        switch data.subData[subIndex] {
        case .volume(let vd):
            drawVolumeSub(ctx: ctx, vd: vd, vis: safeVis, content: content,
                           cw: cw, crosshairIdx: crosshairIdx)
        case .macd(let md):
            tlRenderer.drawMACDSub(ctx: ctx, result: md, count: data.candles.count,
                                    total: data.candles.count, content: content,
                                    crosshairIdx: crosshairIdx)
            drawSubLabel(ctx: ctx, content: content, text: "MACD",
                          vals: [("DIF", md.dif.last, EFColor.difLine),
                                 ("DEA", md.dea.last, EFColor.deaLine),
                                 ("M",   md.bar.last,  EFColor.rising)])
        case .kdj(let kd):
            drawKDJSub(ctx: ctx, kd: kd, vis: safeVis, content: content,
                        cw: cw, crosshairIdx: crosshairIdx)
        case .rsi(let rd):
            drawRSISub(ctx: ctx, rd: rd, vis: safeVis, content: content,
                        cw: cw, crosshairIdx: crosshairIdx)
        }
    }

    private func drawVolumeSub(ctx: CGContext, vd: EFVolumeResult, vis: Range<Int>,
                                content: CGRect, cw: CGFloat, crosshairIdx: Int?) {
        guard vis.count > 0 else { return }
        let visVols  = Array(vd.volumes[vis])
        let maxVol   = visVols.max() ?? 1
        let slotW    = content.width / CGFloat(vis.count)
        let bodyW    = Swift.max(1, slotW * (1 - EFLayout.candleGap))
        let map      = EFCoordMap(rect: content, minV: 0, maxV: maxVol)

        let upP = CGMutablePath(), dnP = CGMutablePath()
        for (i, gi) in vis.enumerated() {
            guard gi < vd.volumes.count else { continue }
            let v   = vd.volumes[gi]
            let x   = content.minX + (CGFloat(i) + 0.5) * slotW
            let h   = content.height * CGFloat(v / maxVol)
            let r   = CGRect(x: x - bodyW/2, y: content.maxY - h, width: bodyW, height: h)
            let bull = gi < vd.isBullish.count ? vd.isBullish[gi] : true
            if bull { upP.addRect(r) } else { dnP.addRect(r) }
        }
        ctx.addPath(upP); ctx.setFillColor(EFColor.rising.withAlphaComponent(0.85).cgColor); ctx.fillPath()
        ctx.addPath(dnP); ctx.setFillColor(EFColor.falling.withAlphaComponent(0.85).cgColor); ctx.fillPath()

        // MA 线
        func volLine(_ vals: [Double?], color: UIColor) {
            let pts: [CGPoint?] = vis.enumerated().map { i, gi in
                guard gi < vals.count, let v = vals[gi] else { return nil }
                return CGPoint(x: content.minX + (CGFloat(i) + 0.5) * slotW, y: map.y(v))
            }
            ctx.strokePolyline(points: pts, color: color, lineWidth: 1.0)
        }
        volLine(vd.ma1, color: EFColor.volMa1)
        volLine(vd.ma2, color: EFColor.volMa2)

        // 十字线
        if let ci = crosshairIdx, vis.contains(ci) {
            let i = ci - vis.lowerBound
            let x = content.minX + (CGFloat(i) + 0.5) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: content.minY),
                                  to:   CGPoint(x: x, y: content.maxY),
                                  color: EFColor.crosshair, lineWidth: 0.5)
        }

        // 图例
        let lastIdx = Swift.max(0, vis.upperBound - 1)
        let lastVol = lastIdx < vd.volumes.count ? vd.volumes[lastIdx] : 0
        let ma1v    = lastIdx < vd.ma1.count ? vd.ma1[lastIdx] : nil
        let ma2v    = lastIdx < vd.ma2.count ? vd.ma2[lastIdx] : nil
        var legend  = "成交量 \(EFFormat.volume(lastVol))"
        if let v = ma1v { legend += "  MA5:\(EFFormat.volume(v))" }
        if let v = ma2v { legend += "  MA10:\(EFFormat.volume(v))" }
        ctx.drawString(legend, at: CGPoint(x: content.minX + 4, y: content.minY + 7),
                        font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
    }

    private func drawKDJSub(ctx: CGContext, kd: EFKDJResult, vis: Range<Int>,
                              content: CGRect, cw: CGFloat, crosshairIdx: Int?) {
        let map   = EFCoordMap(rect: content, minV: 0, maxV: 100)
        let slotW = content.width / CGFloat(vis.count)

        // 超买超卖参考线
        for level in [20.0, 50.0, 80.0] {
            let y = map.y(level)
            ctx.strokeDashedLine(from: CGPoint(x: content.minX, y: y),
                                  to:   CGPoint(x: content.maxX, y: y),
                                  color: EFColor.grid, lineWidth: 0.3, dash: [2, 2])
        }

        func line(_ vals: [Double], color: UIColor) {
            let pts: [CGPoint?] = vis.enumerated().map { i, gi in
                guard gi < vals.count else { return nil }
                return CGPoint(x: content.minX + (CGFloat(i) + 0.5) * slotW, y: map.y(vals[gi]))
            }
            ctx.strokePolyline(points: pts, color: color, lineWidth: 1.0)
        }
        line(kd.k, color: EFColor.kLine)
        line(kd.d, color: EFColor.dLine)
        line(kd.j, color: EFColor.jLine)

        // 右侧 20/50/80 标签
        for level in [20.0, 80.0] {
            ctx.drawString("\(Int(level))", at: CGPoint(x: content.maxX + 3, y: map.y(level)),
                            font: EFLayout.axisFont, color: EFColor.textSecondary, align: .left)
        }

        // 十字线
        if let ci = crosshairIdx, vis.contains(ci) {
            let i = ci - vis.lowerBound
            let x = content.minX + (CGFloat(i) + 0.5) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: content.minY),
                                  to:   CGPoint(x: x, y: content.maxY),
                                  color: EFColor.crosshair, lineWidth: 0.5)
        }

        let gi = Swift.max(0, vis.upperBound - 1)
        drawSubLabel(ctx: ctx, content: content, text: "KDJ",
                      vals: [("K", gi < kd.k.count ? kd.k[gi] : nil, EFColor.kLine),
                             ("D", gi < kd.d.count ? kd.d[gi] : nil, EFColor.dLine),
                             ("J", gi < kd.j.count ? kd.j[gi] : nil, EFColor.jLine)])
    }

    private func drawRSISub(ctx: CGContext, rd: EFRSIResult, vis: Range<Int>,
                              content: CGRect, cw: CGFloat, crosshairIdx: Int?) {
        let map   = EFCoordMap(rect: content, minV: 0, maxV: 100)
        let slotW = content.width / CGFloat(vis.count)

        for level in [30.0, 70.0] {
            let y = map.y(level)
            ctx.strokeDashedLine(from: CGPoint(x: content.minX, y: y),
                                  to:   CGPoint(x: content.maxX, y: y),
                                  color: EFColor.grid, lineWidth: 0.3, dash: [2, 2])
        }

        let pts: [CGPoint?] = vis.enumerated().map { i, gi in
            guard gi < rd.values.count else { return nil }
            return CGPoint(x: content.minX + (CGFloat(i) + 0.5) * slotW, y: map.y(rd.values[gi]))
        }
        ctx.strokePolyline(points: pts, color: EFColor.ma5, lineWidth: 1.0)

        if let ci = crosshairIdx, vis.contains(ci) {
            let i = ci - vis.lowerBound
            let x = content.minX + (CGFloat(i) + 0.5) * slotW
            ctx.strokeDashedLine(from: CGPoint(x: x, y: content.minY),
                                  to:   CGPoint(x: x, y: content.maxY),
                                  color: EFColor.crosshair, lineWidth: 0.5)
        }

        let gi  = Swift.max(0, vis.upperBound - 1)
        let val = gi < rd.values.count ? rd.values[gi] : nil
        drawSubLabel(ctx: ctx, content: content, text: "RSI(\(rd.period))",
                      vals: [("RSI", val, EFColor.ma5)])
    }

    // MARK: ── 副图标题图例 ────────────────────────────────────

    private func drawSubLabel(ctx: CGContext, content: CGRect, text: String,
                               vals: [(String, Double?, UIColor)]) {
        var x = content.minX + 4
        let y = content.minY + 7
        ctx.drawString(text + " ", at: CGPoint(x: x, y: y),
                        font: EFLayout.infoFont, color: EFColor.textSecondary, align: .left)
        x += (text as NSString).size(withAttributes: [.font: EFLayout.infoFont]).width + 6

        for (label, val, color) in vals {
            guard let v = val else { continue }
            let s = "\(label):\(EFFormat.price(v, decimals: 2))  "
            ctx.drawString(s, at: CGPoint(x: x, y: y), font: EFLayout.infoFont, color: color, align: .left)
            x += (s as NSString).size(withAttributes: [.font: EFLayout.infoFont]).width
        }
    }

    // MARK: ── 工具 ───────────────────────────────────────────

    func mainContentRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY + EFLayout.infoBarH + EFLayout.topPad,
               width: rect.width - EFLayout.priceAxisW,
               height: rect.height - EFLayout.infoBarH - EFLayout.topPad - EFLayout.timeAxisH)
    }

    func subContentRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY + EFLayout.subDivider,
               width: rect.width - EFLayout.priceAxisW,
               height: rect.height - EFLayout.subDivider - EFLayout.timeAxisH)
    }

    private func computePriceRange(candles: [EFKLinePoint], maData: [EFMAResult],
                                    vis: Range<Int>) -> ClosedRange<Double> {
        var lo = candles.map(\.low).min() ?? 0
        var hi = candles.map(\.high).max() ?? 1
        for ma in maData {
            let vs = Array(ma.values[vis]).compactMap { $0 }
            if let v = vs.min() { lo = Swift.min(lo, v) }
            if let v = vs.max() { hi = Swift.max(hi, v) }
        }
        let pad = (hi - lo) * 0.05
        return (lo - pad)...(hi + pad)
    }

    private func clampVis(_ vis: Range<Int>, count: Int) -> Range<Int> {
        let s = Swift.max(0, vis.lowerBound)
        let e = Swift.min(count, vis.upperBound)
        return s < e ? s..<e : 0..<Swift.min(50, count)
    }
}

// Swift 5.7: Array subscript with Range<Int>
private extension Array {
    subscript(safe range: Range<Int>) -> ArraySlice<Element> {
        let s = Swift.max(0, range.lowerBound)
        let e = Swift.min(count, range.upperBound)
        guard s < e else { return [] }
        return self[s..<e]
    }
}
