//
//  EFChartModels.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 数据模型层 — 值语义(struct)，并发安全，完整覆盖个股+指数两种形态

import Foundation
import CoreGraphics
import UIKit

// MARK: ── 基础价格数据点 ─────────────────────────────────────

/// 分时单点（个股 & 指数通用）
public struct EFTimePoint {
    public let time:          Date
    public let price:         Double   // 当前价
    public let avgPrice:      Double   // 均价（VWAP）
    public let volume:        Double   // 成交量（手 / 万手）
    public let amount:        Double   // 成交额
    public let changePercent: Double   // 相对昨收涨跌幅 %

    // 仅指数使用（个股传 nil）
    public let advancers:  Int?        // 上涨家数
    public let decliners:  Int?        // 下跌家数
    public let unchanged:  Int?        // 平盘家数

    public init(time: Date, price: Double, avgPrice: Double, volume: Double,
                amount: Double, changePercent: Double,
                advancers: Int? = nil, decliners: Int? = nil, unchanged: Int? = nil) {
        self.time          = time
        self.price         = price
        self.avgPrice      = avgPrice
        self.volume        = volume
        self.amount        = amount
        self.changePercent = changePercent
        self.advancers     = advancers
        self.decliners     = decliners
        self.unchanged     = unchanged
    }
}

/// K线单根蜡烛（OHLCV）
public struct EFKLinePoint {
    public let time:    Date
    public let open:    Double
    public let high:    Double
    public let low:     Double
    public let close:   Double
    public let volume:  Double   // 成交量（手）
    public let amount:  Double   // 成交额（元）
    public var isBullish: Bool { close >= open }
    public var changePercent: Double { open == 0 ? 0 : (close - open) / open * 100 }

    public init(time: Date, open: Double, high: Double, low: Double,
                close: Double, volume: Double, amount: Double) {
        self.time   = time; self.open  = open; self.high = high
        self.low    = low;  self.close = close
        self.volume = volume; self.amount = amount
    }
}

// MARK: ── 图表类型 ───────────────────────────────────────────

/// 证券类型（决定 UI 布局差异）
public enum EFSecurityType {
    case stock      // 个股：分时图右侧显示盘口
    case index      // 指数：全宽，内嵌涨跌家数柱
    case etf        // ETF：同个股
}

/// 主图周期
public enum EFChartPeriod: Equatable {
    case timeline            // 分时
    case fiveDay             // 五日
    case kLine(EFKPeriod)   // K线

    public var title: String {
        switch self {
        case .timeline:       return "分时"
        case .fiveDay:        return "五日"
        case .kLine(let p):   return p.title
        }
    }
}

public enum EFKPeriod: CaseIterable, Equatable {
    case min1, min5, min15, min30, min60, min120
    case daily, weekly, monthly, quarterly, yearly

    public var title: String {
        switch self {
        case .min1:      return "1分"
        case .min5:      return "5分"
        case .min15:     return "15分"
        case .min30:     return "30分"
        case .min60:     return "60分"
        case .min120:    return "120分"
        case .daily:     return "日K"
        case .weekly:    return "周K"
        case .monthly:   return "月K"
        case .quarterly: return "季K"
        case .yearly:    return "年K"
        }
    }
}

// MARK: ── 技术指标结果 ──────────────────────────────────────

public struct EFMAResult {
    public let period: Int
    public let color:  UIColor
    public let values: [Double?]
}

public struct EFMACDResult {
    public let dif: [Double]
    public let dea: [Double]
    public let bar: [Double]   // MACD bar = (DIF-DEA)*2
}

public struct EFKDJResult {
    public let k: [Double]
    public let d: [Double]
    public let j: [Double]
}

public struct EFRSIResult {
    public let period: Int
    public let values: [Double]
}

public struct EFVolumeResult {
    public let volumes:  [Double]
    public let ma1:      [Double?]  // 成交量 MA5 (默认)
    public let ma2:      [Double?]  // 成交量 MA10
    public let isBullish:[Bool]     // 对应蜡烛方向，决定柱子颜色
}

// 副图指标枚举
public enum EFSubIndicator: CaseIterable, Equatable {
    case volume, macd, kdj, rsi
    public var title: String {
        switch self { case .volume: return "成交量"; case .macd: return "MACD"
                      case .kdj:   return "KDJ";    case .rsi:  return "RSI" }
    }
}

// 副图渲染用数据包
public enum EFSubData {
    case volume(EFVolumeResult)
    case macd(EFMACDResult)
    case kdj(EFKDJResult)
    case rsi(EFRSIResult)
}

// MARK: ── 完整数据包 ────────────────────────────────────────

/// 分时图数据包（传入图表组件的完整数据）
public struct EFTimelineData {
    public let securityType: EFSecurityType
    public let stockCode:    String
    public let stockName:    String
    public let prevClose:    Double          // 昨收（分时图以此为对称轴）
    public let upperLimit:   Double          // 涨停价
    public let lowerLimit:   Double          // 跌停价
    public let points:       [EFTimePoint]
    public let period:       EFChartPeriod   // .timeline or .fiveDay

    // 个股专用：五档盘口
    public var orderBook:    EFOrderBook?

