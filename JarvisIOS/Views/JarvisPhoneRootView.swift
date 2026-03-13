import SwiftUI

struct JarvisPhoneRootView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.09, blue: 0.16),
                        Color(red: 0.05, green: 0.16, blue: 0.24),
                        Color(red: 0.02, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                JarvisPhoneHomeView()
                    .padding(.horizontal, 16)
            }
            .navigationTitle("Jarvis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if appModel.needsModelSetup {
                            appModel.showSetupFlow = true
                        } else {
                            appModel.isKnowledgePresented = true
                        }
                        JarvisHaptics.selection()
                    } label: {
                        Label("Knowledge", systemImage: "books.vertical")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        appModel.isModelLibraryPresented = true
                        JarvisHaptics.selection()
                    } label: {
                        Label("Models", systemImage: "tray.full")
                    }

                    Button {
                        appModel.isSettingsPresented = true
                        JarvisHaptics.selection()
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $appModel.isAssistantPresented) {
            JarvisPhoneAssistantView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appModel.isKnowledgePresented) {
            JarvisPhoneKnowledgeView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appModel.isSettingsPresented) {
            JarvisPhoneSettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appModel.isModelLibraryPresented) {
            JarvisPhoneModelLibraryView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $appModel.showSetupFlow) {
            JarvisPhoneSetupView()
                .interactiveDismissDisabled(appModel.needsModelSetup)
        }
    }
}
