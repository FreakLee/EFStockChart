//
//  EFSubIndicatorBar.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 副图指标切换栏（K线图底部每个副图左上角的下拉按钮）
// 对应截图中的 "MACD ▼" "成交量 ▼" "KDJ ▼" 按钮

import UIKit

// MARK: ── 副图标题栏（含指标切换按钮）

/// 每个副图顶部的标题 + 切换按钮
final class EFSubTitleBar: UIView {

    var onIndicatorChanged: ((EFSubIndicator) -> Void)?

    private let indicatorBtn = UIButton(type: .system)
    private var currentIndicator: EFSubIndicator = .macd

    // 实时指标值标签（显示 DIF/DEA/M 或 K/D/J 等）
    private let valuesLabel = UILabel()

    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        backgroundColor = EFColor.background

        indicatorBtn.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        indicatorBtn.setTitleColor(EFColor.textPrimary, for: .normal)
        indicatorBtn.addTarget(self, action: #selector(showMenu), for: .touchUpInside)

        valuesLabel.font      = EFLayout.infoFont
        valuesLabel.textColor = EFColor.textSecondary
        valuesLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [indicatorBtn, valuesLabel])
        stack.axis    = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setIndicator(.macd)
    }

    func setIndicator(_ indicator: EFSubIndicator) {
        currentIndicator = indicator
        indicatorBtn.setTitle("\(indicator.title) ▼", for: .normal)
    }

    func updateValues(_ text: String) {
        valuesLabel.text = text
    }

    @objc private func showMenu() {
        guard let vc = findVC() else { return }
        let alert = UIAlertController(title: "切换指标", message: nil, preferredStyle: .actionSheet)
        for indicator in EFSubIndicator.allCases {
            alert.addAction(UIAlertAction(title: indicator.title, style: .default) { [weak self] _ in
                self?.setIndicator(indicator)
                self?.onIndicatorChanged?(indicator)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = indicatorBtn
            pop.sourceRect = indicatorBtn.bounds
        }
        vc.present(alert, animated: true)
    }

    private func findVC() -> UIViewController? {
        var r: UIResponder? = self
        while let next = r?.next { r = next; if let vc = r as? UIViewController { return vc } }
        return nil
    }
}

// MARK: ── 副图容器（标题栏 + 图像视图）

/// 单个副图面板 = 顶部标题栏 + 图表 ImageView
final class EFSubPanel: UIView {

    let titleBar    = EFSubTitleBar()
    let imageView   = UIImageView()
    var indicator:  EFSubIndicator = .macd

    override init(frame: CGRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        backgroundColor = EFColor.background
        imageView.contentMode = .scaleToFill  // 渲染图像已是精确尺寸

        titleBar.translatesAutoresizingMaskIntoConstraints   = false
        imageView.translatesAutoresizingMaskIntoConstraints  = false
        addSubview(titleBar); addSubview(imageView)

        // 注意：父视图用 frame 赋值，初始化时高度为 0。
        // titleBar 高度约束设为 priority 999（非 required=1000），
        // 让 AutoLayout 在高度为 0 的过渡状态下能正常降级，不打印警告。
        let titleBarH = titleBar.heightAnchor.constraint(equalToConstant: EFLayout.subDivider)
        titleBarH.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBarH,

            imageView.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setIndicator(_ ind: EFSubIndicator) {
        indicator = ind
        titleBar.setIndicator(ind)
    }
}
