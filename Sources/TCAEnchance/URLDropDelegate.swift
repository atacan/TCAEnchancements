#if canImport(SwiftUI)
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct URLDropDelegate: DropDelegate {
    @Binding var urls: [URL]
    @Binding var isDropInProgress: Bool
    var actionDropEntered: () -> Void
    var actionDropExited: () -> Void

    let acceptedType = UTType.fileURL

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [acceptedType])
    }

    func dropEntered(info: DropInfo) {
        isDropInProgress = true
        actionDropEntered()
    }

    func performDrop(info: DropInfo) -> Bool {
        var noProblem = true
        for itemProvider in info.itemProviders(for: [acceptedType]) {
            itemProvider.loadItem(forTypeIdentifier: acceptedType.identifier, options: nil) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        urls.append(url)
                    }
                } else {
                    noProblem = false
                }
            }
        }
        return noProblem
    }

    func dropExited(info: DropInfo) {
        isDropInProgress = false
        actionDropExited()
    }
}

/// Drop a text file and return its content
///
/// ```swift
/// public struct State: Equatable {
/// // ...
///     var urlDrop: URLDropReducer.State
/// // ...
/// }
///
/// public enum Action: Equatable {
/// // ...
/// case urlDrop(URLDropReducer.Action)
/// // ...
/// }
///
///switch action {
/// // ...
///     case let .urlDrop(.droppedFileContent(content)):
///         return .run {send in
///             await send(.importResponse(TaskResult{
///                  return try decoding(content)
///             }))
///         }
///     case .urlDrop:
///         return .none
/// // ...
/// }
public struct URLDropReducer: Reducer {
    public init() {}
    
    public struct State: Equatable {
        @BindingState var isDropInProgress: Bool
        @BindingState var droppedUrls: [URL]
        var droppedText: String

        public init(droppedUrls: [URL] = [], droppedText: String = "", isDropInProgress: Bool = false) {
            self.droppedUrls = droppedUrls
            self.droppedText = droppedText
            self.isDropInProgress = isDropInProgress
        }
    }

    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case dropEntered
        case dropExited
        case droppedFileContent(String)
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce<State, Action> { state, action in
            switch action {
            case .binding:
                return .none
            case .dropEntered:
                return .none
            case .dropExited:
                guard !state.droppedUrls.isEmpty else {
                    return .none
                }
                return .run { [droppedUrls = state.droppedUrls] send in
                    let text =
                        try droppedUrls.map {
                            try String(contentsOf: $0)
                        }
                        .joined(separator: "\n")
                    await send(.droppedFileContent(text))
                }
            case .droppedFileContent:
                state.droppedUrls = []
                return .none
            }
        }
    }
}

@available(iOS 15.0, *)
@available(macOS 12.0, *)
public struct URLDropView: View {
    let store: StoreOf<URLDropReducer>
    @ObservedObject var viewStore: ViewStoreOf<URLDropReducer>

    @State var phase: CGFloat = 0

    public init(store: StoreOf<URLDropReducer>) {
        self.store = store
        self.viewStore = ViewStore(store, observe: {$0})
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
                style: .init(
                    lineWidth: 4,
                    lineCap: .round,
                    lineJoin: .round,
                    miterLimit: 1,
                    dash: [10],
                    dashPhase: phase
                )
            )
            .padding(4)
            .foregroundStyle(viewStore.isDropInProgress ? Color.accentColor : Color.clear)
            .animation(
                Animation.linear(duration: 2)
                    .repeatForever(autoreverses: false),
                value: phase
            )
            .onAppear {
                phase = 20
            }
            .onDrop(
                of: [UTType.text],
                delegate: URLDropDelegate(
                    urls: viewStore.$droppedUrls,
                    isDropInProgress: viewStore.$isDropInProgress,
                    actionDropEntered: { viewStore.send(.dropEntered) },
                    actionDropExited: { viewStore.send(.dropExited) }
                )
            )
    }
}

// preview
#if DEBUG
@available(iOS 15.0, *)
@available(macOS 12.0, *)
struct URLDropView_Previews: PreviewProvider {
    static var previews: some View {
        URLDropView(
            store: Store(initialState: .init(isDropInProgress: true), reducer: {URLDropReducer()})
        )
        .padding()
    }
}
#endif
#endif
