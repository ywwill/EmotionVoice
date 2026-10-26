//
//  DataReceiveGridView.swift
//  EmotionVoice
//
//  数据接收可视化：每来一条数据就往容器里 +1 个方块，自下而上堆叠，
//  一列填满后换到右边一列（阅读顺序 = 从左往右、每列从下往上）。
//  总格数不固定 —— 容器可横向滚动、右侧无限延伸，并自动跟随到最新一列。
//

import SwiftUI
import Combine

// MARK: - 滚动锚点偏好

/// 把"最新一列锚点"离可视区右缘的距离（锚点的 minX）上报出来，
/// 用来判断用户是否还停留在最右端附近。
private struct TailFrameKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 数据源

/// 接收网格的数据源。
///
/// 位置语义：索引 0 是**左下角**第一格，索引递增方向 = 沿本列往上，
/// 列填满后自动落到右边一列的最底部。`index / rows` 是列号，`index % rows` 是本列第几格。
///
/// 总接收量没有上限：`columnCount` 随数据增长，拿它就能算出容器的真实宽度。
@MainActor
final class DataReceiveGridModel: ObservableObject {

    /// 一个已接收的格子：全局索引 + 到达时刻。
    struct Slot: Identifiable, Equatable {
        /// 索引 0 = 左下角
        let id: Int
        /// 到达时刻（`Date().timeIntervalSinceReferenceDate`）
        let at: TimeInterval
    }

    // MARK: 尺寸

    /// 列高（每列固定几格）
    let rows: Int

    /// 已出现的列数（= ceil(已接收 / 列高)），用于推算容器宽度
    var columnCount: Int {
        max(1, Int(ceil(Double(slots.count) / Double(max(rows, 1)))))
    }

    // MARK: 状态

    /// 已接收的格子，按到达顺序排列
    @Published private(set) var slots: [Slot] = []

    /// 落地动画 / 高亮呼吸的时钟。
    /// 只在有动画要播的这段时间里跳动（~60Hz），播完自动停，不留空转。
    @Published private(set) var clock: TimeInterval = Date().timeIntervalSinceReferenceDate

    /// 模拟是否正在跑（只影响测试按钮的显示）
    @Published private(set) var isRunning: Bool = false

    var filledCount: Int { slots.count }

    // MARK: 动画时长（与绘制同源，避免两边各写一套）

    /// 单格「落地」弹入时长
    static let landingDuration: TimeInterval = 0.26
    /// 落地后高亮环完全沉下去的时长
    static let afterglowDuration: TimeInterval = 0.75

    private var clockTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?

    init(rows: Int = 7) {
        self.rows = max(rows, 1)
    }

    // MARK: - 接收

    /// 真实接收入口：来几条数据就点亮几格，会一直往右生长。
    func receive(_ count: Int = 1) {
        guard count > 0 else { return }

        let now = Date().timeIntervalSinceReferenceDate

        var next = slots
        // 同一批数据共用同一个到达时刻，视觉上一起蹦出来
        for offset in 0..<count {
            next.append(Slot(id: next.count, at: now + Double(offset) * 0.0001))
        }
        slots = next

        startClockIfNeeded()
    }

    /// 清空数据（不打断正在跑的模拟）
    func clear() {
        slots = []
        stopClock()
        clock = Date().timeIntervalSinceReferenceDate
    }

    /// 全部归零并停止模拟
    func reset() {
        stop()
        clear()
    }

    // MARK: - 测试入口

    /// 测试方法：模拟数据持续到达。
    ///
    /// - Parameter cellsPerSecond: 平均每秒到达的格数（内部有 0.6~1.5 倍抖动，接近真实网络节奏）。
    ///   容器会随接收量向右无限延伸。
    func startTest(cellsPerSecond: Double = 120) {
        stop()
        isRunning = true

        let interval = 1.0 / max(cellsPerSecond, 1)

        feedTask = Task { @MainActor [weak self] in
            defer { self?.isRunning = false }

            while !Task.isCancelled {
                guard let self else { return }

                // 一次可能来 1~2 条：真实数据是分包的，不会整整齐齐一格一格来
                self.receive(Int.random(in: 1...2))

                let jitter = interval * Double.random(in: 0.6...1.5)
                try? await Task.sleep(for: .seconds(jitter))
            }
        }
    }

