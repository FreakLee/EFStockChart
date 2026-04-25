//
//  EFStockChartView.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 主图表容器视图 — 副图可插拔

import UIKit

// MARK: - Delegate

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

// MARK: - EFStockChartView

public final class EFStockChartView: UIView {

    // ── 公开
    public weak var delegate: EFStockChartViewDelegate?
    public private(set) var currentPeriod: EFChartPeriod = .timeline

    // ── 数据
    private var timelineData: EFTimelineData?
    private var kLineData:    EFKLineData?

    // ── 渲染器（不持有状态，纯函数）
    private let tlR = EFTimelineRenderer()
    private let klR = EFKLineRenderer()

    // ── K线状态
    private var visibleRange:  Range<Int> = 0..<50
    private var candleWidth:   CGFloat    = EFLayout.candleDefW
    private var pinchStartCW:  CGFloat    = EFLayout.candleDefW
    private var panStartRange: Range<Int> = 0..<50

    // ── 十字线
    private var crosshairActive = false
    private var crosshairIndex  = 0

    // ── 渲染队列
    private let renderQ   = DispatchQueue(label: "ef.render", qos: .userInteractive)
    private var renderToken = UUID()

    // ── 动量滚动
    private lazy var animator    = UIDynamicAnimator(referenceView: self)
    private lazy var dynamicItem = EFDynamicItem()
    private weak var decelerationBehavior: UIDynamicItemBehavior?
    private var decelerationStartX: CGFloat = 0

    // ── 防抖：skipSub 渲染后延迟触发一次全量渲染（含副图）
    private var subSyncTimer: Timer?

    // ──────────────────────────── 子视图 ────────────────────────────

    /// 周期切换栏（分时/五日/日K/周K/月K/更多）
    public  let periodBar      = EFPeriodBar()
    /// K线 MA 信息行（只在 K线 模式下显示）
    private let infoBar        = EFInfoBar()
    /// 主图 ImageView
    private let mainImageView  = UIImageView()
    /// 十字线覆盖层（高频刷新，独立于主图）
    private let crosshairLayer = EFCrosshairLayer()
    /// 副图面板（最多 4 个，可插拔）
    private var subPanels      = [EFSubPanel]()
    /// 个股分时右侧盘口（securityType == .stock 时显示）
    private let orderBookView  = EFOrderBookView()

    // ────────────────────────── Init ────────────────────────────────

    public override init(frame: CGRect) { super.init(frame: frame); setup() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = EFColor.background
        mainImageView.contentMode = .scaleToFill
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
            panel.imageView.contentMode = .scaleToFill
            panel.setIndicator(defaultIndicator(for: i))
            panel.isHidden = true
            panel.titleBar.onIndicatorChanged = { [weak self, weak panel] ind in
                guard let self = self, let panel = panel else { return }
                panel.setIndicator(ind)
                self.renderSinglePanel(panel: panel)
            }
            addSubview(panel)
            subPanels.append(panel)
        }

