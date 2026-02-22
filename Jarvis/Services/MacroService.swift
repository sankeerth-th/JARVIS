import Foundation

final class MacroService: ObservableObject {
    @Published private(set) var macros: [Macro] = []
    private let database: JarvisDatabase

    init(database: JarvisDatabase) {
        self.database = database
        reload()
    }

    func reload() {
        macros = database.loadMacros()
    }

    func save(_ macro: Macro) {
        database.saveMacro(macro)
        reload()
    }

    func delete(_ macro: Macro) {
        database.deleteMacro(id: macro.id)
        reload()
    }
}