    /// 停止模拟（不清数据）
    func stop() {
        feedTask?.cancel()
        feedTask = nil
        isRunning = false
    }

    // MARK: - 动画时钟

    private func startClockIfNeeded() {
        guard clockTask == nil else { return }

        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let now = Date().timeIntervalSinceReferenceDate
                self.clock = now

                let lastArrival = self.slots.last?.at ?? now
                if now - lastArrival > Self.landingDuration + Self.afterglowDuration {
                    self.clockTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }
}

// MARK: - 网格

/// 数据接收网格。
///
/// 用 `Canvas` 自绘而不是 `ForEach` 铺几百个 View：
/// ① 每次 `receive()` 只重绘、不做布局 diff；
/// ② 每格的落地进度由「到达时刻 + 当前时钟」现算，重绘时天然保持连续，无需逐格绑定动画。
///
/// 容器外层可横向滚动，右侧无限延伸；默认自动跟随到最新一列。
/// 关键修复：只有用户停留在最右端附近时才跟随——一旦往左翻阅历史会暂停跟随，
/// 新数据到来不再把视图硬拽回右边，避免与用户的手动滚动冲突；滚回最右又会自动跟上。
struct DataReceiveGridView: View {

    @ObservedObject var model: DataReceiveGridModel

    /// 已接收方块的颜色（换成 `Color(hex: 0x5BC8E8)` 就是青蓝那套观感）
    var tint: Color = AppColor.accentPrimary
    /// 单格边长
    var cellSize: CGFloat = 13
    /// 期望的格间距。
    /// 行间距就等于它；列间距会在「不小于它」的前提下被微调，让整数列正好从左铺到右 ——
    /// 这样左右边缘整格对齐，不会出现某列被切掉一角的残缺方块。
    var spacing: CGFloat = 4.5
    /// 圆角
    var cornerRadius: CGFloat = 3.6
    /// 可视宽度还没测出来（首帧宽度为 0）时的兜底列数
    var minColumns: Int = 26
    /// 是否自动跟随到最新一列。
    /// 仅当用户停留在最右端附近时跟随；往左翻阅历史会自动暂停，滚回最右恢复。
    var autoFollow: Bool = true

    private var tailID: String { "drg-tail" }
    private var coordSpace: String { "drgScroll" }

    // MARK: - 布局解算

    /// 「最新一格」的高亮环向外扩出的距离（见 `draw` 里的 `insetBy(dx:dy:)`）
    private static let haloRingInset: CGFloat = 1
    /// 画布四周必须预留的空白。
    ///
    /// 高亮环是画在格子外面的（环本身 1pt + 线宽一半 0.6pt ≈ 1.6pt），
    /// 而顶行 / 最右一列的格子是贴着画布边界的 —— 不预留的话，
    /// 落在边缘的最新格子上边或右边的白环会被画布直接裁掉一截。
    private static let haloOutset: CGFloat = 2

    /// 一次宽度测量后的布局结果。
    ///
    /// 列步进（`columnStep`）和行步进（`rowStep`）分开存：
    /// 列步进为了让左右边缘都贴齐会被微调，行步进保持原样。
    private struct Layout {
        /// 参与绘制的列数（数据没铺满时用空槽补足）
        let columns: Int
        let cellSize: CGFloat
        /// 相邻两行的步进
        let rowStep: CGFloat
        /// 相邻两列的步进
        let columnStep: CGFloat
        /// 画布宽度：数据没超宽时正好等于可视宽度，超了才向右延伸
        let width: CGFloat
        /// 网格自身高度（只由行数决定，与列间距无关，不含四周预留）
        let gridHeight: CGFloat
        /// 内容整体向外让出的距离：给贴边格子的高亮环留位置
        let outset: CGFloat