        setupGestures()
    }

    // ────────────────────────── 布局 ────────────────────────────────

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateFrames()
        triggerRender()
    }

    private func updateFrames() {
        let w = bounds.width, h = bounds.height
        var y: CGFloat = 0

        // 1. 周期切换栏
        periodBar.frame = CGRect(x: 0, y: y, width: w, height: EFLayout.periodBarH)
        y += EFLayout.periodBarH

        // 2. K线 MA 信息行
        let showInfo = isKLinePeriod
        infoBar.isHidden = !showInfo
        if showInfo {
            infoBar.frame = CGRect(x: 0, y: y, width: w, height: EFLayout.infoBarH)
            y += EFLayout.infoBarH
        }

        // 3. 计算图表宽度（个股分时：右侧盘口）
        let isStockTL = (currentPeriod == .timeline || currentPeriod == .fiveDay)
            && (timelineData?.securityType == .stock || timelineData?.securityType == .etf)
        let chartW = isStockTL ? w * (1 - EFLayout.orderBookRatio) : w

        // 4. 主图 + 副图高度分配
        let remaining = h - y
        let subCnt    = visibleSubCount()
        let mainH     = remaining * EFLayout.mainRatio
        let eachSubH  = subCnt > 0 ? (remaining - mainH) / CGFloat(subCnt) : 0

        mainImageView.frame  = CGRect(x: 0, y: y, width: chartW, height: mainH)
        crosshairLayer.frame = mainImageView.bounds
        y += mainH

        // 5. 副图
        for (i, panel) in subPanels.enumerated() {
            let visible = i < subCnt
            panel.isHidden = !visible
            if visible {
                panel.frame = CGRect(x: 0, y: y, width: chartW, height: eachSubH)
                y += eachSubH
            }
        }

        // 6. 盘口
        orderBookView.isHidden = !isStockTL
        if isStockTL {
            let obY = mainImageView.frame.minY
            let obH = mainImageView.frame.height + CGFloat(subCnt) * eachSubH
            orderBookView.frame = CGRect(x: chartW, y: obY, width: w - chartW, height: obH)
        }
    }

    private var isKLinePeriod: Bool {
        if case .kLine = currentPeriod { return true }
        return false
    }

    private func visibleSubCount() -> Int {
        switch currentPeriod {
        case .timeline, .fiveDay:
            return 1   // 分时图固定 1 个副图（可切换 MACD/VOL）
        case .kLine:
            guard let d = kLineData else { return 1 }
            return Swift.min(d.subData.count, 4)
        }
    }

    private func defaultIndicator(for i: Int) -> EFSubIndicator {
        [.macd, .kdj, .rsi, .volume][Swift.min(i, 3)]
    }

    // ────────────────────── 数据加载（公开 API）────────────────────

    public func loadTimeline(_ data: EFTimelineData) {
        timelineData = data
        currentPeriod = data.period
        crosshairActive = false
        crosshairLayer.hide()
        periodBar.setSelected(data.period)
        if let ob = data.orderBook { orderBookView.update(ob) }
        setNeedsLayout()
    }

    public func loadKLine(_ data: EFKLineData) {
        kLineData    = data
        currentPeriod = .kLine(data.period)
        crosshairActive = false
        crosshairLayer.hide()
        periodBar.setSelected(currentPeriod)

        // 初始可见范围：最右侧 N 根
        let vis   = computeDefaultVisCount()
        let total = data.candles.count
        visibleRange = Swift.max(0, total - vis)..<total

        // 同步副图面板指标名称
        for (i, panel) in subPanels.enumerated() {
            if i < data.subData.count {
                panel.setIndicator(indicatorType(of: data.subData[i]))
            }
        }

        setNeedsLayout()
    }

    public func appendTimelinePoints(_ pts: [EFTimePoint]) {
        guard pts.isEmpty == false else { return }
        timelineData?.points.append(contentsOf: pts)   // COW in-place，O(1) amortized
        triggerRender()
    }

    public func updateOrderBook(_ ob: EFOrderBook) {
        timelineData?.orderBook = ob
        orderBookView.update(ob)
    }

    public func updateTradeRecords(_ trades: [EFTradeRecord]) {
        orderBookView.updateTrades(trades)
    }

    // ────────────────────────── 周期切换 ────────────────────────────

    private func handlePeriodSelected(_ period: EFChartPeriod) {
        guard period != currentPeriod else { return }
        currentPeriod = period
        crosshairActive = false
        crosshairLayer.hide()
        setNeedsLayout()
        delegate?.chartView(self, didSelectPeriod: period)
    }

    // ────────────────────────── 渲染调度 ────────────────────────────

    private func triggerRender(skipSub: Bool = false) {
        let token = UUID(); renderToken = token
        scheduleRender(token: token, onlyPanel: nil, skipSub: skipSub)
        if skipSub { scheduleSubSync() }
    }

    /// 惯性滚动期间每帧只画主图；最后一帧 150ms 后无新帧时补一次全量渲染（副图同步）
    private func scheduleSubSync() {
        subSyncTimer?.invalidate()
        subSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.triggerRender()   // skipSub=false，全量
        }
    }

    private func renderSinglePanel(panel: EFSubPanel) {
        let token = UUID(); renderToken = token
        scheduleRender(token: token, onlyPanel: panel, skipSub: false)
    }

    private func scheduleRender(token: UUID, onlyPanel: EFSubPanel?, skipSub: Bool) {
        // 在主线程收集所有渲染所需数据（UI相关的只能主线程读）
        let mainRect    = mainImageView.bounds
        let screenScale = traitCollection.displayScale
        let subTitleH   = EFLayout.subDivider

        // 副图面板：(UIImageView引用, 渲染区域, 在数据数组中的索引)
        typealias SubEntry = (iv: UIImageView, rect: CGRect, dataIdx: Int, panel: EFSubPanel)
        let subEntries: [SubEntry] = skipSub ? [] : subPanels.enumerated().compactMap { (i, panel) in
            guard !panel.isHidden else { return nil }
            if let op = onlyPanel, op !== panel { return nil }
            let ivH = panel.frame.height - subTitleH
            guard panel.frame.width > 0, ivH > 0 else { return nil }
            let rect = CGRect(x: 0, y: 0,
                              width: panel.frame.width,
                              height: ivH)
            return (panel.imageView, rect, i, panel)
        }

        let tlData  = timelineData
        let klData  = kLineData
        let period  = currentPeriod
        let vis     = visibleRange
        let cw      = candleWidth
        let cIdx: Int? = crosshairActive ? crosshairIndex : nil
        let tlR     = self.tlR
        let klR     = self.klR

        renderQ.async { [weak self] in
            guard let self = self, self.renderToken == token else { return }

            var mainImg: CGImage?
            var subImgs: [(UIImageView, CGImage)] = []

            // ── 主图
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

            // ── 副图
            for entry in subEntries {
                var img: CGImage?
                switch period {
                case .timeline, .fiveDay:
                    if let d = tlData {
                        // 分时副图：panel 的 indicator 决定画什么
                        let ind = entry.panel.indicator
                        img = tlR.renderSub(data: d, indicator: ind,
                                            rect: entry.rect, crosshairIdx: cIdx)
                    }
                case .kLine:
                    if let d = klData, entry.dataIdx < d.subData.count {
                        img = klR.renderSub(data: d, subIndex: entry.dataIdx,
                                            rect: entry.rect, visibleRange: vis,
                                            candleWidth: cw, crosshairIdx: cIdx)
                    }
                }
                if let img = img { subImgs.append((entry.iv, img)) }
            }

            DispatchQueue.main.async {
                guard self.renderToken == token else { return }
                if let img = mainImg {
                    self.mainImageView.image = UIImage(cgImage: img,
                                                       scale: screenScale,
                                                       orientation: .up)
                }
                for (iv, img) in subImgs {
                    iv.image = UIImage(cgImage: img, scale: screenScale, orientation: .up)
                }
                self.updateInfoBar()
            }
        }
    }

    // ────────────────────────── MA 信息行 ────────────────────────────

    private func updateInfoBar() {
        guard let data = kLineData else { return }
        let ci = crosshairActive ? crosshairIndex : (data.candles.count - 1)
        infoBar.update(maResults: data.maResults, index: ci)
    }

    // ────────────────────────── 手势 ────────────────────────────────

    private func setupGestures() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        lp.minimumPressDuration = 0.28; lp.delegate = self
        addGestureRecognizer(lp)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.delegate = self; addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self; addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap))
        tap.require(toFail: lp); addGestureRecognizer(tap)
    }

    @objc private func onLongPress(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began, .changed:
            activateCrosshair(at: gr.location(in: mainImageView))
        case .ended:
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.dismissCrosshair()
            }
        default: break
        }
    }

    @objc private func onPan(_ gr: UIPanGestureRecognizer) {
        if crosshairActive {
            activateCrosshair(at: gr.location(in: mainImageView))
            return
        }
        guard case .kLine = currentPeriod, let d = kLineData else { return }

        switch gr.state {
        case .began:
            animator.removeAllBehaviors()
            panStartRange = visibleRange

        case .changed:
            let dx    = gr.translation(in: self).x
            let shift = Int(-dx / Swift.max(1, candleWidth))
            let cnt   = d.candles.count
            let len   = visibleRange.count
            let ns    = (panStartRange.lowerBound + shift).clamped(lo: 0, hi: Swift.max(0, cnt - len))
            let nr    = ns..<Swift.min(ns + len, cnt)
            guard nr != visibleRange else { return }
            visibleRange = nr
            // 拖动时跳过副图渲染，仅刷新主图，提升流畅度
            triggerRender(skipSub: true)
            delegate?.chartView(self, visibleRangeChanged: nr)
            if ns <= 5 { delegate?.chartView(self, visibleRangeChanged: nr) }

        case .ended, .cancelled:
            // 添加惯性动量滚动
            let velocity = gr.velocity(in: self)
            // 速度不足时直接全量渲染一帧（含副图），然后退出
            guard abs(velocity.x) > 80 else { triggerRender(); return }
            decelerationStartX      = 0
            dynamicItem.center      = .zero
            let behavior            = UIDynamicItemBehavior(items: [dynamicItem])
            behavior.addLinearVelocity(velocity, for: dynamicItem)
            behavior.resistance     = 3.0
            behavior.action = { [weak self] in
                guard let self = self, let d = self.kLineData else { return }
                let itemX    = self.dynamicItem.center.x
                let dist     = itemX - self.decelerationStartX
                let slotW    = Swift.max(1, self.candleWidth)
                guard abs(dist) >= slotW else { return }
                let shift    = Int(-dist / slotW)
                let cnt      = d.candles.count
                let len      = self.visibleRange.count
                let ns       = (self.visibleRange.lowerBound + shift).clamped(lo: 0, hi: Swift.max(0, cnt - len))
                let nr       = ns..<Swift.min(ns + len, cnt)
                guard nr != self.visibleRange else { return }
                self.visibleRange          = nr
                self.decelerationStartX    = itemX
                let atEdge = (ns == 0 || ns >= cnt - len)
                if atEdge {
                    // 到达边界：取消防抖 timer，立即全量渲染后停止动量
                    self.subSyncTimer?.invalidate()
                    self.triggerRender()
                    self.animator.removeAllBehaviors()
                } else {
                    self.triggerRender(skipSub: true)   // scheduleSubSync 已在内部调用
                }
                self.delegate?.chartView(self, visibleRangeChanged: nr)
                if ns <= 5 { self.delegate?.chartView(self, visibleRangeChanged: nr) }
            }
            animator.addBehavior(behavior)
            decelerationBehavior = behavior

        default: break
        }
    }

    @objc private func onPinch(_ gr: UIPinchGestureRecognizer) {
        guard case .kLine = currentPeriod, let d = kLineData else { return }
        if gr.state == .began { pinchStartCW = candleWidth }

        let nw = (pinchStartCW * gr.scale).clamped(lo: EFLayout.candleMinW, hi: EFLayout.candleMaxW)
        guard abs(nw - candleWidth) > 0.15 else { return }
        candleWidth = nw

        let newVis = computeDefaultVisCount()
        let total  = d.candles.count
        let start  = Swift.max(0, visibleRange.upperBound - newVis)
        visibleRange = start..<Swift.min(start + newVis, total)
        triggerRender()
    }

    @objc private func onTap() { dismissCrosshair() }

    private func activateCrosshair(at loc: CGPoint) {
        crosshairActive = true
        crosshairIndex  = locationToIndex(loc)
        crosshairLayer.show(x: loc.x, y: loc.y, bounds: mainImageView.bounds)
        triggerRender()
        delegate?.chartView(self, crosshairMoved: crosshairIndex, period: currentPeriod)
    }

    private func dismissCrosshair() {
        guard crosshairActive else { return }
        crosshairActive = false
        crosshairLayer.hide()
        triggerRender()
        delegate?.chartViewCrosshairHid(self)
    }

    private func locationToIndex(_ loc: CGPoint) -> Int {
        let contentW = mainImageView.bounds.width - EFLayout.priceAxisW
        guard contentW > 0 else { return 0 }
        let ratio = (loc.x / contentW).clamped(lo: 0, hi: 1)

        switch currentPeriod {
        case .timeline, .fiveDay:
            let total  = EFTimelineRenderer.totalSlots(for: currentPeriod)
            let maxIdx = Swift.max(0, (timelineData?.points.count ?? 1) - 1)
            return Int(ratio * CGFloat(total)).clamped(lo: 0, hi: maxIdx)
        case .kLine:
            let vis    = visibleRange
            let maxIdx = Swift.max(0, (kLineData?.candles.count ?? 1) - 1)
            let i      = Int(ratio * CGFloat(vis.count - 1) + 0.5)
            return (vis.lowerBound + i).clamped(lo: 0, hi: maxIdx)
        }
    }

    private func computeDefaultVisCount() -> Int {
        let w = Swift.max(mainImageView.bounds.width, bounds.width - EFLayout.priceAxisW)
        return Swift.max(20, Int(w / candleWidth))
    }

    private func indicatorType(of subData: EFSubData) -> EFSubIndicator {
        switch subData {
        case .macd:   return .macd
        case .kdj:    return .kdj
        case .rsi:    return .rsi
        case .volume: return .volume
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension EFStockChartView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ a: UIGestureRecognizer,
                                   shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }
}

// MARK: - EFDynamicItem（UIDynamicAnimator 动量滚动辅助）

private final class EFDynamicItem: NSObject, UIDynamicItem {
    var center:    CGPoint              = .zero
    var bounds:    CGRect               = CGRect(x: 0, y: 0, width: 1, height: 1)
    var transform: CGAffineTransform    = .identity
}

