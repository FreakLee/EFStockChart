//
//  EFRenderContext.swift
//  EFStockChart
//
//  Created by min Lee on 2026/04/10.
//  Copyright © 2026 min Lee. All rights reserved.
//

// 渲染工具集 — 坐标映射、文字绘制、路径工具

import UIKit
import CoreGraphics

// MARK: ── 坐标映射 ──────────────────────────────────────────

struct EFCoordMap {
    let rect:  CGRect     // 绘制区域
    let minV:  Double     // 值域下界
    let maxV:  Double     // 值域上界

    /// 值 → Y（CGContext 已翻转，Y 向上增大 = 价格向上）
    func y(_ v: Double) -> CGFloat {
        guard maxV > minV else { return rect.midY }
        let ratio = CGFloat((v - minV) / (maxV - minV))
        return rect.maxY - ratio * rect.height
    }

    /// 索引 → X（基于总数）
    func x(idx: Int, total: Int) -> CGFloat {
        guard total > 1 else { return rect.midX }
        return rect.minX + CGFloat(idx) / CGFloat(total - 1) * rect.width
    }

    /// X → 索引
    func index(x: CGFloat, total: Int) -> Int {
        guard total > 1, rect.width > 0 else { return 0 }
        let ratio = (x - rect.minX) / rect.width
        return Swift.max(0, Swift.min(total - 1, Int(ratio * CGFloat(total - 1) + 0.5)))
    }

    /// 均匀分布 X（K线用，基于可见范围）
    func xK(idx: Int, visStart: Int, visCount: Int, candleW: CGFloat) -> CGFloat {
        let offset = idx - visStart
        // 使每根蜡烛居中在格子里
        let slotW  = rect.width / CGFloat(visCount)
        return rect.minX + (CGFloat(offset) + 0.5) * slotW
    }
}

// MARK: ── Core Graphics 绘图助手 ─────────────────────────────

extension CGContext {

    // ── 折线（nil 断开）
    func strokePolyline<S: Sequence>(
        points: S,
        color: UIColor,
        lineWidth: CGFloat,
        alpha: CGFloat = 1
    ) where S.Element == CGPoint? {
        setStrokeColor(color.withAlphaComponent(alpha).cgColor)
        setLineWidth(lineWidth)
        setLineJoin(.round); setLineCap(.round)

        var pen: CGPoint?
        for pt in points {
            if let p = pt {
                if let prev = pen { move(to: prev); addLine(to: p) }
                pen = p
            } else { pen = nil }
        }
        strokePath()
    }

    // ── 文字（支持左/中/右对齐）
    func drawString(
        _ text: String,
        at origin: CGPoint,
        font: UIFont,
        color: UIColor,
        align: NSTextAlignment = .left
    ) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        var x = origin.x
        switch align {
        case .center: x -= size.width / 2
        case .right:  x -= size.width
        default:      break
        }
        UIGraphicsPushContext(self)
        (text as NSString).draw(
            in: CGRect(x: x, y: origin.y - size.height/2, width: size.width, height: size.height),
            withAttributes: attrs
        )
        UIGraphicsPopContext()
    }

    // ── 带背景色的标签（十字线轴标签用）
    func drawLabelBadge(
        _ text: String,
        at origin: CGPoint,
        font: UIFont,
        fg: UIColor,
        bg: UIColor,
        padding: CGFloat = 3
    ) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let sz = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: origin.x, y: origin.y - sz.height/2 - padding,
                          width: sz.width + padding*2, height: sz.height + padding*2)
        setFillColor(bg.cgColor)
        fill(rect)
        UIGraphicsPushContext(self)
        (text as NSString).draw(
            in: CGRect(x: rect.minX + padding, y: rect.minY + padding,
                       width: sz.width, height: sz.height),
            withAttributes: attrs
        )
        UIGraphicsPopContext()
    }

    // ── 虚线
    func strokeDashedLine(from: CGPoint, to: CGPoint, color: UIColor,
                          lineWidth: CGFloat = 0.5, dash: [CGFloat] = [3, 3]) {
        setStrokeColor(color.cgColor)
        setLineWidth(lineWidth)
        setLineDash(phase: 0, lengths: dash)
        move(to: from); addLine(to: to); strokePath()
        setLineDash(phase: 0, lengths: [])
    }

    // ── 实线
    func strokeLine(from: CGPoint, to: CGPoint, color: UIColor, lineWidth: CGFloat = 0.5) {
        setStrokeColor(color.cgColor)
        setLineWidth(lineWidth)
        move(to: from); addLine(to: to); strokePath()
    }

    // ── 圆角矩形
    func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: UIColor) {
        setFillColor(color.cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        addPath(path.cgPath); fillPath()
    }
}

// MARK: ── CGContext 工厂（离屏渲染）────────────────────────

func makeOffscreenContext(size: CGSize, scale: CGFloat) -> CGContext? {
    let w = Int(size.width * scale), h = Int(size.height * scale)
    guard w > 0, h > 0 else { return nil }
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    // 翻转 Y 轴，使坐标系与 UIKit 一致（y 向下增大）
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

// MARK: ── 数值扩展 ──────────────────────────────────────────

extension Double {
    func clamped(lo: Double, hi: Double) -> Double { Swift.max(lo, Swift.min(hi, self)) }
}
extension CGFloat {
    func clamped(lo: CGFloat, hi: CGFloat) -> CGFloat { Swift.max(lo, Swift.min(hi, self)) }
}
extension Int {
    func clamped(lo: Int, hi: Int) -> Int { Swift.max(lo, Swift.min(hi, self)) }
}

// MARK: ── CGRect convenience ──────────────────────────────────
// 定义在公共文件，所有 Renderer 均可访问

extension CGRect {
    /// 保留尺寸，将 origin 替换为指定值（渲染器离屏绘制时常用）
    func withOrigin(_ o: CGPoint) -> CGRect { CGRect(origin: o, size: size) }
}
