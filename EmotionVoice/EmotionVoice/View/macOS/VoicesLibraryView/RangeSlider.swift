//
//  RangeSlider.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

// MARK: - RangeSlider（两个原生 Slider 上下排布，状态联动保证 low <= high）

struct RangeSlider: View {

    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let range: ClosedRange<Double>
    let step: Double

    init(lowerValue: Binding<Double>,
         upperValue: Binding<Double>,
         range: ClosedRange<Double>,
         step: Double = 1) {
        self._lowerValue = lowerValue
        self._upperValue = upperValue
        self.range = range
        self.step = step
    }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { lowerValue },
                    set: { lowerValue = min($0, upperValue - step) }
                ),
                in: range,
                step: step
            )
            .tint(AppColor.accentPrimary)

            Slider(
                value: Binding(
                    get: { upperValue },
                    set: { upperValue = max($0, lowerValue + step) }
                ),
                in: range,
                step: step
            )
            .tint(AppColor.accentPrimary)
        }
    }
}