    // 当前最新快照
    public var latestPrice:     Double { points.last?.price ?? prevClose }
    public var latestChange:    Double { latestPrice - prevClose }
    public var latestChangePct: Double { prevClose == 0 ? 0 : latestChange / prevClose * 100 }

    // 价格范围（以昨收对称，确保昨收线居中）
    public var priceRange: ClosedRange<Double> {
        guard !points.isEmpty else { return (prevClose * 0.9)...(prevClose * 1.1) }
        let ps = points.map(\.price)
        let maxDiff = Swift.max(
            abs((ps.max() ?? prevClose) - prevClose),
            abs((ps.min() ?? prevClose) - prevClose)
        )
        let padding = Swift.max(maxDiff * 1.08, prevClose * 0.001)
        return (prevClose - padding)...(prevClose + padding)
    }

    public init(securityType: EFSecurityType, stockCode: String, stockName: String,
                prevClose: Double, upperLimit: Double, lowerLimit: Double,
                points: [EFTimePoint], period: EFChartPeriod = .timeline,
                orderBook: EFOrderBook? = nil) {
        self.securityType = securityType; self.stockCode = stockCode; self.stockName = stockName
        self.prevClose = prevClose; self.upperLimit = upperLimit; self.lowerLimit = lowerLimit
        self.points = points; self.period = period; self.orderBook = orderBook
    }
}

/// K线图数据包
public struct EFKLineData {
    public let securityType: EFSecurityType
    public let period:       EFKPeriod
    public let candles:      [EFKLinePoint]
    public let maResults:    [EFMAResult]    // 计算好的 MA 线数据
    public let subData:      [EFSubData]     // 最多 4 个副图
    public var prevClose:    Double          // 最近的昨收（用于最右侧涨跌色判断）

    public init(securityType: EFSecurityType, period: EFKPeriod, candles: [EFKLinePoint],
                maResults: [EFMAResult], subData: [EFSubData], prevClose: Double) {
        self.securityType = securityType; self.period = period; self.candles = candles
        self.maResults = maResults; self.subData = subData; self.prevClose = prevClose
    }
}

// MARK: ── 五档盘口 ───────────────────────────────────────────

public struct EFOrderLevel {
    public let price:    Double
    public let volume:   Int      // 挂单量（手）
    public init(_ price: Double, _ volume: Int) { self.price = price; self.volume = volume }
}

public struct EFOrderBook {
    public let asks: [EFOrderLevel]   // 卖5…卖1（从高到低）
    public let bids: [EFOrderLevel]   // 买1…买5（从高到低）
    public init(asks: [EFOrderLevel], bids: [EFOrderLevel]) {
        self.asks = asks; self.bids = bids
    }
}

/// 分时成交明细
public struct EFTradeRecord {
    public let time:      String
    public let price:     Double
    public let volume:    Int
    public let direction: Int   // 1=主买(红)  -1=主卖(绿)  0=中性
    public init(time: String, price: Double, volume: Int, direction: Int) {
        self.time = time; self.price = price; self.volume = volume; self.direction = direction
    }
}

// MARK: ── 行情摘要（顶部数据） ──────────────────────────────

/// 两种证券类型的行情头部数据
public struct EFQuoteSummary {
    // 通用
    public let code:          String
    public let name:          String
    public let currentPrice:  Double
    public let changeAmount:  Double
    public let changePercent: Double
    public let open:          Double
    public let high:          Double
    public let low:           Double
    public let prevClose:     Double
    public let volume:        Double   // 成交量（手 / 亿手）
    public let amount:        Double   // 成交额（元）
    public let turnoverRate:  Double   // 换手率 %（指数无此字段，传 0）
    public let pe:            Double   // 市盈率（指数无，传 0）

    // 个股专用
    public let totalMarketCap:   Double
    public let floatMarketCap:   Double

    // 指数专用
    public let advancers:  Int?        // 上涨家数
    public let decliners:  Int?        // 下跌家数
    public let unchanged:  Int?
    public let limitUp:    Int?        // 涨停家数
    public let limitDown:  Int?        // 跌停家数
    public let netInflow:  Double?     // 净流入（亿）

    public var isRising: Bool { changeAmount >= 0 }
    public var securityType: EFSecurityType { advancers != nil ? .index : .stock }

    public init(code: String, name: String, currentPrice: Double, changeAmount: Double,
                changePercent: Double, open: Double, high: Double, low: Double, prevClose: Double,
                volume: Double, amount: Double, turnoverRate: Double, pe: Double,
                totalMarketCap: Double = 0, floatMarketCap: Double = 0,
                advancers: Int? = nil, decliners: Int? = nil, unchanged: Int? = nil,
                limitUp: Int? = nil, limitDown: Int? = nil, netInflow: Double? = nil) {
        self.code = code; self.name = name; self.currentPrice = currentPrice
        self.changeAmount = changeAmount; self.changePercent = changePercent
        self.open = open; self.high = high; self.low = low; self.prevClose = prevClose
        self.volume = volume; self.amount = amount; self.turnoverRate = turnoverRate; self.pe = pe
        self.totalMarketCap = totalMarketCap; self.floatMarketCap = floatMarketCap
        self.advancers = advancers; self.decliners = decliners; self.unchanged = unchanged
        self.limitUp = limitUp; self.limitDown = limitDown; self.netInflow = netInflow
    }
}
