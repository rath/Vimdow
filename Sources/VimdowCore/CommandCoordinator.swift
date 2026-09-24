import Foundation

@MainActor
public final class CommandCoordinator {
    /// An uncounted move or resize whose repeats undo as one change.
    private struct StepRun: Equatable {
        let window: UUID
        let direction: Direction
        let anchor: ResizeAnchor?
    }

    public private(set) var mode: Mode = .normal
    public private(set) var lastQuery: String?
    private var prefix = RepeatPrefix()
    private var pageOffset: Int?
    private var page: [WindowInfo] = []
    private var previousWindow: UUID?
    private var screenLayout: [CGRect] = []
    private var screenHistory: [UUID: [Int: CGRect]] = [:]
    private var lastDisplayBehavior: DisplayMoveBehavior?
    private var undoHistory = UndoHistory()
    private var openRun: StepRun?
    private var pendingKey: SequenceKey?
    private let preferences: () -> WindowPreferences
    private let windows: any WindowControlling
    private let presentation: any CommandPresenting

    public init(windows: any WindowControlling, presentation: any CommandPresenting,
                preferences: @escaping () -> WindowPreferences = { WindowPreferences() }) {
        self.windows = windows
        self.presentation = presentation
        self.preferences = preferences
    }

    public func handle(_ command: Command) {
        // A key waiting for a second one is settled by the very next command, whatever it is.
        let pending = pendingKey
        pendingKey = nil
        switch command {
        case .move, .resize: break
        default: openRun = nil // Any other command ends a run of repeated steps.
        }
        do {
            switch command {
            case .settings:
                setSettingsActive(true)
                presentation.showSettings()
            case .enter:
                // Re-entering is idempotent; it must not duplicate handlers or reset a prefix.
                if mode == .normal { transition(to: .command) }
            case .escape:
                if mode == .search { finishSearch(nil) } else { transition(to: .normal) }
            case .cycle(let step):
                guard mode != .search && mode != .settings else { return }
                try cycle(step: step, count: prefix.take())
            default:
                guard mode == .command || mode == .quickSwitch else { return }
                if let pending { try complete(pending, with: command) } else { try handleModal(command) }
            }
        } catch {
            prefix.reset()
            openRun = nil
            presentation.hideGuides()
            if mode == .quickSwitch { transition(to: .command) }
            if error as? WindowFailure == .permissionDenied { transition(to: .normal) }
            presentation.showFailure(error)
        }
    }

    private func handleModal(_ command: Command) throws {
        switch command {
        case .digit(let digit):
            if mode == .quickSwitch {
                guard !page.isEmpty, (1...page.count).contains(digit) else { return }
                let id = page[digit - 1].id
                transition(to: .normal)
                try windows.focus(id, movePointer: true)
            } else if digit == 0, prefix.value == nil {
                try place(.edge(.left)) // As in Vim, 0 is a motion unless it continues a count.
            } else {
                prefix.append(digit)
            }
        case .move(let direction):
            try transform(direction, anchor: nil)
        case .resize(let direction, let anchor):
            try transform(direction, anchor: anchor)
        case .place(let placement):
            try place(placement)
        case .sequence(let key):
            leaveNumbers()
            if key != .only { pendingKey = key } // A lone O means nothing.
        case .undo:
            try restore(.undo)
        case .redo:
            try restore(.redo)
        case .quickSwitch:
            let list = try windows.windows()
            pageOffset = WindowSelection.nextPage(after: pageOffset, count: list.count)
            page = Array(list.dropFirst(pageOffset ?? 0).prefix(9))
            mode = .quickSwitch
            prefix.reset()
            presentation.setMode(mode)
            presentation.showGuides(page)
        case .search:
            do { previousWindow = try windows.focusedWindow().id }
            catch WindowFailure.noFocusedWindow { previousWindow = nil }
            transition(to: .search)
            presentation.showSearch()
        case .repeatSearch(let step):
            let count = prefix.take()
            if let lastQuery { try cycle(step: step, count: count, query: lastQuery) }
        case .nextScreen:
            let window = try windows.focusedWindow()
            leaveNumbers()
            prefix.reset()
            try moveToNextScreen(window)
        case .quit:
            transition(to: .normal)
            presentation.quit()
        default: break
        }
    }

    private func moveToNextScreen(_ window: WindowInfo) throws {
        let screens = windows.screenFrames()
        let behavior = preferences().displayBehavior
        if screens != screenLayout || behavior != lastDisplayBehavior {
            screenLayout = screens
            lastDisplayBehavior = behavior
            screenHistory.removeAll()
        }
        guard screens.count > 1,
              let current = WindowGeometry.screenIndex(for: window.frame, screens: screens) else { return }
        let next = (current + 1) % screens.count
        let initial = behavior == .fillDisplay ? screens[next]
            : WindowGeometry.transfer(window.frame, from: screens[current], to: screens[next])
        let target = screenHistory[window.id]?[next] ?? initial
        try windows.setFrame(target, of: window.id, animated: false)
        // Only record departures after successful moves. Each window maintains
        // independent geometry, including manual edits made on each display.
        screenHistory[window.id, default: [:]][current] = window.frame
        if target != window.frame { undoHistory.record(window.frame, canGlide: false, for: window.id) }
    }