        /// 画布实际高度 = 网格高度 + 上下各预留一段
        var canvasHeight: CGFloat { gridHeight + outset * 2 }

        /// 索引 → 具体矩形（左下角起，逐列往上）
        func cellRect(for index: Int, rows: Int) -> CGRect {
            let column = index / rows
            let rowFromBottom = index % rows
            return CGRect(
                x: outset + CGFloat(column) * columnStep,
                y: outset + CGFloat(rows - 1 - rowFromBottom) * rowStep,
                width: cellSize,
                height: cellSize
            )
        }
    }

    /// 网格自身高度（不含四周预留；给外层 GeometryReader 定高时要再算上 `haloOutset * 2`）
    private var gridHeight: CGFloat {
        CGFloat(model.rows) * cellSize + CGFloat(max(model.rows - 1, 0)) * spacing
    }

    /// 整块画布的高度（含预留）
    private var canvasHeight: CGFloat { gridHeight + Self.haloOutset * 2 }

    /// 按可用的可视宽度解算布局。
    ///
    /// 两条约束：
    /// 1. **整数列必须正好铺满可用宽度**（首列贴左、末列贴右）。
    ///    之前是按 `ceil(宽度 / 步进)` 取列数、再乘回步进，结果画布往往比可视宽度多出一截，
    ///    最右一列的右半边就被容器边框切掉了。
    /// 2. **上下左右各留出 `haloOutset`**：最新一格的白环画在格子外面，
    ///    落在顶行 / 最右一列时必须有地方可画（这次修的就是这个）。
    private func layout(width visibleWidth: CGFloat) -> Layout {
        let rows = model.rows
        let desired = max(spacing, 0)
        let cell = max(cellSize, 1)
        let rowStep = cell + desired
        let height = CGFloat(rows) * cell + CGFloat(max(rows - 1, 0)) * desired

        // 宽度还没测出来（首帧 0）：退回兜底值，下一帧测量到真实宽度会重新算
        guard visibleWidth > cell * 2 else {
            return Layout(columns: max(model.columnCount, minColumns),
                          cellSize: cell,
                          rowStep: rowStep,
                          columnStep: rowStep,
                          width: max(visibleWidth, rowStep),
                          gridHeight: height,
                          outset: Self.haloOutset)
        }

        // 真正用来排列方块的宽度：两边各扣掉给高亮环预留的距离
        let drawWidth = max(visibleWidth - Self.haloOutset * 2, cell)

        // 「首列贴左、末列贴右」时，n 列要满足：可用宽度 = n × 格宽 + (n − 1) × 列间距。
        // 取满足「列间距 ≥ 期望间距」的最大整数 —— 只会比期望更松，不会挤在一起：
        //   可用宽度 ≥ n × 格宽 + (n − 1) × 期望间距
        //   ⟺ n ≤ (可用宽度 + 期望间距) / (格宽 + 期望间距)
        let fit = max(1, Int(floor((drawWidth + desired) / (cell + desired))))
        let columnGap = fit > 1
            ? (drawWidth - CGFloat(fit) * cell) / CGFloat(fit - 1)
            : desired
        let columnStep = cell + columnGap
        let dataColumns = model.columnCount

        return Layout(
            columns: max(dataColumns, fit),
            cellSize: cell,
            rowStep: rowStep,
            columnStep: columnStep,
            // 数据没超宽时直接用可视宽度：内容正好铺满，一点多余的横向滚动都没有；
            // 超宽后按真实内容宽度延伸（= 列数 × 列步进 − 一个列间距 + 两侧预留）
            width: dataColumns > fit
                ? CGFloat(dataColumns) * columnStep - columnGap + Self.haloOutset * 2
                : visibleWidth,
            gridHeight: height,
            outset: Self.haloOutset
        )
    }

