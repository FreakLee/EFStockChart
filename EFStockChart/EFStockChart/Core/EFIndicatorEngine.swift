//
//  EFIndicatorEngine.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// EFIndicatorEngine.swift
// 技术指标计算引擎 — 全部 O(n)，Swift 5.7 兼容

import Foundation
import UIKit

public enum EFIndicatorEngine {

    // MARK: ── MA ────────────────────────────────────────────

    public static func ma(_ data: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return data.map { Optional($0) } }
        var result  = [Double?](repeating: nil, count: data.count)
        guard data.count >= period else { return result }
        var sum = data[0..<period].reduce(0, +)
        result[period - 1] = sum / Double(period)
        for i in period..<data.count {
            sum += data[i] - data[i - period]
            result[i] = sum / Double(period)
        }
        return result
    }

    /// 批量计算 MA，返回带颜色的结果
    public static func calculateMALines(
        closes: [Double],
        periods: [Int]
    ) -> [EFMAResult] {
        let colors = EFColor.maColors
        return periods.enumerated().map { idx, period in
            EFMAResult(
                period: period,
                color:  colors[Swift.min(idx, colors.count - 1)],
                values: ma(closes, period: period)
            )
        }
    }

    // MARK: ── EMA ───────────────────────────────────────────

    public static func ema(_ data: [Double], period: Int) -> [Double] {
        guard !data.isEmpty else { return [] }
        let k = 2.0 / Double(period + 1)
        var result = [Double](); result.reserveCapacity(data.count)
        var ema = data[0]; result.append(ema)
        for i in 1..<data.count {
            ema = data[i] * k + ema * (1 - k); result.append(ema)
        }
        return result
    }

    // MARK: ── MACD(12,26,9) ──────────────────────────────────

    public static func macd(
        closes: [Double],
        fast: Int = 12, slow: Int = 26, signal: Int = 9
    ) -> EFMACDResult {
        guard closes.count > slow else {
            let z = [Double](repeating: 0, count: closes.count)
            return EFMACDResult(dif: z, dea: z, bar: z)
        }
        let eFast = ema(closes, period: fast)
        let eSlow = ema(closes, period: slow)
        let dif   = zip(eFast, eSlow).map { $0 - $1 }
        let dea   = ema(dif, period: signal)
        let bar   = zip(dif, dea).map { ($0 - $1) * 2 }
        return EFMACDResult(dif: dif, dea: dea, bar: bar)
    }

    // MARK: ── KDJ(9,3,3) ────────────────────────────────────

    public static func kdj(
        highs: [Double], lows: [Double], closes: [Double],
        n: Int = 9, m1: Int = 3, m2: Int = 3
    ) -> EFKDJResult {
        let count = Swift.min(highs.count, lows.count, closes.count)
        var ks = [Double](), ds = [Double](), js = [Double]()
        ks.reserveCapacity(count); ds.reserveCapacity(count); js.reserveCapacity(count)
        var k = 50.0, d = 50.0
        for i in 0..<count {
            let lo = Swift.max(0, i - n + 1)
            let hh = highs[lo...i].max()!; let ll = lows[lo...i].min()!
            let rsv = hh == ll ? 50.0 : (closes[i] - ll) / (hh - ll) * 100
            k = (k * Double(m1 - 1) + rsv) / Double(m1)
            d = (d * Double(m2 - 1) + k)   / Double(m2)
            ks.append(k); ds.append(d); js.append(3*k - 2*d)
        }
        return EFKDJResult(k: ks, d: ds, j: js)
    }

    // MARK: ── RSI(Wilder) ────────────────────────────────────

    public static func rsi(closes: [Double], period: Int = 14) -> EFRSIResult {
        guard closes.count > period else {
            return EFRSIResult(period: period,
                               values: [Double](repeating: 50, count: closes.count))
        }
        var result = [Double](repeating: 50, count: period)
        var g = 0.0, l = 0.0
        for i in 1...period {
            let d = closes[i] - closes[i-1]
            g += Swift.max(d, 0); l += Swift.max(-d, 0)
        }
        var ag = g / Double(period), al = l / Double(period)
        result.append(al == 0 ? 100 : 100 - 100/(1 + ag/al))
        for i in (period+1)..<closes.count {
            let d = closes[i] - closes[i-1]
            ag = (ag * Double(period-1) + Swift.max(d,0))  / Double(period)
            al = (al * Double(period-1) + Swift.max(-d,0)) / Double(period)
            result.append(al == 0 ? 100 : 100 - 100/(1 + ag/al))
        }
        return EFRSIResult(period: period, values: result)
    }

    // MARK: ── 成交量 MA ──────────────────────────────────────

    public static func volumeResult(
        volumes: [Double], candles: [EFKLinePoint],
        ma1Period: Int = 5, ma2Period: Int = 10
    ) -> EFVolumeResult {
        let isBullish = candles.map(\.isBullish)
        return EFVolumeResult(
            volumes:   volumes,
            ma1:       ma(volumes, period: ma1Period),
            ma2:       ma(volumes, period: ma2Period),
            isBullish: isBullish
        )
    }

    // MARK: ── 批量异步计算（结构体返回，兼容 Swift 5.7）─────────

    public struct BatchResult {
        public let maLines:    [EFMAResult]
        public let macd:       EFMACDResult
        public let kdj:        EFKDJResult
        public let rsi6:       EFRSIResult
        public let rsi12:      EFRSIResult
        public let volumeData: EFVolumeResult
    }

    public static func calculateAsync(
        candles: [EFKLinePoint],
        maPeriods: [Int] = [5, 10, 20, 60, 120, 250],
        completion: @escaping (BatchResult) -> Void
    ) {
        let closes  = candles.map(\.close)
        let highs   = candles.map(\.high)
        let lows    = candles.map(\.low)
        let volumes = candles.map(\.volume)

        DispatchQueue.global(qos: .userInitiated).async {
            let r = BatchResult(
                maLines:    calculateMALines(closes: closes, periods: maPeriods),
                macd:       macd(closes: closes),
                kdj:        kdj(highs: highs, lows: lows, closes: closes),
                rsi6:       rsi(closes: closes, period: 6),
                rsi12:      rsi(closes: closes, period: 12),
                volumeData: volumeResult(volumes: volumes, candles: candles)
            )
            DispatchQueue.main.async { completion(r) }
        }
    }
}
