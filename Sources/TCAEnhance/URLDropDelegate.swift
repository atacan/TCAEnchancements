#if canImport(SwiftUI)
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct URLDropDelegate: DropDelegate {
    @Binding var urls: [URL]
    @Binding var isDropInProgress: Bool
    var actionDropEntered: () -> Void
    var actionDropExited: () -> Void
    var acceptedTypes: [UTType]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        isDropInProgress = true
        actionDropEntered()
    }

    func performDrop(info: DropInfo) -> Bool {
        var noProblem = true
        for itemProvider in info.itemProviders(for: acceptedTypes) {
            for type in acceptedTypes {
                itemProvider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
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
        }
        return noProblem
    }

    func dropExited(info: DropInfo) {
        isDropInProgress = false
        actionDropExited()
    }
}

/// A view and reducer for handling file drops with customizable file types
///
/// ```swift
/// public struct State: Equatable {
///     // ...
///     var urlDrop: URLDropReducer.State
///     // ...
/// }
///
/// public enum Action: Equatable {
///     // ...
///     case urlDrop(URLDropReducer.Action)
///     // ...
/// }
///
/// switch action {
///     // ...
///     case let .urlDrop(.droppedFiles(urls)):
///         return .run { send in
///             // Handle the dropped files however you need
///             for url in urls {
///                 // Process files based on their types
///                 if url.pathExtension == "mp3" {
///                     try await processAudioFile(url)
///                 } else if url.pathExtension == "jpg" {
///                     try await processImageFile(url)
///                 }
///             }
///             await send(.filesProcessed)
///         }
///     case .urlDrop:
///         return .none
///     // ...
/// }
///
/// // In reducer
/// Scope(state: \.urlDrop, action: \.urlDrop) {
///     URLDropReducer()
/// }
///
/// // In view
/// .overlay {
///     URLDropView(
///         store: store.scope(state: \.urlDrop, action: Action.urlDrop),
///         acceptedTypes: [.audio, .image] // Specify the file types you want to accept
///     )
/// }
@Reducer
public struct URLDropReducer {
    public init() {}
    
    @ObservableState
    public struct State: Equatable {
        var isDropInProgress: Bool
        var droppedUrls: [URL]

        public init(droppedUrls: [URL] = [], isDropInProgress: Bool = false) {
            self.droppedUrls = droppedUrls
            self.isDropInProgress = isDropInProgress
        }
    }

    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case dropEntered
        case dropExited
        case droppedFiles([URL])
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
                return .send(.droppedFiles(state.droppedUrls))
            case .droppedFiles:
                state.droppedUrls = []
                return .none
            }
        }
    }
}

@available(iOS 15.0, *)
@available(macOS 12.0, *)
public struct URLDropView: View {
    @ComposableArchitecture.Bindable var store: StoreOf<URLDropReducer>

    let acceptedTypes: [UTType]

    @State var phase: CGFloat = 0

    public init(store: StoreOf<URLDropReducer>, acceptedTypes: [UTType]) {
        self.store = store
        self.acceptedTypes = acceptedTypes
    }

    public var body: some View {
        WithPerceptionTracking {
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
                .foregroundStyle(store.isDropInProgress ? Color.accentColor : Color.clear)
                .animation(
                    Animation.linear(duration: 2)
                        .repeatForever(autoreverses: false),
                    value: phase
                )
                .onAppear {
                    phase = 20
                }
                .onDrop(
                    of: acceptedTypes,
                    delegate: URLDropDelegate(
                        urls: $store.droppedUrls,
                        isDropInProgress: $store.isDropInProgress,
                        actionDropEntered: { store.send(.dropEntered) },
                        actionDropExited: { store.send(.dropExited) },
                        acceptedTypes: acceptedTypes
                    )
                )
        }
    }
}

// preview
#if DEBUG
@available(iOS 15.0, *)
@available(macOS 12.0, *)
struct URLDropView_Previews: PreviewProvider {
    static var previews: some View {
        URLDropView(
            store: Store(initialState: .init(isDropInProgress: true), reducer: {URLDropReducer()}),
            acceptedTypes: [.audio, .image]
        )
        .padding()
    }
}
#endif
#endif
