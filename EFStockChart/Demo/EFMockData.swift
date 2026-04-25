//
//  EFMockData.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 完整 Mock 数据 — 可直接运行验证

import Foundation
import UIKit

// MARK: ── Mock 数据生成 ───────────────────────────────────────

public enum EFMockData {

    // MARK: ── 贵州茅台 600519 分时图（个股）──────────────────

    public static func stockTimeline() -> EFTimelineData {
        let prevClose: Double = 1465.02
        var pts = [EFTimePoint]()
        var price  = prevClose
        var cum_amount = 0.0, cum_vol = 0.0
        let cal = Calendar.current
        var comps = cal.dateComponents([.year,.month,.day], from: Date())

        // 上午 09:30–11:30 (120 min)
        for i in 0..<120 {
            comps.hour = 9; comps.minute = 30 + i
            let t = cal.date(from: comps)!
            _ = Double.random(in: -0.008...0.008)
            price = (prevClose * (1 + Double.random(in: -0.03...0.03)))
                .clamped(lo: prevClose * 0.9, hi: prevClose * 1.1)
            if i == 0 { price = 1465.02 }
            let vol    = Double.random(in: 80...500) * 100
            let amount = vol * price
            cum_vol    += vol; cum_amount += amount
            let avg    = cum_amount / cum_vol
            let chg    = (price - prevClose) / prevClose * 100
            pts.append(EFTimePoint(time: t, price: price, avgPrice: avg,
                                    volume: vol, amount: amount, changePercent: chg))
        }
        // 下午 13:00–15:00 (120 min)
        for i in 0..<120 {
            comps.hour = 13; comps.minute = i
            let t = cal.date(from: comps)!
            price = Swift.max(prevClose * 0.9,
                       Swift.min(prevClose * 1.1, price * (1 + Double.random(in: -0.006...0.006))))
            let vol    = Double.random(in: 50...400) * 100
            let amount = vol * price
            cum_vol    += vol; cum_amount += amount
            let avg    = cum_amount / cum_vol
            let chg    = (price - prevClose) / prevClose * 100
            pts.append(EFTimePoint(time: t, price: price, avgPrice: avg,
                                    volume: vol, amount: amount, changePercent: chg))
        }
        // 收盘价靠近截图数值
        if let last = pts.last {
            let finalPrice = 1460.49
            let chg = (finalPrice - prevClose) / prevClose * 100
            pts[pts.count-1] = EFTimePoint(time: last.time, price: finalPrice,
                                             avgPrice: last.avgPrice, volume: last.volume,
                                             amount: last.amount, changePercent: chg)
        }

        let ob = EFOrderBook(
            asks: [
                EFOrderLevel(1460.68, 1), EFOrderLevel(1460.66, 2),
                EFOrderLevel(1460.60, 2), EFOrderLevel(1460.50, 4),
                EFOrderLevel(1460.49, 3),
            ],
            bids: [
                EFOrderLevel(1460.14, 1), EFOrderLevel(1460.13, 1),
                EFOrderLevel(1460.10, 13), EFOrderLevel(1460.05, 1),
                EFOrderLevel(1460.04, 1),
            ]
        )

        return EFTimelineData(
            securityType: .stock, stockCode: "600519", stockName: "贵州茅台",
            prevClose: prevClose, upperLimit: prevClose * 1.1, lowerLimit: prevClose * 0.9,
            points: pts, period: .timeline, orderBook: ob
        )
    }

    // MARK: ── 上证指数 000001 分时图（指数）──────────────────

    public static func indexTimeline() -> EFTimelineData {
        let prevClose: Double = 3995.00
        var pts = [EFTimePoint]()
        var price = prevClose
        var cum_amount = 0.0, cum_vol = 0.0
        let cal = Calendar.current
        var comps = cal.dateComponents([.year,.month,.day], from: Date())

        // 总成分股约 2346
        let totalStocks = 2346

        for session in [(9,30,120), (13,0,120)] {
            for i in 0..<session.2 {
                comps.hour = session.0; comps.minute = session.1 + i
                let t = cal.date(from: comps)!
                price = Swift.max(prevClose * 0.9,
                           Swift.min(prevClose * 1.1, price * (1 + Double.random(in: -0.004...0.004))))
                let vol    = Double.random(in: 500...3000) * 10000
                let amount = vol * price
                cum_vol    += vol; cum_amount += amount
                let avg    = cum_amount / cum_vol
                let chg    = (price - prevClose) / prevClose * 100

                // 涨跌家数随价格方向随机分布
                let trend    = chg > 0 ? 1.0 : -1.0
                let advFrac  = (0.5 + trend * Double.random(in: 0...0.25)).clamped(lo: 0.1, hi: 0.85)
                let adv      = Int(Double(totalStocks) * advFrac)
                let dec      = Int(Double(totalStocks) * (1 - advFrac) * Double.random(in: 0.8...1.0))
                let unch     = totalStocks - adv - dec

                pts.append(EFTimePoint(time: t, price: price, avgPrice: avg,
                                        volume: vol, amount: amount, changePercent: chg,
                                        advancers: adv, decliners: dec, unchanged: unch))
            }
        }
        // 调整到截图收盘数值
        let finalPrice = 3966.17
        if !pts.isEmpty {
            let last = pts[pts.count-1]
            let chg  = (finalPrice - prevClose) / prevClose * 100
            pts[pts.count-1] = EFTimePoint(time: last.time, price: finalPrice,
                                             avgPrice: last.avgPrice, volume: last.volume,
                                             amount: last.amount, changePercent: chg,
                                             advancers: last.advancers, decliners: last.decliners,
                                             unchanged: last.unchanged)
        }

        return EFTimelineData(
            securityType: .index, stockCode: "000001", stockName: "上证指数",
            prevClose: prevClose, upperLimit: prevClose * 1.15, lowerLimit: prevClose * 0.85,
            points: pts, period: .timeline
        )
    }

