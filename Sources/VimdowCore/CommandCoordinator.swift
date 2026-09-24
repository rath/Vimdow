import Foundation

@MainActor
public final class CommandCoordinator {
    public private(set) var mode: Mode = .normal
    public private(set) var lastQuery: String?
    private var prefix = RepeatPrefix()
    private var pageOffset: Int?
    private var page: [WindowInfo] = []
    private var previousWindow: UUID?
    private let windows: any WindowControlling
    private let presentation: any CommandPresenting

    public init(windows: any WindowControlling, presentation: any CommandPresenting) {
        self.windows = windows
        self.presentation = presentation
    }

    public func handle(_ command: Command) {
        do {
            switch command {
            case .enter:
                // Re-entering is idempotent; it must not duplicate handlers or reset a prefix.
                if mode == .normal { transition(to: .command) }
            case .escape:
                if mode == .search { finishSearch(nil) } else { transition(to: .normal) }
            case .cycle(let step):
                guard mode != .search else { return }
                try cycle(step: step, count: prefix.take())
            default:
                guard mode == .command || mode == .quickSwitch else { return }
                try handleModal(command)
            }
        } catch {
            prefix.reset()
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
            } else {
                prefix.append(digit)
            }
        case .move(let direction):
            try transform(direction, anchor: nil)
        case .resize(let direction, let anchor):
            try transform(direction, anchor: anchor)
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
            if let frame = WindowGeometry.nextScreen(for: window.frame, screens: windows.screenFrames()) {
                try windows.setFrame(frame, of: window.id)
            }
        case .quit:
            transition(to: .normal)
            presentation.quit()
        default: break
        }
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
        let count = prefix.take()
        leaveNumbers()
        let window = try windows.focusedWindow()
        try windows.setFrame(WindowGeometry.apply(direction, to: window.frame, count: count, anchor: anchor),
                             of: window.id)
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
        pageOffset = nil
        page = []
        presentation.hideGuides()
        presentation.setMode(next)
        if previous == .search { presentation.hideSearch() }
    }
}
