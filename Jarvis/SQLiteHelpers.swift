import Foundation
import SQLite3

// Provide a Swift-friendly SQLITE_TRANSIENT for sqlite3 text/blob binding and result APIs.
// This matches the C macro ((sqlite3_destructor_type)-1)
public let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
