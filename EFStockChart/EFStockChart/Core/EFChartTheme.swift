//
//  EFChartTheme.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// EFChartTheme.swift
// 主题系统 — 精确对应东方财富截图配色

import UIKit
import CoreGraphics

// MARK: ── 颜色系统 ──────────────────────────────────────────

public struct EFColor {
    // ── 价格涨跌
    static let rising   = UIColor(r: 238, g: 61,  b: 60)   // #EE3D3C 涨（红）
    static let falling  = UIColor(r: 26,  g: 181, b: 77)   // #1AB54D 跌（绿）
    static let neutral  = UIColor(r: 204, g: 204, b: 204)  // #CCCCCC 平

    // ── 分时图
    static let timelineMain    = UIColor(r: 51,  g: 178, b: 255)  // #33B2FF 蓝色折线
    static let timelineAvg     = UIColor(r: 255, g: 204, b: 0)    // #FFCC00 均价线（黄）
    static let timelineFillTop = UIColor(r: 51,  g: 178, b: 255, a: 0.36)
    static let timelineFillBot = UIColor(r: 51,  g: 178, b: 255, a: 0.0)

    // 指数分时内嵌涨跌家数柱（比正常柱子矮，透明度低）
    static let indexAdvancer = UIColor(r: 238, g: 61,  b: 60,  a: 0.5)
    static let indexDecliner = UIColor(r: 26,  g: 181, b: 77,  a: 0.5)

    // ── MA 线（严格按截图顺序）
    // MA5=白, MA10=黄, MA20=紫, MA60=蓝, MA120=粉, MA250=橙
    static let ma5   = UIColor(r: 255, g: 255, b: 255)  // 白
    static let ma10  = UIColor(r: 255, g: 200, b: 0)    // 黄
    static let ma20  = UIColor(r: 204, g: 102, b: 255)  // 紫
    static let ma60  = UIColor(r: 0,   g: 153, b: 255)  // 蓝
    static let ma120 = UIColor(r: 255, g: 102, b: 204)  // 粉
    static let ma250 = UIColor(r: 255, g: 128, b: 0)    // 橙

    static let maColors: [UIColor] = [ma5, ma10, ma20, ma60, ma120, ma250]

    // ── MACD
    static let difLine  = UIColor(r: 255, g: 200, b: 0)    // 黄 DIF
    static let deaLine  = UIColor(r: 255, g: 255, b: 255)  // 白 DEA
    static let macdBarUp   = rising
    static let macdBarDown = falling

    // ── KDJ
    static let kLine = UIColor(r: 255, g: 200, b: 0)    // 黄 K
    static let dLine = UIColor(r: 255, g: 255, b: 255)  // 白 D
    static let jLine = UIColor(r: 204, g: 102, b: 255)  // 紫 J

    // ── 成交量 MA
    static let volMa1 = UIColor(r: 255, g: 200, b: 0)    // 黄
    static let volMa2 = UIColor(r: 204, g: 102, b: 255)  // 粉/紫

    // ── 网格 & 边框
    static let grid      = UIColor(r: 44, g: 44, b: 44)    // 细网格线
    static let border    = UIColor(r: 60, g: 60, b: 60)    // 外边框
    static let prevClose = UIColor(r: 120, g: 120, b: 120, a: 0.8)  // 昨收虚线

    // ── 背景
    static let background = UIColor(r: 16, g: 16, b: 16)   // 主背景
    static let panel      = UIColor(r: 16, g: 16, b: 16)   // 图表面板

    // ── 文字
    static let textPrimary   = UIColor(r: 230, g: 230, b: 230)
    static let textSecondary = UIColor(r: 140, g: 140, b: 140)
    static let textLabel     = UIColor(r: 100, g: 100, b: 100)

    // ── 十字线
    static let crosshair      = UIColor(r: 180, g: 180, b: 180, a: 0.9)
    static let crosshairLabel = UIColor(r: 200, g: 200, b: 200)

    // ── 盘口
    static let askLabel  = rising    // 卖档价格（红）
    static let bidLabel  = falling   // 买档价格（绿）
    static let orderBookBg = UIColor(r: 20, g: 20, b: 20)

    // ── Tooltip
    static let tooltipBg     = UIColor(r: 25, g: 25, b: 30, a: 0.95)
    static let tooltipBorder = UIColor(r: 70, g: 70, b: 70)
}

extension UIColor {
    fileprivate convenience init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.init(red: r/255, green: g/255, blue: b/255, alpha: a)
    }
}

// MARK: ── 布局常量 ──────────────────────────────────────────

public struct EFLayout {
    // 周期切换栏
    static let periodBarH: CGFloat = 36

    // 指标信息行（MA值显示）
    static let infoBarH: CGFloat = 32

    // 主图 / 副图比例
    static let mainRatio:  CGFloat = 0.60
    static let subRatio:   CGFloat = 0.22   // 单个副图
    static let subDivider: CGFloat = 20     // 副图切换标题栏高

    // 图表内边距
    static let priceAxisW: CGFloat = 58     // 右侧价格轴宽度
    static let timeAxisH:  CGFloat = 18     // 底部时间轴高度
    static let topPad:     CGFloat = 6

    // 个股分时：右侧盘口区域比例（约 42%）
    static let orderBookRatio: CGFloat = 0.42

    // K线
    static let candleMinW:  CGFloat = 2
    static let candleMaxW:  CGFloat = 48
    static let candleDefW:  CGFloat = 7
    static let candleGap:   CGFloat = 0.2   // 间距占比

    // 网格
    static let mainRows: Int = 5
    static let subRows:  Int = 3

    // 字体
    static let axisFont:    UIFont = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    static let labelFont:   UIFont = .systemFont(ofSize: 10)
    static let infoFont:    UIFont = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    static let tooltipFont: UIFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
}

// MARK: ── 数字格式化 ────────────────────────────────────────

public struct EFFormat {
    static func price(_ v: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", v)
    }
    static func priceSigned(_ v: Double) -> String {
        String(format: "%+.2f", v)
    }
    static func percent(_ v: Double, signed: Bool = false) -> String {
        signed ? String(format: "%+.2f%%", v) : String(format: "%.2f%%", v)
    }
    static func volume(_ v: Double, isIndex: Bool = false) -> String {
        if isIndex {
            if v >= 1e8 { return String(format: "%.2f亿", v/1e8) }
            if v >= 1e4 { return String(format: "%.2f万", v/1e4) }
            return String(format: "%.0f", v)
        }
        if v >= 1e8 { return String(format: "%.2f亿", v/1e8) }
        if v >= 1e4 { return String(format: "%.2f万", v/1e4) }
        return String(format: "%.0f", v)
    }
    static func amount(_ v: Double) -> String {
        if v >= 1e8 { return String(format: "%.2f亿", v/1e8) }
        if v >= 1e4 { return String(format: "%.0f万", v/1e4) }
        return String(format: "%.2f", v)
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/dd"; return f
    }()
    private static let fullFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
    private static let ymdFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f
    }()

    static func time(_ d: Date)     -> String { timeFmt.string(from: d) }
    static func date(_ d: Date)     -> String { dateFmt.string(from: d) }
    static func full(_ d: Date)     -> String { fullFmt.string(from: d) }
    static func ymd(_ d: Date)      -> String { ymdFmt.string(from: d) }
}
