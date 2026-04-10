//
//  EFStockChartView.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// EFStockChartView.swift
// 主图表容器视图 — iOS 15+，Swift 5.7 兼容
// 零第三方依赖，纯 UIKit + Core Graphics

import UIKit

// MARK: ── Delegate ──────────────────────────────────────────

public protocol EFStockChartViewDelegate: AnyObject {
    /// 用户切换了周期（分时/五日/日K等）
    func chartView(_ v: EFStockChartView, didSelectPeriod p: EFChartPeriod)
    /// 十字线移动时回调
    func chartView(_ v: EFStockChartView, crosshairMoved idx: Int, period: EFChartPeriod)
    /// 十字线隐藏
    func chartViewCrosshairHid(_ v: EFStockChartView)
    /// K线可见区间变化（用于分页加载更多历史数据）
    func chartView(_ v: EFStockChartView, visibleRangeChanged r: Range<Int>)
}

public extension EFStockChartViewDelegate {
    func chartView(_ v: EFStockChartView, didSelectPeriod p: EFChartPeriod) {}
    func chartView(_ v: EFStockChartView, crosshairMoved idx: Int, period: EFChartPeriod) {}
    func chartViewCrosshairHid(_ v: EFStockChartView) {}
    func chartView(_ v: EFStockChartView, visibleRangeChanged r: Range<Int>) {}
}

// MARK: ── EFStockChartView ──────────────────────────────────

public final class EFStockChartView: UIView {

    // ─────────────────────── 公开属性 ───────────────────────
    public weak var delegate: EFStockChartViewDelegate?
    public var config = EFChartConfig.shared { didSet { triggerFullRedraw() } }
    public private(set) var currentPeriod: EFChartPeriod = .timeline

    // ─────────────────────── 数据 ───────────────────────────
    private var timelineData: EFTimelineData?
    private var kLineData:    EFKLineData?

    // ─────────────────────── 渲染器 ─────────────────────────
    private let tlRenderer = EFTimelineRenderer()
    private let klRenderer = EFKLineRenderer()

    // ─────────────────────── K线状态 ────────────────────────
    private var visibleRange: Range<Int> = 0..<50
    private var candleWidth:  CGFloat    = EFLayout.candleDefW
    private var pinchStartCW: CGFloat    = EFLayout.candleDefW
    private var panStartRange: Range<Int> = 0..<50

    // ─────────────────────── 十字线 ─────────────────────────
    private var crosshairActive = false
    private var crosshairIndex  = 0

    // ─────────────────────── 渲染队列 ───────────────────────
    private let renderQ = DispatchQueue(label: "ef.chart.render", qos: .userInteractive)
    private var renderToken = UUID()

    // ─────────────────────── 子视图 ─────────────────────────
    /// 周期切换栏（分时/五日/日K/周K/月K/更多）
    public  let periodBar      = EFPeriodBar()
    /// K线 MA 信息行
    private let infoBar        = EFInfoBar()
    /// 主图 ImageView
    private let mainImageView  = UIImageView()
    /// 十字线覆盖层（独立于主图刷新）
    private let crosshairLayer = EFCrosshairLayer()
    /// 副图面板数组（最多 4 个）
    private var subPanels      = [EFSubPanel]()
    /// 个股分时右侧盘口
    private let orderBookView  = EFOrderBookView()

    // ─────────────────────── Init ───────────────────────────

    public override init(frame: CGRect) { super.init(frame: frame); setup() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = EFColor.background
        mainImageView.contentMode = .scaleAspectFill
        crosshairLayer.isUserInteractionEnabled = false

        addSubview(periodBar)
        addSubview(infoBar)
        addSubview(mainImageView)
        mainImageView.addSubview(crosshairLayer)
        addSubview(orderBookView)

        periodBar.onPeriodSelected = { [weak self] p in self?.handlePeriodSelected(p) }

        // 预创建 4 个副图面板（按需显示/隐藏）
        for i in 0..<4 {
            let panel = EFSubPanel()
            panel.setIndicator(defaultIndicator(for: i))
            panel.isHidden = true
            panel.titleBar.onIndicatorChanged = { [weak self, weak panel] ind in
                guard let self = self, let panel = panel else { return }
                panel.setIndicator(ind)
                self.triggerSubRedraw(panel: panel)
            }
            addSubview(panel)
            subPanels.append(panel)
        }

        setupGestures()
    }

