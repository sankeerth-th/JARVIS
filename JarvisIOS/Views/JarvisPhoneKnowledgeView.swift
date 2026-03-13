import SwiftUI

struct JarvisPhoneKnowledgeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.95), Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.8))
                        TextField("Search local snippets", text: $appModel.knowledgeQuery)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .onChange(of: appModel.knowledgeQuery) { _, _ in
                                appModel.refreshKnowledgeResults()
                            }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))

                    if appModel.knowledgeResults.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("No local knowledge yet")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Save an assistant response to make it searchable.")
                                .font(.system(.footnote, design: .rounded, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(appModel.knowledgeResults) { result in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(result.item.title)
                                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(result.item.createdAt.formatted(date: .abbreviated, time: .omitted))
                                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.65))
                                        }
                                        Text(result.snippet)
                                            .font(.system(.footnote, design: .rounded, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.8))
                                            .lineLimit(4)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Local Knowledge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        appModel.clearKnowledge()
                    }
                    .disabled(appModel.knowledgeItems.isEmpty)
                }
            }
        }
        .onAppear {
            appModel.refreshKnowledgeResults()
        }
    }
}
