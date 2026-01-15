#if canImport(SwiftUI)
import Foundation
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct URLDropDelegate: DropDelegate {
    @Binding var isDropInProgress: Bool
    var actionDropEntered: () -> Void
    var actionDropExited: () -> Void
    var actionDroppedFiles: ([URL]) -> Void
    var acceptedTypes: [UTType]

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        isDropInProgress = true
        actionDropEntered()
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let group = DispatchGroup()
        var loadedUrls: [URL] = []
        let urlsLock = NSLock()

        for itemProvider in info.itemProviders(for: acceptedTypes) {
            for type in acceptedTypes {
                group.enter()
                itemProvider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                    defer { group.leave() }

                    if let url = item as? URL {
                        urlsLock.lock()
                        loadedUrls.append(url)
                        urlsLock.unlock()
                    } else if let urlString = item as? String,
                              let url = URL(string: urlString) {
                        urlsLock.lock()
                        loadedUrls.append(url)
                        urlsLock.unlock()
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urlsLock.lock()
                        loadedUrls.append(url)
                        urlsLock.unlock()
                    }
                }
            }
        }

        group.notify(queue: .main) { [self] in
            isDropInProgress = false
            if !loadedUrls.isEmpty {
                actionDroppedFiles(loadedUrls)
            }
        }

        return true
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

        public init(isDropInProgress: Bool = false) {
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
                return .none
            case .droppedFiles:
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
                        isDropInProgress: $store.isDropInProgress,
                        actionDropEntered: { store.send(.dropEntered) },
                        actionDropExited: { store.send(.dropExited) },
                        actionDroppedFiles: { urls in store.send(.droppedFiles(urls)) },
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
            store: Store(initialState: .init(), reducer: {
                URLDropReducer()
                    ._printChanges()
            }),
            acceptedTypes: [.audio, .image]
        )
        .padding()
    }
}
#endif
#endif
