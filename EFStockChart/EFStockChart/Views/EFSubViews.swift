//
//  EFSubViews.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 所有辅助子视图：周期栏、MA信息行、盘口视图、十字线层

import UIKit

// MARK: ── 周期切换栏 ─────────────────────────────────────────

public final class EFPeriodBar: UIView {
    public var onPeriodSelected: ((EFChartPeriod) -> Void)?

    // 主栏固定5个 + 更多按钮
    private let mainPeriods: [(String, EFChartPeriod)] = [
        ("分时", .timeline), ("五日", .fiveDay),
        ("日K",  .kLine(.daily)), ("周K", .kLine(.weekly)), ("月K", .kLine(.monthly))
    ]
    private let moreExtended: [EFKPeriod] = [
        .min1, .min5, .min15, .min30, .min60, .min120, .quarterly, .yearly
    ]

    private var buttons   = [UIButton]()
    private let moreBtn   = UIButton(type: .system)
    private let underline = UIView()

    public override init(frame: CGRect) { super.init(frame: frame); build() }
    public required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        backgroundColor = EFColor.background

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.distribution = .fill
        hStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            hStack.topAnchor.constraint(equalTo: topAnchor),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])

        for (i, item) in mainPeriods.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(item.0, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13)
            btn.setTitleColor(EFColor.textSecondary, for: .normal)
            if #available(iOS 15.0, *) {
                var config = UIButton.Configuration.plain()
                config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
                btn.configuration = config
            } else {
                btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            }
            btn.tag = i
            btn.addTarget(self, action: #selector(mainBtnTap(_:)), for: .touchUpInside)
            hStack.addArrangedSubview(btn)
            buttons.append(btn)
        }

        moreBtn.setTitle("更多 ▾", for: .normal)
        moreBtn.titleLabel?.font = .systemFont(ofSize: 13)
        moreBtn.setTitleColor(EFColor.textSecondary, for: .normal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            moreBtn.configuration = config
        } else {
            moreBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        }
        moreBtn.addTarget(self, action: #selector(showMore), for: .touchUpInside)
        hStack.addArrangedSubview(moreBtn)

        underline.backgroundColor = EFColor.rising
        underline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(underline)
        underline.heightAnchor.constraint(equalToConstant: 2).isActive = true
        underline.widthAnchor.constraint(equalToConstant: 24).isActive = true
        underline.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        setSelected(.timeline)
    }

    @objc private func mainBtnTap(_ sender: UIButton) {
        let p = mainPeriods[sender.tag].1
        setSelected(p)
        onPeriodSelected?(p)
    }

    @objc private func showMore() {
        guard let vc = findViewController() else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for kp in moreExtended {
            sheet.addAction(UIAlertAction(title: kp.title, style: .default) { [weak self] _ in
                let p = EFChartPeriod.kLine(kp)
                self?.setSelected(p)
                self?.onPeriodSelected?(p)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = moreBtn; pop.sourceRect = moreBtn.bounds
        }
        vc.present(sheet, animated: true)
    }

    public func setSelected(_ period: EFChartPeriod) {
        let isMain = mainPeriods.map(\.1).contains(period)
        let isMore = !isMain

        for (i, btn) in buttons.enumerated() {
            let match = mainPeriods[i].1 == period
            btn.setTitleColor(match ? EFColor.rising : EFColor.textSecondary, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: match ? .semibold : .regular)

            // 移动下划线
            if match {
                DispatchQueue.main.async {
                    let center = btn.convert(btn.bounds.center, to: self)
                    UIView.animate(withDuration: 0.18) {
                        self.underline.center = CGPoint(x: center.x, y: self.bounds.height - 1)
                    }
                }
            }
        }
        moreBtn.setTitleColor(isMore ? EFColor.rising : EFColor.textSecondary, for: .normal)
    }

    private func findViewController() -> UIViewController? {
        var r: UIResponder? = self
        while let n = r?.next { r = n; if let vc = r as? UIViewController { return vc } }
        return nil
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: ── MA 信息行 ──────────────────────────────────────────

final class EFInfoBar: UIView {
    private let scrollView = UIScrollView()
    private let stack      = UIStackView()

    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        backgroundColor = EFColor.background
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
    }

    func update(maResults: [EFMAResult], index: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for ma in maResults {
            let v = (index < ma.values.count) ? ma.values[index] : nil
            guard let val = v else { continue }
            let lbl = UILabel()
            lbl.font      = EFLayout.infoFont
            lbl.textColor = ma.color
            lbl.text      = "MA\(ma.period):\(EFFormat.price(val))"
            stack.addArrangedSubview(lbl)
        }
    }
}

// MARK: ── 五档盘口视图 ─────────────────────────────────────────

final class EFOrderBookView: UIView {
    private let tabBar       = EFOrderBookTabBar()
    private let askStack     = UIStackView()
    private let bidStack     = UIStackView()
    private let midDivider   = UIView()
    private let tradeTitle   = UILabel()
    private var tradeCells   = [EFTradeCellView]()
    private var askRows      = [EFOrderLevelRow]()
    private var bidRows      = [EFOrderLevelRow]()

    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        backgroundColor = EFColor.orderBookBg
        clipsToBounds = true

        // Tab 栏
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        // 卖档（卖5在上，卖1靠近分隔线）
        askStack.axis = .vertical
        askStack.distribution = .fillEqually
        for i in (1...5).reversed() {
            let row = EFOrderLevelRow(); row.configure(side: .ask, rank: i)
            askStack.addArrangedSubview(row)
            askRows.append(row)
        }

        // 中间分隔线（绿色横条，标志买卖价格中点）
        midDivider.backgroundColor = UIColor(red: 26/255, green: 181/255, blue: 77/255, alpha: 0.6)
        midDivider.heightAnchor.constraint(equalToConstant: 1.5).isActive = true

        // 买档
        bidStack.axis = .vertical
        bidStack.distribution = .fillEqually
        for i in 1...5 {
            let row = EFOrderLevelRow(); row.configure(side: .bid, rank: i)
            bidStack.addArrangedSubview(row)
            bidRows.append(row)
        }

        // 分时成交标题
        tradeTitle.text          = "分时成交"
        tradeTitle.font          = .systemFont(ofSize: 10)
        tradeTitle.textColor     = EFColor.textSecondary
        tradeTitle.textAlignment = .center
        tradeTitle.heightAnchor.constraint(equalToConstant: 18).isActive = true

        // 分时成交明细（10条）
        let tradeStack = UIStackView()
        tradeStack.axis = .vertical
        for _ in 0..<10 {
            let c = EFTradeCellView(); tradeCells.append(c)
            tradeStack.addArrangedSubview(c)
        }

        let main = UIStackView(arrangedSubviews: [
            tabBar, askStack, midDivider, bidStack, tradeTitle, tradeStack
        ])
        main.axis = .vertical
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor),
            main.leadingAnchor.constraint(equalTo: leadingAnchor),
            main.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func update(_ ob: EFOrderBook) {
        // 卖档：asks[0] 是卖5（价格最高），asks[4] 是卖1（最低）
        for (i, row) in askRows.enumerated() {
            let level = i < ob.asks.count ? ob.asks[i] : nil
            row.update(level: level)
        }
        // 买档：bids[0] 是买1（价格最高）
        for (i, row) in bidRows.enumerated() {
            let level = i < ob.bids.count ? ob.bids[i] : nil
            row.update(level: level)
        }
    }

    func updateTrades(_ trades: [EFTradeRecord]) {
        for (i, cell) in tradeCells.enumerated() {
            cell.update(i < trades.count ? trades[i] : nil)
        }
    }
}

// 盘口 Tab（五档/大单/分价）
private final class EFOrderBookTabBar: UIView {
    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 24) }

    private func build() {
        backgroundColor = EFColor.orderBookBg
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        for (i, t) in ["五档", "大单", "分价"].enumerated() {
            let lbl = UILabel(); lbl.text = t; lbl.textAlignment = .center
            lbl.font = .systemFont(ofSize: 10, weight: .medium)
            lbl.textColor = i == 0 ? EFColor.rising : EFColor.textLabel
            stack.addArrangedSubview(lbl)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

// 单行盘口（卖1–卖5 / 买1–买5）
final class EFOrderLevelRow: UIView {
    private let rankLbl  = UILabel()   // 卖5/买1 等
    private let priceLbl = UILabel()
    private let volLbl   = UILabel()
    private var side: Side = .ask

    enum Side { case ask, bid }

    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 19) }

    private func build() {
        let stack = UIStackView(arrangedSubviews: [rankLbl, priceLbl, volLbl])
        stack.axis = .horizontal; stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        [rankLbl, priceLbl, volLbl].forEach {
            $0.font = font
            $0.textAlignment = .right
        }
        rankLbl.textAlignment = .left
    }

    func configure(side: Side, rank: Int) {
        self.side = side
        rankLbl.text      = side == .ask ? "卖\(rank)" : "买\(rank)"
        rankLbl.textColor = EFColor.textSecondary
        priceLbl.textColor = side == .ask ? EFColor.rising : EFColor.falling
        volLbl.textColor  = EFColor.textPrimary
    }

    func update(level: EFOrderLevel?) {
        priceLbl.text = level.map { EFFormat.price($0.price) } ?? "---"
        volLbl.text   = level.map { "\($0.volume)" } ?? ""
    }
}

