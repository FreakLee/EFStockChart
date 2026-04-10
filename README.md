# EFStockChart

东方财富风格股票图表组件 — iOS 15+，Swift 5.7，零第三方依赖

---

## 文件结构

```
EFStockChart/
├── Models/
│   └── EFChartModels.swift        数据模型（TimePoint、KLinePoint、OrderBook 等）
├── Core/
│   ├── EFChartTheme.swift         颜色、字体、布局常量、数字格式化
│   ├── EFIndicatorEngine.swift    技术指标计算（MA/EMA/MACD/KDJ/RSI）
│   ├── EFRenderContext.swift      CGContext 绘图助手、坐标映射
│   └── EFChartConfig.swift        图表运行时配置
├── Renderers/
│   ├── EFTimelineRenderer.swift   分时图渲染器（个股+指数）
│   ├── EFKLineRenderer.swift      K线图渲染器（含所有副图）
│   └── EFFiveDayRenderer.swift    五日分时扩展
├── Views/
│   ├── EFStockChartView.swift     主容器视图（手势+渲染调度）
│   ├── EFSubViews.swift           周期栏/MA栏/盘口/十字线层
│   └── EFSubIndicatorBar.swift    副图指标切换
└── Demo/
    ├── EFMockData.swift           完整 Mock 数据（可直接运行）
    └── DemoViewController.swift   开箱即用 Demo
```

---

## 3步接入

### 步骤1 — 拖入工程
将整个 `EFStockChart/` 文件夹拖入 Xcode，勾选「Copy items if needed」

### 步骤2 — 设为根视图（快速验证）
```swift
// AppDelegate.swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions ...) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = EFDemoViewController()
    window?.makeKeyAndVisible()
    return true
}
```

### 步骤3 — 运行
Command+R，切换 Segment 可看到：个股分时（带盘口）/ 指数分时 / 日K / 5分K

---

## 嵌入已有页面

```swift
// 1. 创建视图
let chartView = EFStockChartView()
chartView.delegate = self
view.addSubview(chartView)
// 设置约束...

// 2a. 加载个股分时图
let data = EFTimelineData(
    securityType: .stock,
    stockCode: "600519",
    stockName: "贵州茅台",
    prevClose: 1465.02,
    upperLimit: 1611.52,
    lowerLimit: 1318.52,
    points: yourTimelinePoints,
    orderBook: yourOrderBook
)
chartView.loadTimeline(data)

// 2b. 加载指数分时图（全宽，内嵌涨跌家数柱）
let indexData = EFTimelineData(
    securityType: .index,
    stockCode: "000001",
    stockName: "上证指数",
    prevClose: 3995.00,
    upperLimit: 4594.25,
    lowerLimit: 3395.75,
    points: indexPoints  // EFTimePoint 含 advancers/decliners 字段
)
chartView.loadTimeline(indexData)

// 2c. 加载 K 线（先异步计算指标）
EFIndicatorEngine.calculateAsync(candles: yourCandles) { result in
    let kData = EFKLineData(
        securityType: .stock,
        period: .daily,
        candles: yourCandles,
        maResults: result.maLines,
        subData: [.macd(result.macd), .kdj(result.kdj), .volume(result.volumeData)],
        prevClose: yourPrevClose
    )
    self.chartView.loadKLine(kData)
}
```

---

## Delegate 实现

```swift
extension YourVC: EFStockChartViewDelegate {

    func chartView(_ v: EFStockChartView, didSelectPeriod p: EFChartPeriod) {
        // 拉取对应周期的数据
        switch p {
        case .timeline:      fetchTimeline()
        case .fiveDay:       fetchFiveDay()
        case .kLine(let kp): fetchKLine(period: kp)
        }
    }

    func chartView(_ v: EFStockChartView, crosshairMoved idx: Int, period: EFChartPeriod) {
        // 十字线移动时更新外部 HUD
    }

    func chartView(_ v: EFStockChartView, visibleRangeChanged r: Range<Int>) {
        // 触达左边缘，加载更多历史数据
        if r.lowerBound <= 5 { loadMoreHistory() }
    }
}
```

---

## 实时数据推送

```swift
// WebSocket 收到新分时点
chartView.appendTimelinePoints([newPoint])

// 盘口更新
chartView.updateOrderBook(newOrderBook)

// 分时成交明细
chartView.updateTradeRecords(latestTrades)
```

---

## 技术点

**性能**
- 离屏渲染（CGContext→CGImage），主线程只做 `imageView.image = ...`
- K 线批量路径：所有阳线一次 fill，阴线一次 fill，共 4 次 draw call
- 十字线独立 CALayer，高频移动不触发主图重渲
- UUID token 机制取消过期渲染任务

**兼容性**
- Swift 5.7 (Xcode 14.2)，iOS 15+
- 零第三方依赖

**可扩展**
- `EFStockChartThemeProtocol` 协议支持自定义主题
- `EFChartConfig` 运行时切换实心/空心K线、复权类型
- 副图支持 1-4 个，可动态切换 MACD/KDJ/RSI/成交量

