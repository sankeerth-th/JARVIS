import SwiftUI

struct ContentView: View {
    @StateObject private var appModel = JarvisPhoneAppModel()

    var body: some View {
        JarvisPhoneRootView()
            .environmentObject(appModel)
    }
}

#Preview {
    ContentView()
}
