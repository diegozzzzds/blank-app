import SwiftData
import SwiftUI

@main
struct MusicAppApp: App {
    @State private var dependencies: AppDependencies

    init() {
        // AsyncImage relies on URLCache; the default is tiny.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        let container: ModelContainer
        do {
            container = try ModelContainerFactory.make()
        } catch {
            // Never crash on launch because of the store; fall back to memory and log.
            print("Failed to open the library store: \(error). Using an in-memory store.")
            container = try! ModelContainerFactory.make(inMemory: true)
        }
        _dependencies = State(initialValue: AppDependencies(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(dependencies)
        }
    }
}

extension View {
    /// Injects every service into the environment.
    func appEnvironment(_ dependencies: AppDependencies) -> some View {
        modelContainer(dependencies.container)
            .environment(dependencies.registry)
            .environment(dependencies.library)
            .environment(dependencies.player)
            .environment(dependencies.lyrics)
            .environment(dependencies.downloads)
            .environment(dependencies.importer)
            .environment(dependencies.actions)
            .environment(dependencies.search)
    }
}