    public func setSettingsActive(_ active: Bool) {
        if active {
            if mode == .search { finishSearch(nil) }
            if mode != .settings { transition(to: .settings) }
        } else if mode == .settings {
            transition(to: .normal)
        }
    }

    public func resetDisplayHistory() {
        screenHistory.removeAll()
    }

    public func finishSearch(_ query: String?) {
        guard mode == .search else { return }
        let previous = previousWindow
        previousWindow = nil
        transition(to: .command)
        do {
            if let previous {
                do { try windows.focus(previous, movePointer: false) }
                catch WindowFailure.unavailableWindow { /* The app may have closed during the search. */ }
            }
            if let query, !query.isEmpty {
                lastQuery = query
                try cycle(step: 1, count: 1, query: query, current: previous)
            }
        } catch {
            if error as? WindowFailure == .permissionDenied { transition(to: .normal) }
            presentation.showFailure(error)
        }
    }

    private func transform(_ direction: Direction, anchor: ResizeAnchor?) throws {
        let counted = prefix.value != nil
        let count = prefix.take()
        leaveNumbers()
        let window = try windows.focusedWindow()
        let settings = preferences()
        let step = anchor == nil ? settings.moveStep : settings.resizeStep
        var target = WindowGeometry.apply(direction, to: window.frame, count: count, anchor: anchor, step: step)
        if anchor != nil, settings.resizeStopsAtDisplayEdges, let display = usableDisplay(around: window.frame) {
            target = WindowGeometry.limitGrowth(from: window.frame, to: target, within: display)
        }
        try windows.setFrame(target, of: window.id, animated: settings.animatesSteps)
        // Repeating a step without a count, as a held key does, extends one
        // undoable change. A count always makes a change of its own.
        let run = counted ? nil : StepRun(window: window.id, direction: direction, anchor: anchor)
        if let run, run == openRun { return }
        openRun = nil
        guard target != window.frame else { return }
        undoHistory.record(window.frame, canGlide: true, for: window.id)
        openRun = run
    }

    /// Finishes a two-key command, or drops both keys when they form none.
    private func complete(_ pending: SequenceKey, with command: Command) throws {
        switch (pending, command) {
        case (.g, .sequence(.g)): try place(.edge(.up))
        case (.z, .sequence(.z)): try place(.center)
        case (.window, .sequence(.only)): try place(.fill)
        // Shift–H/J/K/L already resize, and a key combination registers only
        // once, so after Control–W their resize command tiles instead.
        case (.window, .resize(let direction, .bottomRight)): try place(.half(direction))
        default: prefix.reset()
        }
    }

    /// Moves or tiles the focused window on the display holding most of it.
    private func place(_ placement: Placement) throws {
        prefix.reset()
        leaveNumbers()
        openRun = nil
        let window = try windows.focusedWindow()
        guard let display = usableDisplay(around: window.frame) else { return }
        let target = WindowGeometry.place(placement, frame: window.frame, within: display)
        try windows.setFrame(target, of: window.id, animated: preferences().animatesSteps)
        // Placing a window where it already is, like tiling a tiled window again, is not a change.
        guard target != window.frame else { return }
        undoHistory.record(window.frame, canGlide: true, for: window.id)
    }

    /// The area outside the menu bar and Dock of the display holding most of `frame`.
    private func usableDisplay(around frame: CGRect) -> CGRect? {
        let displays = windows.visibleScreenFrames()
        return WindowGeometry.screenIndex(for: frame, screens: displays).map { displays[$0] }
    }

    /// Undoes or redoes changes to the focused window, committing the history
    /// only after the window accepts the frame.
    private func restore(_ travel: UndoHistory.Travel) throws {
        let count = prefix.take()
        leaveNumbers()
        let window = try windows.focusedWindow()
        var history = undoHistory
        guard let target = history.travel(travel, count: count, for: window.id, from: window.frame) else { return }
        try windows.setFrame(target.frame, of: window.id, animated: target.canGlide && preferences().animatesSteps)
        undoHistory = history
    }

    private func cycle(step: Int, count: Int, query: String? = nil, current: UUID? = nil) throws {
        leaveNumbers()
        let list = try windows.windows()
        let focused = current ?? list.first(where: \.isFocused)?.id
        if let index = WindowSelection.index(in: list, current: focused, step: step, count: count, query: query) {
            try windows.focus(list[index].id, movePointer: false)
        }
    }

    private func leaveNumbers() {
        if mode == .quickSwitch { transition(to: .command) }
    }

    private func transition(to next: Mode) {
        let previous = mode
        mode = next
        prefix.reset()
        openRun = nil
        pendingKey = nil
        pageOffset = nil
        page = []
        presentation.hideGuides()
        presentation.setMode(next)
        if previous == .search { presentation.hideSearch() }
    }
}