    // MARK: ── 贵州茅台 日K（含所有副图数据）───────────────────

    public static func stockKLine(period: EFKPeriod = .daily) -> EFKLineData {
        let candles = generateCandles(count: 300, startPrice: 900, name: "茅台")

        // 异步计算替代（这里同步计算供 Demo 用）
        let closes  = candles.map(\.close)
        let highs   = candles.map(\.high)
        let lows    = candles.map(\.low)
        let volumes = candles.map(\.volume)

        let maPeriods = [5, 10, 20, 60, 120, 250]
        let maLines   = EFIndicatorEngine.calculateMALines(closes: closes, periods: maPeriods)
        let macdData  = EFIndicatorEngine.macd(closes: closes)
        let kdjData   = EFIndicatorEngine.kdj(highs: highs, lows: lows, closes: closes)
        let rsi6      = EFIndicatorEngine.rsi(closes: closes, period: 6)
        let rsi12     = EFIndicatorEngine.rsi(closes: closes, period: 12)
        let rsi24     = EFIndicatorEngine.rsi(closes: closes, period: 24)
        let volData   = EFIndicatorEngine.volumeResult(volumes: volumes, candles: candles)

        let subData: [EFSubData] = [
            .macd(macdData),
            .kdj(kdjData),
            .rsi([rsi6, rsi12, rsi24]),
            .volume(volData),
        ]

        return EFKLineData(
            securityType: .stock,
            period: period,
            candles: candles,
            maResults: maLines,
            subData: subData,
            prevClose: candles.dropLast().last?.close ?? 1465
        )
    }

    // MARK: ── 行情摘要（个股）────────────────────────────────

    public static func stockQuote() -> EFQuoteSummary {
        EFQuoteSummary(
            code: "600519", name: "贵州茅台",
            currentPrice: 1460.49, changeAmount: -4.53, changePercent: -0.31,
            open: 1465.02, high: 1465.02, low: 1447.50, prevClose: 1465.02,
            volume: 20705, amount: 3_012_000_000, turnoverRate: 0.17, pe: 21.22,
            totalMarketCap: 183_500_000_000, floatMarketCap: 183_500_000_000
        )
    }

    // MARK: ── 行情摘要（指数）────────────────────────────────

    public static func indexQuote() -> EFQuoteSummary {
        EFQuoteSummary(
            code: "000001", name: "上证指数",
            currentPrice: 3966.17, changeAmount: -28.83, changePercent: -0.72,
            open: 3967.63, high: 3979.13, low: 3955.25, prevClose: 3995.00,
            volume: 542_000_000, amount: 902_500_000_000, turnoverRate: 1.13, pe: 0,
            advancers: 514, decliners: 1802, unchanged: 30,
            limitUp: 28, limitDown: 7, netInflow: -24.17
        )
    }

    // MARK: ── K线数据生成器 ──────────────────────────────────

    private static func generateCandles(count: Int, startPrice: Double, name: String) -> [EFKLinePoint] {
        var candles = [EFKLinePoint](); candles.reserveCapacity(count)
        var price   = startPrice
        let cal     = Calendar.current
        var date    = cal.date(byAdding: .year, value: -1, to: Date())!

        func nextTradingDay(_ d: Date) -> Date {
            var next = cal.date(byAdding: .day, value: 1, to: d)!
            while [1, 7].contains(cal.component(.weekday, from: next)) {
                next = cal.date(byAdding: .day, value: 1, to: next)!
            }
            return next
        }

        var prevClose = price
        for _ in 0..<count {
            let trend   = 0.0003
            let noise   = Double.random(in: -0.025...0.025)
            let open    = prevClose * (1 + Double.random(in: -0.004...0.004))
            let close   = open * (1 + trend + noise)
            let high    = Swift.max(open, close) * (1 + Double.random(in: 0...0.012))
            let low     = Swift.min(open, close) * (1 - Double.random(in: 0...0.012))
            let vol     = Swift.max(10000, 500_000 * (1 + abs(noise) * 5 + Double.random(in: -0.3...0.5)))

            candles.append(EFKLinePoint(
                time: date, open: Swift.max(0.01, open), high: Swift.max(0.01, high),
                low: Swift.max(0.01, low), close: Swift.max(0.01, close),
                volume: vol, amount: vol * (open+close)/2
            ))
            prevClose = close; price = close
            date = nextTradingDay(date)
        }
        return candles
    }
}
