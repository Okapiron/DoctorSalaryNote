import Foundation

enum DeductionNameNormalizer {
    static func canonicalKey(_ name: String) -> String {
        let halfWidthName = name.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? name
        let normalizedName = halfWidthName
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .lowercased()

        if normalizedName.contains("短期掛金") || normalizedName.contains("健康保険") {
            return "健康保険"
        }
        if normalizedName.contains("長期掛金") || normalizedName.contains("厚生年金") {
            return "厚生年金"
        }

        return normalizedName
    }
}

enum AmountConsistencyValidator {
    static func warnings(
        grossAmount: Int,
        netAmount: Int?,
        deductionAmount: Int?,
        itemizedDeductionTotal: Int
    ) -> [String] {
        var warnings: [String] = []

        if let netAmount {
            let calculatedDeduction = grossAmount - netAmount
            if calculatedDeduction < 0 {
                warnings.append("手取りが額面を \((-calculatedDeduction).currencyText) 上回っています。")
            } else if let deductionAmount, calculatedDeduction != deductionAmount {
                let difference = abs(calculatedDeduction - deductionAmount)
                warnings.append(
                    "額面から手取りを引いた金額は \(calculatedDeduction.currencyText) ですが、控除合計は \(deductionAmount.currencyText) です。差額は \(difference.currencyText) です。"
                )
            }
        }

        if let deductionAmount, itemizedDeductionTotal > deductionAmount {
            warnings.append(
                "所得税・住民税・控除内訳の合計が、控除合計を \((itemizedDeductionTotal - deductionAmount).currencyText) 上回っています。"
            )
        }

        return warnings
    }
}

private extension Int {
    var currencyText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let amount = formatter.string(from: NSNumber(value: self)) ?? String(self)
        return "\(amount)円"
    }
}
