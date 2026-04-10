//
//  DemoViewController.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// DemoViewController.swift
// 完整接入示例 — 开箱即用 Demo
// 直接设为 App 的 rootViewController 即可看到效果

import UIKit

// MARK: ── Demo 主页：个股 vs 指数切换 ─────────────────────────

public final class EFDemoViewController: UIViewController {

    // ── 顶部行情摘要区
    private let quoteView = EFQuoteSummaryView()

    // ── 核心图表组件
    public let chartView  = EFStockChartView()

    // ── 切换按钮（演示）
    private let segControl = UISegmentedControl(items: ["个股分时", "指数分时", "日K", "分钟K"])

    private var currentDemo = 0

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = EFColor.background
        setupLayout()
        loadDemo(0)
    }

    private func setupLayout() {
        [quoteView, segControl, chartView].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        segControl.selectedSegmentIndex = 0
        segControl.addTarget(self, action: #selector(segChanged), for: .valueChanged)
        segControl.selectedSegmentTintColor = EFColor.rising
        segControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        segControl.setTitleTextAttributes([.foregroundColor: EFColor.textSecondary], for: .normal)
        segControl.backgroundColor = EFColor.background

        NSLayoutConstraint.activate([
            quoteView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            quoteView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quoteView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            quoteView.heightAnchor.constraint(equalToConstant: 100),

            segControl.topAnchor.constraint(equalTo: quoteView.bottomAnchor, constant: 6),
            segControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            segControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            chartView.topAnchor.constraint(equalTo: segControl.bottomAnchor, constant: 6),
            chartView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chartView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        chartView.delegate = self
    }

    @objc private func segChanged() {
        loadDemo(segControl.selectedSegmentIndex)
    }

    private func loadDemo(_ index: Int) {
        currentDemo = index
        switch index {
        case 0:
            // 个股分时（带右侧盘口）
            quoteView.update(EFMockData.stockQuote())
            chartView.loadTimeline(EFMockData.stockTimeline())

        case 1:
            // 指数分时（全宽，内嵌涨跌家数柱）
            quoteView.update(EFMockData.indexQuote())
            chartView.loadTimeline(EFMockData.indexTimeline())

        case 2:
            // 日 K 线
            quoteView.update(EFMockData.stockQuote())
            let kData = EFMockData.stockKLine(period: .daily)
            chartView.loadKLine(kData)

        case 3:
            // 5分钟 K 线
            quoteView.update(EFMockData.stockQuote())
            let kData = EFMockData.stockKLine(period: .min5)
            chartView.loadKLine(kData)

        default: break
        }
    }
}

// MARK: ── Delegate 实现 ──────────────────────────────────────

extension EFDemoViewController: EFStockChartViewDelegate {

    public func chartView(_ v: EFStockChartView, didSelectPeriod p: EFChartPeriod) {
        print("[Demo] 切换周期: \(p.title)")
        // 实际项目：发起网络请求拉取对应周期数据
    }

    public func chartView(_ v: EFStockChartView, crosshairMoved idx: Int, period: EFChartPeriod) {
        print("[Demo] 十字线: index=\(idx), period=\(period.title)")
        // 可在此更新底部详情面板
    }

    public func chartViewCrosshairHid(_ v: EFStockChartView) {
        print("[Demo] 十字线隐藏")
    }

    public func chartView(_ v: EFStockChartView, visibleRangeChanged r: Range<Int>) {
        if r.lowerBound <= 5 {
            print("[Demo] 触及左边缘，需要加载更多历史数据: range=\(r)")
            // 实际项目：加载更早的历史 K 线数据，合并后重新 loadKLine()
        }
    }
}

// MARK: ── 行情摘要顶部视图 ────────────────────────────────────

final class EFQuoteSummaryView: UIView {

    private let priceLabel   = UILabel()
    private let changeLabel  = UILabel()
    private let pctLabel     = UILabel()
    private let row1Stack    = UIStackView()   // 今开/最高/最低/…
    private let row2Stack    = UIStackView()   // 换手/总手/金额 | 涨跌家数(指数)

    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        backgroundColor = EFColor.background

        priceLabel.font        = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        changeLabel.font       = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        pctLabel.font          = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)

        let topStack = UIStackView(arrangedSubviews: [priceLabel, changeLabel, pctLabel])
        topStack.axis = .horizontal; topStack.spacing = 8; topStack.alignment = .lastBaseline

        [row1Stack, row2Stack].forEach {
            $0.axis = .horizontal; $0.distribution = .fillEqually; $0.spacing = 4
        }

        let main = UIStackView(arrangedSubviews: [topStack, row1Stack, row2Stack])
        main.axis = .vertical; main.spacing = 4
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            main.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            main.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            main.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
        ])
    }

    func update(_ q: EFQuoteSummary) {
        let c = q.isRising ? EFColor.rising : EFColor.falling
        priceLabel.text       = EFFormat.price(q.currentPrice)
        priceLabel.textColor  = c
        changeLabel.text      = EFFormat.priceSigned(q.changeAmount)
        changeLabel.textColor = c
        pctLabel.text         = EFFormat.percent(q.changePercent, signed: true)
        pctLabel.textColor    = c

        // 清空旧数据
        row1Stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        row2Stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if q.securityType == .index {
            // 指数行1：今开/最高/最低/换手
            for (t, v) in [("今开", EFFormat.price(q.open)), ("最高", EFFormat.price(q.high)),
                           ("最低", EFFormat.price(q.low)), ("换手", EFFormat.percent(q.turnoverRate))] {
                row1Stack.addArrangedSubview(metricView(title: t, value: v))
            }
            // 指数行2：涨/平/跌/涨停/跌停
            let adv = q.advancers ?? 0, unch = q.unchanged ?? 0, dec = q.decliners ?? 0
            let lu  = q.limitUp ?? 0, ld = q.limitDown ?? 0
            let advStr = "\(adv)/\(unch)/\(dec)"
            let luStr  = "\(lu)/\(ld)"
            for (t, v, clr) in [("涨跌家数", advStr, EFColor.textPrimary),
                                 ("涨跌停", luStr, EFColor.textPrimary),
                                 ("总手", EFFormat.volume(q.volume, isIndex: true), EFColor.textPrimary),
                                 ("金额", EFFormat.amount(q.amount), EFColor.textPrimary)] {
                row2Stack.addArrangedSubview(metricView(title: t, value: v, valueColor: clr))
            }
        } else {
            // 个股行1
            for (t, v, c2) in [("今开", EFFormat.price(q.open), EFColor.textPrimary),
                                ("最高", EFFormat.price(q.high), EFColor.rising),
                                ("最低", EFFormat.price(q.low), EFColor.falling),
                                ("换手", EFFormat.percent(q.turnoverRate), EFColor.textPrimary)] {
                row1Stack.addArrangedSubview(metricView(title: t, value: v, valueColor: c2))
            }
            // 个股行2
            for (t, v) in [("总手", EFFormat.volume(q.volume)),
                           ("金额", EFFormat.amount(q.amount)),
                           ("市盈动", EFFormat.price(q.pe)),
                           ("市值", EFFormat.amount(q.totalMarketCap))] {
                row2Stack.addArrangedSubview(metricView(title: t, value: v))
            }
        }
    }

    private func metricView(title: String, value: String,
                             valueColor: UIColor = EFColor.textPrimary) -> UIView {
        let tv = UILabel(); tv.text = title; tv.font = .systemFont(ofSize: 10)
        tv.textColor = EFColor.textSecondary
        let vv = UILabel(); vv.text = value
        vv.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        vv.textColor = valueColor
        let s = UIStackView(arrangedSubviews: [tv, vv])
        s.axis = .vertical; s.spacing = 1; s.alignment = .leading
        return s
    }
}

