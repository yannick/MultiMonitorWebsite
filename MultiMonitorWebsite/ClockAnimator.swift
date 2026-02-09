import Foundation

struct TimeState {
    let secondAngle: CGFloat
    let minuteAngle: CGFloat
    let hourAngle: CGFloat
}

class ClockAnimator {

    private(set) var currentTimeState = TimeState(
        secondAngle: .pi / 2,
        minuteAngle: .pi / 2,
        hourAngle: .pi / 2
    )

    func start() {
        // Nothing to initialize
    }

    func stop() {
        // Nothing to clean up
    }

    /// Update hand positions based on current time. Returns true (always needs redraw for smooth animation)
    func update() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)

        let hours = Double(components.hour ?? 0)
        let minutes = Double(components.minute ?? 0)
        let seconds = Double(components.second ?? 0)
        let nanos = Double(components.nanosecond ?? 0) / 1_000_000_000.0

        // Single source of truth: total seconds as a continuous float
        let totalSeconds = hours * 3600.0 + minutes * 60.0 + seconds + nanos

        // Second hand: full rotation every 60 seconds
        let secondPosition = totalSeconds.truncatingRemainder(dividingBy: 60.0)
        let secondAngle = .pi / 2 - CGFloat(secondPosition) * (.pi / 30.0)

        // Minute hand: full rotation every 60 minutes (3600 seconds)
        let minutePosition = totalSeconds.truncatingRemainder(dividingBy: 3600.0) / 60.0
        let minuteAngle = .pi / 2 - CGFloat(minutePosition) * (.pi / 30.0)

        // Hour hand: full rotation every 12 hours (43200 seconds)
        let hourPosition = totalSeconds.truncatingRemainder(dividingBy: 43200.0) / 3600.0
        let hourAngle = .pi / 2 - CGFloat(hourPosition) * (.pi / 6.0)

        currentTimeState = TimeState(
            secondAngle: secondAngle,
            minuteAngle: minuteAngle,
            hourAngle: hourAngle
        )

        return true
    }
}
