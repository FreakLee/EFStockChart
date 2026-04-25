//
//  EFChartConfig.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 图表运行时配置（可在外部修改，影响渲染行为）

import UIKit

/// 图表运行时配置 — 注入到 EFStockChartView
public struct EFChartConfig {

    // ── 蜡烛图设置
    public var candleStyle: CandleStyle  = .solid      // 实心/空心
    public var maPeriods:   [Int]        = [5,10,20,60,120,250]
    public var subCount:    Int          = 2            // 同时显示副图数量（1-4）

    // ── 复权类型
    public var adjustType: AdjustType   = .forward

    // ── 坐标类型
    public var scaleType:  ScaleType    = .linear

    // ── 分时设置
    public var showAvgLine:   Bool      = true
    public var showLimitLine: Bool      = true   // 涨跌停参考线
    public var showAuctionPeriod: Bool  = false  // 集合竞价段

    // 默认单例（可直接修改）
    public static var shared = EFChartConfig()
    public init() {}
}

public enum CandleStyle: Int {
    case solid    // 实心K线（默认）
    case hollow   // 空心K线（东财默认）
    case bar      // 美国线
    case mountain // 山形线（分时用）
}

public enum AdjustType: Int {
    case none      // 不复权
    case forward   // 前复权
    case backward  // 后复权
}

public enum ScaleType: Int {
    case linear      // 普通坐标
    case percentage  // 百分比坐标
    case log         // 对数坐标
}