// MARK: ── AppDelegate 最简接入 ──────────────────────────────────
/*
 最简集成（3 步）：

 步骤 1 — 将 EFStockChart 文件夹拖入 Xcode 工程（Add Files to...）

 步骤 2 — AppDelegate.swift

     func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
         window = UIWindow(frame: UIScreen.main.bounds)
         window?.rootViewController = EFDemoViewController()
         window?.makeKeyAndVisible()
         return true
     }

 步骤 3 — 运行即可看到效果 ✅

 ───────────────────────────────────────────────────────────────
 实际项目接入（嵌入已有 VC）：

     let chartView = EFStockChartView()
     chartView.delegate = self
     view.addSubview(chartView)
     // 设置约束...

     // 加载分时
     let data = EFTimelineData(
         securityType: .stock, stockCode: "600519", stockName: "贵州茅台",
         prevClose: 1465.02, upperLimit: 1611.52, lowerLimit: 1318.52,
         points: yourTimelinePoints
     )
     chartView.loadTimeline(data)

     // 或加载 K 线（先异步计算指标）
     EFIndicatorEngine.calculateAsync(candles: yourCandles) { result in
         let volData = EFSubData.volume(result.volumeData)
         let macdData = EFSubData.macd(result.macd)
         let kData = EFKLineData(
             securityType: .stock,
             period: .daily,
             candles: yourCandles,
             maResults: result.maLines,
             subData: [macdData, volData],
             prevClose: yourPrevClose
         )
         self.chartView.loadKLine(kData)
     }
 */
