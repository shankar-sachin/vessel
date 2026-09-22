import Foundation

/// The numerical core behind every claim the insights engine makes.
///
/// Correlating food with symptoms is mostly an exercise in *not* being fooled.
/// Three dairy meals, two of them followed by bloating, is a 67% rate — and it
/// is also exactly what you would expect from chance if bloating happens after
/// half of everything you eat. So nothing here reports a raw proportion. Every
/// rate is a Beta-Binomial posterior pulled toward the user's own base rate for
/// that symptom, and every finding carries the credible interval and the sample
/// size that produced it.
///
/// Implemented from scratch rather than pulled in: a dependency here would be
/// one more thing between someone's health conclusion and a line of code that
/// can be read.
public enum Statistics {

    // MARK: - Beta posterior

    /// A Beta distribution, used as both the prior and the posterior over
    /// "how often does this symptom follow this food".
    public struct Beta: Sendable, Equatable {
        public let alpha: Double
        public let beta: Double

        public init(alpha: Double, beta: Double) {
            // Guard rails rather than a precondition: a degenerate prior should
            // produce a useless-but-safe answer, never a crash in a health app.
            self.alpha = max(alpha, 1e-6)
            self.beta = max(beta, 1e-6)
        }

        /// A prior centred on `mean` with the weight of `strength` observations.
        ///
        /// `strength` is literally "how many imaginary meals is this belief
        /// worth". At 8, five real exposures cannot outvote the base rate on
        /// their own — which is the entire point.
        public static func prior(mean: Double, strength: Double) -> Beta {
            let m = min(max(mean, 0.001), 0.999)
            return Beta(alpha: m * strength, beta: (1 - m) * strength)
        }

        /// The posterior after seeing `successes` of `trials`.
        public func updated(successes: Int, trials: Int) -> Beta {
            let failures = max(0, trials - successes)
            return Beta(alpha: alpha + Double(successes), beta: beta + Double(failures))
        }

        public var mean: Double { alpha / (alpha + beta) }

        /// The value below which `p` of the posterior mass lies.
        public func quantile(_ p: Double) -> Double {
            Statistics.betaQuantile(p, alpha: alpha, beta: beta)
        }

        /// Posterior probability that the true rate exceeds `threshold`.
        ///
        /// This, not the point estimate, is what decides whether a finding is
        /// shown. "Probably higher than your normal rate" is a claim the data
        /// can support; "67%" is not.
        public func probability(greaterThan threshold: Double) -> Double {
            1 - Statistics.regularizedIncompleteBeta(threshold, alpha, beta)
        }
    }

    // MARK: - Incomplete beta

    /// The regularized incomplete beta function `I_x(a, b)` — the Beta CDF.
    ///
    /// Continued-fraction evaluation (Lentz's method). Converges in a handful of
    /// iterations for the small counts this app deals in.
    public static func regularizedIncompleteBeta(_ x: Double, _ a: Double, _ b: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }

        let logBeta = lgamma(a) + lgamma(b) - lgamma(a + b)
        let front = exp(a * log(x) + b * log1p(-x) - logBeta)

        // The continued fraction only converges quickly on one side of the
        // distribution's mass; reflect onto that side when we're on the wrong one.
        if x < (a + 1) / (a + b + 2) {
            return front * betaContinuedFraction(x, a, b) / a
        } else {
            return 1 - front * betaContinuedFraction(1 - x, b, a) / b
        }
    }

    private static func betaContinuedFraction(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let tiny = 1e-30
        let qab = a + b, qap = a + 1, qam = a - 1

        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d

        for m in 1...200 {
            let mD = Double(m)
            let m2 = 2 * mD

            var numerator = mD * (b - mD) * x / ((qam + m2) * (a + m2))
            d = 1 + numerator * d
            if abs(d) < tiny { d = tiny }
            c = 1 + numerator / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c

            numerator = -(a + mD) * (qab + mD) * x / ((a + m2) * (qap + m2))
            d = 1 + numerator * d
            if abs(d) < tiny { d = tiny }
            c = 1 + numerator / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d

            let delta = d * c
            h *= delta
            if abs(delta - 1) < 1e-12 { break }
        }
        return h
    }

    /// Inverse Beta CDF by bisection.
    ///
    /// Bisection rather than Newton because it cannot diverge, and sixty halvings
    /// of `[0, 1]` reach the limit of Double precision anyway. Speed is
    /// irrelevant — this runs a few dozen times on a screen the user opened.
    public static func betaQuantile(_ p: Double, alpha: Double, beta: Double) -> Double {
        guard p > 0 else { return 0 }
        guard p < 1 else { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if regularizedIncompleteBeta(mid, alpha, beta) < p { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    // MARK: - Order statistics

    /// Linearly interpolated percentile, `p` in 0...1.
    ///
    /// Onset delays are reported as a median and a spread rather than a mean
    /// because the distribution is skewed and one symptom logged the next
    /// morning would drag a mean somewhere no symptom actually happened.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let position = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard upper < sorted.count else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    public static func median(_ values: [Double]) -> Double? { percentile(values, 0.5) }

    /// How alike two sets of occasions are, 0...1.
    ///
    /// Used to catch the foods that cannot be told apart: if every slice of bread
    /// you have eaten came with butter, no amount of data separates them, and the
    /// honest move is to say so rather than to name whichever scored a hair higher.
    public static func jaccard<T: Hashable>(_ a: Set<T>, _ b: Set<T>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }
}