    /// 用户是否停留在「最右端附近」。不在附近（往左翻阅历史）就暂停自动跟随，
    /// 避免新方块到来时把视图硬拽回右边，与用户的手动滚动冲突。
    @State private var followTail: Bool = true

    var body: some View {
        GeometryReader { outerGeo in
            let visibleWidth = outerGeo.size.width
            let layout = layout(width: visibleWidth)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // 在 body 里读取，确保 @Published 变化能驱动 Canvas 重绘
                        let slots = model.slots
                        let now = model.clock

                        Canvas { context, _ in
                            draw(slots: slots, now: now, layout: layout, in: &context)
                        }
                        .frame(width: layout.width, height: layout.canvasHeight)

                        // 紧贴内容右端的锚点：自动跟随滚到这里即可看到最新一列。
                        // ⚠️ 必须零宽 —— 哪怕占 1pt，内容都会比可视区宽，
                        // 自动跟随就会把整块内容往左拽那么一点，左边第一格被切掉一角。
                        Color.clear
                            .frame(width: 0, height: layout.canvasHeight)
                            .id(tailID)
                            .background(
                                GeometryReader { tailGeo in
                                    Color.clear
                                        .preference(
                                            key: TailFrameKey.self,
                                            value: tailGeo.frame(in: .named(coordSpace)).minX
                                        )
                                }
                            )
                    }
                    .frame(height: layout.canvasHeight)
                }
                // 测量锚点离可视区右缘有多远 → 判断用户是否还贴在最新一列。
                //
                // ⚠️ 只在判定结果真正翻转时才写 @State：`tailMinX` 是每帧都可能变的量
                // （上层任何布局动画都会让这个值在动画期间逐帧漂移），而无条件写 @State
                // 会把整个 body（GeometryReader + Canvas + ScrollView）每帧重算一遍。
                // 状态切换的布局动画恰好会放大这个回环，卡顿感有一半出在这儿。
                .onPreferenceChange(TailFrameKey.self) { tailMinX in
                    let rightEdge = outerGeo.frame(in: .named(coordSpace)).maxX
                    let shouldFollow = tailMinX - rightEdge <= layout.columnStep * 2
                    guard shouldFollow != followTail else { return }
                    followTail = shouldFollow
                }
                // 只在「新增了一列」且用户还贴在右端时滚动；
                // 一旦用户往左翻阅，followTail 变 false，这里就不再抢滚，冲突消失。
                .onChange(of: model.columnCount) { _, _ in
                    guard autoFollow, followTail else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(tailID, anchor: .trailing)
                    }
                }
            }
        }
        .frame(height: canvasHeight)
        .coordinateSpace(name: coordSpace)
        .accessibilityElement()
        .accessibilityLabel("已接收 \(model.filledCount) 条")
    }

    private func draw(
        slots: [DataReceiveGridModel.Slot],
        now: TimeInterval,
        layout: Layout,
        in context: inout GraphicsContext
    ) {
        let rows = model.rows
        let totalCells = layout.columns * rows

        // 1. 底槽：还没收到的格子，几乎不可见，只留一点网格暗示。
        //    攒成一条 Path 再一次性 fill —— 逐格 fill 的话，5 行 × 30 多列就是上百次
        //    独立的绘制调用，而接收期 Canvas 是跟着动画时钟每帧重绘的，这笔开销每帧都要付一遍。
        var emptySlots = Path()
        for index in 0..<totalCells {
            emptySlots.addPath(
                Path(roundedRect: layout.cellRect(for: index, rows: rows), cornerRadius: cornerRadius)
            )
        }
        context.fill(emptySlots, with: .color(Color.white.opacity(0.045)))

        // 2. 已接收：按到达时刻算落地进度（弹入 + 淡入）
        for slot in slots {
            let rect = layout.cellRect(for: slot.id, rows: rows)
            let age = max(now - slot.at, 0)
            let progress = min(age / DataReceiveGridModel.landingDuration, 1)

            // easeOutBack：起步快、末尾轻微过冲，落地有「咔」一下的手感
            let eased = Self.easeOutBack(progress)
            let scale = 0.55 + 0.45 * eased
            let alpha = min(progress * 2.2, 1)

            let inset = layout.cellSize * (1 - scale) / 2
            let body = rect.insetBy(dx: inset, dy: inset)

            context.fill(
                Path(roundedRect: body, cornerRadius: cornerRadius * scale),
                with: .color(tint.opacity(0.92 * alpha))
            )
        }

        // 3. 最新一格：亮一圈 + 呼吸，标出「数据正在往这里落」。
        //    环往外扩 `haloRingInset`，这部分超出画布的地方已被 `haloOutset` 预留，
        //    所以就算它落在顶行或最右一列，整圈白环也画得完整。
        if let latest = slots.last {
            let rect = layout
                .cellRect(for: latest.id, rows: rows)
                .insetBy(dx: -Self.haloRingInset, dy: -Self.haloRingInset)
            let age = max(now - latest.at, 0)

            // 刚落地时脉冲一次（0.55 → 1.0 → 0.55），之后停在 0.32 的安静亮边
            let glow: Double
            if age < DataReceiveGridModel.afterglowDuration {
                glow = 0.55 + 0.45 * sin(age / DataReceiveGridModel.afterglowDuration * .pi)
            } else {
                glow = 0.32
            }

            context.stroke(
                Path(roundedRect: rect, cornerRadius: cornerRadius + 1),
                with: .color(.white.opacity(glow)),
                lineWidth: 1.2
            )

            // 内部再垫一层白，让最新格比其余格子更亮
            context.fill(
                Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: cornerRadius),
                with: .color(.white.opacity(0.16 * glow))
            )
        }
    }

    private static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
}