    // ─────────────────────── 布局 ───────────────────────────

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateFrames()
        triggerFullRedraw()
    }

    private func updateFrames() {
        let w = bounds.width, h = bounds.height
        var y: CGFloat = 0

        // 1. 周期栏
        periodBar.frame = CGRect(x: 0, y: y, width: w, height: EFLayout.periodBarH)
        y += EFLayout.periodBarH

        // 2. K线 MA 信息行（分时图不显示）
        let isKLine = isKLinePeriod
        infoBar.isHidden = !isKLine
        if isKLine {
            infoBar.frame = CGRect(x: 0, y: y, width: w, height: EFLayout.infoBarH)
            y += EFLayout.infoBarH
        }

        // 3. 计算剩余高度
        let remaining = h - y
        let subCnt    = visibleSubCount()
        let mainH     = remaining * (subCnt == 0 ? 0.72 : EFLayout.mainRatio)
        let eachSubH  = subCnt > 0 ? remaining * EFLayout.subRatio : 0

        // 4. 个股分时：右侧盘口
        let isStockTimeline = (currentPeriod == .timeline || currentPeriod == .fiveDay)
            && (timelineData?.securityType == .stock || timelineData?.securityType == .etf)
        let chartW = isStockTimeline
            ? w * (1 - EFLayout.orderBookRatio)
            : w

        // 5. 主图
        mainImageView.frame  = CGRect(x: 0, y: y, width: chartW, height: mainH)
        crosshairLayer.frame = mainImageView.bounds
        y += mainH

        // 6. 副图
        for (i, panel) in subPanels.enumerated() {
            let isVisible = i < subCnt
            panel.isHidden = !isVisible
            if isVisible {
                panel.frame = CGRect(x: 0, y: y, width: chartW, height: eachSubH)
                y += eachSubH
            }
        }

        // 7. 盘口
        orderBookView.isHidden = !isStockTimeline
        if isStockTimeline {
            let obY = mainImageView.frame.minY
            let obH = mainH + CGFloat(subCnt) * eachSubH
            orderBookView.frame = CGRect(x: chartW, y: obY, width: w - chartW, height: obH)
        }
    }

    // 返回当前应显示的副图数量
    private func visibleSubCount() -> Int {
        switch currentPeriod {
        case .timeline, .fiveDay:
            // 分时图：1个副图（MACD 或 成交量）
            return 1
        case .kLine:
            guard let d = kLineData else { return 1 }
            return Swift.min(config.subCount, d.subData.count)
        }
    }

    private var isKLinePeriod: Bool {
        if case .kLine = currentPeriod { return true }
        return false
    }

    // 副图默认指标顺序
    private func defaultIndicator(for index: Int) -> EFSubIndicator {
        [.macd, .kdj, .rsi, .volume][Swift.min(index, 3)]
    }

    // ─────────────────────── 数据加载（公开 API）──────────────

    /// 加载分时数据（个股或指数均可）
    public func loadTimeline(_ data: EFTimelineData) {
        timelineData = data
        currentPeriod = data.period
        crosshairActive = false
        crosshairLayer.hide()
        periodBar.setSelected(data.period)
        if let ob = data.orderBook { orderBookView.update(ob) }
        setNeedsLayout()
    }

    /// 加载 K 线数据
    public func loadKLine(_ data: EFKLineData) {
        kLineData = data
        currentPeriod = .kLine(data.period)
        crosshairActive = false
        crosshairLayer.hide()
        periodBar.setSelected(currentPeriod)

        // 同步副图面板指标与数据
        for (i, panel) in subPanels.enumerated() {
            if i < data.subData.count {
                panel.setIndicator(indicatorFrom(subData: data.subData[i]))
            }
        }

        // 初始可见范围：最右侧 N 根
        let defaultVis = computeDefaultVisibleCount()
        let total      = data.candles.count
        visibleRange   = Swift.max(0, total - defaultVis)..<total

        setNeedsLayout()
    }

    /// 追加新分时点（实时推送用）
    public func appendTimelinePoints(_ pts: [EFTimePoint]) {
        guard let d = timelineData else { return }
        let newPts = d.points + pts
        timelineData = EFTimelineData(
            securityType: d.securityType, stockCode: d.stockCode, stockName: d.stockName,
            prevClose: d.prevClose, upperLimit: d.upperLimit, lowerLimit: d.lowerLimit,
            points: newPts, period: d.period, orderBook: d.orderBook
        )
        triggerFullRedraw()
    }

    /// 更新盘口数据（实时推送用）
    public func updateOrderBook(_ ob: EFOrderBook) {
        timelineData?.orderBook = ob
        orderBookView.update(ob)
    }

    /// 更新分时成交明细
    public func updateTradeRecords(_ trades: [EFTradeRecord]) {
        orderBookView.updateTrades(trades)
    }

    // ─────────────────────── 周期切换 ───────────────────────

    private func handlePeriodSelected(_ period: EFChartPeriod) {
        guard period != currentPeriod else { return }
        currentPeriod = period
        crosshairActive = false
        crosshairLayer.hide()
        setNeedsLayout()
        delegate?.chartView(self, didSelectPeriod: period)
        // 通知外部加载对应周期数据
    }

    // ─────────────────────── 渲染调度 ───────────────────────

    private func triggerFullRedraw() {
        let token = UUID(); renderToken = token
        enqueueRender(token: token, fullRedraw: true)
    }

    private func triggerSubRedraw(panel: EFSubPanel) {
        let token = UUID(); renderToken = token
        enqueueRender(token: token, fullRedraw: false, targetPanel: panel)
    }

    private func enqueueRender(token: UUID, fullRedraw: Bool, targetPanel: EFSubPanel? = nil) {
        let mainRect  = mainImageView.bounds
        let subFrames = subPanels.filter { !$0.isHidden }.map { (panel: $0, rect: $0.imageView.bounds) }

        let tlData   = timelineData
        let klData   = kLineData
        let period   = currentPeriod
        let vis      = visibleRange
        let cw       = candleWidth
        let cIdx: Int? = crosshairActive ? crosshairIndex : nil
        let tlR      = tlRenderer
        let klR      = klRenderer
        // 在主线程提前捕获 scale（traitCollection 只能在主线程访问）
        let screenScale = self.traitCollection.displayScale

        renderQ.async { [weak self] in
            guard let self = self, self.renderToken == token else { return }

            var mainImg: CGImage?
            var subImgs: [(UIImageView, CGImage)] = []

            // ── 主图渲染
            switch period {
            case .timeline, .fiveDay:
                if let d = tlData, mainRect.width > 0 {
                    mainImg = tlR.renderMain(data: d, rect: mainRect, crosshairIdx: cIdx)
                }
            case .kLine:
                if let d = klData, mainRect.width > 0 {
                    mainImg = klR.renderMain(data: d, rect: mainRect, visibleRange: vis,
                                             crosshairIdx: cIdx, candleWidth: cw)
                }
            }

            // ── 副图渲染
            for (panel, rect) in subFrames {
                guard rect.width > 0, rect.height > 0 else { continue }
                if let tp = targetPanel, tp !== panel { continue }  // 只刷指定副图

                var img: CGImage?
                switch period {
                case .timeline, .fiveDay:
                    if let d = tlData {
                        // 分时图副图：MACD
                        let closes = d.points.map(\.price)
                        if closes.count > 26 {
                            let r = EFIndicatorEngine.macd(closes: closes)
                            if let ctx = makeOffscreenContext(size: rect.size, scale: screenScale) {
                                ctx.setFillColor(EFColor.panel.cgColor)
                                ctx.fill(CGRect(origin: .zero, size: rect.size))
                                let subR = tlR.subContentRect(CGRect(origin: .zero, size: rect.size))
                                tlR.drawMACDSub(ctx: ctx, result: r, count: closes.count,
                                                 total: EFTimelineRenderer.totalSlots(for: d.period),
                                                 content: subR, crosshairIdx: cIdx)
                                ctx.setStrokeColor(EFColor.border.cgColor); ctx.setLineWidth(0.5); ctx.stroke(subR)
                                img = ctx.makeImage()
                            }
                        }
                    }
                case .kLine:
                    if let d = klData {
                        let panelIdx = subFrames.firstIndex(where: { $0.panel === panel }) ?? 0
                        if panelIdx < d.subData.count {
                            img = klR.renderSub(data: d, subIndex: panelIdx, rect: rect,
                                                visibleRange: vis, candleWidth: cw, crosshairIdx: cIdx)
                        }
                    }
                }
                if let iv = panel.imageView as UIImageView?, let img = img {
                    subImgs.append((iv, img))
                }
            }

            DispatchQueue.main.async {
                guard self.renderToken == token else { return }
                if let img = mainImg {
                    self.mainImageView.image = UIImage(cgImage: img)
                }
                for (iv, img) in subImgs {
                    iv.image = UIImage(cgImage: img)
                }
                self.updateInfoBar()
            }
        }
    }

    // ─────────────────────── MA 信息行 ──────────────────────

    private func updateInfoBar() {
        guard let data = kLineData else { return }
        let ci = crosshairActive ? crosshairIndex : (data.candles.count - 1)
        infoBar.update(maResults: data.maResults, index: ci)
    }

    // ─────────────────────── 手势识别 ───────────────────────

    private func setupGestures() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        longPress.minimumPressDuration = 0.28
        longPress.delegate = self
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap))
        tap.require(toFail: longPress)
        addGestureRecognizer(tap)
    }

    @objc private func onLongPress(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began, .changed:
            let loc = gr.location(in: mainImageView)
            activateCrosshair(at: loc)
        case .ended:
            // 东方财富：长按结束后十字线保留 3 秒
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.dismissCrosshair()
            }
        default: break
        }
    }

    @objc private func onPan(_ gr: UIPanGestureRecognizer) {
        // 十字线激活时：拖动移动十字线
        if crosshairActive {
            activateCrosshair(at: gr.location(in: mainImageView))
            return
        }
        // K线图：左右平移
        guard case .kLine = currentPeriod, let d = kLineData else { return }
        if gr.state == .began { panStartRange = visibleRange }

        let dx     = gr.translation(in: self).x
        let shift  = Int(-dx / Swift.max(1, candleWidth))
        let cnt    = d.candles.count
        let visLen = visibleRange.count
        let ns     = (panStartRange.lowerBound + shift).clamped(lo: 0, hi: Swift.max(0, cnt - visLen))
        let nr     = ns..<Swift.min(ns + visLen, cnt)

        guard nr != visibleRange else { return }
        visibleRange = nr
        triggerFullRedraw()
        delegate?.chartView(self, visibleRangeChanged: nr)

        // 触达左边缘：请求加载更多历史数据
        if ns <= 5 {
            delegate?.chartView(self, visibleRangeChanged: nr)
        }
    }

    @objc private func onPinch(_ gr: UIPinchGestureRecognizer) {
        guard case .kLine = currentPeriod, let d = kLineData else { return }
        if gr.state == .began { pinchStartCW = candleWidth }

        let nw    = (pinchStartCW * gr.scale).clamped(lo: EFLayout.candleMinW, hi: EFLayout.candleMaxW)
        guard abs(nw - candleWidth) > 0.15 else { return }
        candleWidth = nw

        // 以可见区间右端为锚点，重新计算左边界
        let newVis = computeDefaultVisibleCount()
        let total  = d.candles.count
        let start  = Swift.max(0, visibleRange.upperBound - newVis)
        visibleRange = start..<Swift.min(start + newVis, total)
        triggerFullRedraw()
    }

    @objc private func onTap() { dismissCrosshair() }

    // ─────────────────────── 十字线 ─────────────────────────

    private func activateCrosshair(at loc: CGPoint) {
        crosshairActive = true
        crosshairIndex  = locationToIndex(loc)

        // 十字线覆盖层（高频 setNeedsDisplay，不触发主图重渲）
        crosshairLayer.show(x: loc.x, y: loc.y, bounds: mainImageView.bounds)

        // 主图 + 副图需要重渲（含 tooltip）
        triggerFullRedraw()
        delegate?.chartView(self, crosshairMoved: crosshairIndex, period: currentPeriod)
    }

    private func dismissCrosshair() {
        guard crosshairActive else { return }
        crosshairActive = false
        crosshairLayer.hide()
        triggerFullRedraw()
        delegate?.chartViewCrosshairHid(self)
    }

    /// 将屏幕坐标转换为数据索引
    private func locationToIndex(_ loc: CGPoint) -> Int {
        let contentW = mainImageView.bounds.width - EFLayout.priceAxisW
        guard contentW > 0 else { return 0 }
        let ratio = (loc.x / contentW).clamped(lo: 0, hi: 1)

        switch currentPeriod {
        case .timeline, .fiveDay:
            let total = EFTimelineRenderer.totalSlots(for: currentPeriod)
            let raw   = Int(ratio * CGFloat(total))
            let maxIdx = Swift.max(0, (timelineData?.points.count ?? 1) - 1)
            return raw.clamped(lo: 0, hi: maxIdx)

        case .kLine:
            let vis = visibleRange
            guard vis.count > 1 else { return vis.lowerBound }
            let i   = Int(ratio * CGFloat(vis.count - 1) + 0.5)
            let maxIdx = Swift.max(0, (kLineData?.candles.count ?? 1) - 1)
            return (vis.lowerBound + i).clamped(lo: 0, hi: maxIdx)
        }
    }

    // ─────────────────────── 工具 ───────────────────────────

    private func computeDefaultVisibleCount() -> Int {
        let w = Swift.max(mainImageView.bounds.width, bounds.width - EFLayout.priceAxisW)
        return Swift.max(20, Int(w / candleWidth))
    }

    private func indicatorFrom(subData: EFSubData) -> EFSubIndicator {
        switch subData {
        case .macd:   return .macd
        case .kdj:    return .kdj
        case .rsi:    return .rsi
        case .volume: return .volume
        }
    }
}

// MARK: ── UIGestureRecognizerDelegate ───────────────────────

extension EFStockChartView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ a: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer
    ) -> Bool { true }
}