// 分时成交单条
final class EFTradeCellView: UIView {
    private let timeLbl  = UILabel()
    private let priceLbl = UILabel()
    private let volLbl   = UILabel()

    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 16) }

    private func build() {
        let stack = UIStackView(arrangedSubviews: [timeLbl, priceLbl, volLbl])
        stack.axis = .horizontal; stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let font = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        [timeLbl, priceLbl, volLbl].forEach {
            $0.font = font; $0.textAlignment = .right
        }
        timeLbl.textAlignment = .left
    }

    func update(_ trade: EFTradeRecord?) {
        isHidden = trade == nil
        guard let t = trade else { return }
        timeLbl.text       = t.time
        timeLbl.textColor  = EFColor.textSecondary
        priceLbl.text      = EFFormat.price(t.price)
        priceLbl.textColor = t.direction > 0 ? EFColor.rising : (t.direction < 0 ? EFColor.falling : EFColor.textPrimary)
        volLbl.text        = "\(t.volume)"
        volLbl.textColor   = EFColor.textPrimary
    }
}

// MARK: ── 十字线覆盖层（独立刷新，不触发主图重渲）────────────

final class EFCrosshairLayer: UIView {
    private var cx: CGFloat = 0, cy: CGFloat = 0
    private var isVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func show(x: CGFloat, y: CGFloat, bounds: CGRect) {
        cx = x; cy = y; isVisible = true
        frame = bounds
        setNeedsDisplay()
    }

    func hide() {
        isVisible = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard isVisible, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(EFColor.crosshair.cgColor)
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        // 横线
        ctx.move(to: CGPoint(x: 0,            y: cy))
        ctx.addLine(to: CGPoint(x: bounds.width, y: cy))
        // 竖线
        ctx.move(to: CGPoint(x: cx, y: 0))
        ctx.addLine(to: CGPoint(x: cx, y: bounds.height))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        // 圆点
        let r: CGFloat = 3
        ctx.setFillColor(EFColor.timelineMain.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
    }
}