// MARK: - 演示卡片（测试入口）

/// 数据接收动画的演示卡片：点右上角圆形按钮开始 / 停止。
/// 直接拿去挂在任意页面里即可，自己持有数据源。
struct DataReceiveGridDemo: View {

    @StateObject private var model = DataReceiveGridModel(rows: 7)

    /// 测试参数：平均每秒到达多少格
    var cellsPerSecond: Double = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            DataReceiveGridView(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)

            footer
        }
        .padding(20)
        .onDisappear { model.stop() }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 14) {
            // 左侧图标块
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .fill(AppColor.accentPrimary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .strokeBorder(AppColor.accentPrimary.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("数据接收".localized())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("模拟数据到达时的堆叠动画".localized())
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer(minLength: 12)

            // 右上角圆形按钮：开始 / 停止
            Button(action: runAnimationTest) {
                ZStack {
                    Circle()
                        .fill(AppColor.bgElevated)
                        .overlay(
                            Circle()
                                .stroke(AppColor.accentPrimary.opacity(model.isRunning ? 0.95 : 0.35),
                                        lineWidth: 2.5)
                        )
                    Image(systemName: model.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(model.isRunning ? AppColor.accentPrimary : AppColor.textSecondary)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(model.isRunning ? "停止".localized() : "开始接收".localized())
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Text("已接收 %d 格".localized(model.filledCount))
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textTertiary)

            Spacer(minLength: 8)

            Button {
                model.reset()
            } label: {
                Text("重置".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(AppColor.borderMedium, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(model.filledCount == 0 && !model.isRunning)
            .opacity(model.filledCount == 0 && !model.isRunning ? 0.35 : 1)
        }
    }

    // MARK: - 测试方法

    /// 点击按钮时调用：跑起来 / 停下来
    private func runAnimationTest() {
        if model.isRunning {
            model.stop()
        } else {
            model.startTest(cellsPerSecond: cellsPerSecond)
        }
    }
}

#if DEBUG
#Preview("数据接收动画") {
    ZStack {
        AppColor.bgPrimary
        DataReceiveGridDemo()
            .frame(width: 560)
            .background(AppColor.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .strokeBorder(AppColor.borderSubtle, lineWidth: 1)
            )
            .padding(24)
    }
    .frame(height: 320)
}
#endif
