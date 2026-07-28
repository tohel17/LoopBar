import XCTest
@testable import LoopBar

final class SQLiteJSONQueryTests: XCTestCase {
    func testEmptyStdoutDecodesAsEmptyArray() throws {
        struct Row: Decodable { let id: String }
        let rows = try SQLiteJSONQuery.decodeRows([Row].self, from: Data())
        XCTAssertEqual(rows.count, 0)
    }

    func testWhitespaceStdoutDecodesAsEmptyArray() throws {
        struct Row: Decodable { let id: String }
        let rows = try SQLiteJSONQuery.decodeRows([Row].self, from: Data(" \n\t ".utf8))
        XCTAssertEqual(rows.count, 0)
    }

    func testLargeStdoutDoesNotDeadlock() throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopbar-sqlite-large-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let setup = Process()
        setup.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        // ~2KB payload * 80 rows ≈ 160KB+ JSON — larger than a typical pipe buffer.
        setup.arguments = [
            db.path,
            """
            CREATE TABLE t(id INTEGER, payload TEXT);
            WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 80)
            INSERT INTO t(id, payload)
            SELECT n, printf('%.*c', 2000, 'x') FROM seq;
            """
        ]
        try setup.run()
        setup.waitUntilExit()
        XCTAssertEqual(setup.terminationStatus, 0)

        let started = Date()
        let result = try SQLiteJSONQuery.run(
            database: db,
            query: "SELECT id, payload FROM t ORDER BY id;"
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.stdout.count, 100_000)
        XCTAssertLessThan(elapsed, 5, "Large sqlite stdout should not hang on pipe deadlock")
    }

    func testRunAgainstTempDatabase() throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopbar-sqlite-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let setup = Process()
        setup.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        setup.arguments = [db.path, "CREATE TABLE t(id TEXT); INSERT INTO t VALUES ('a'); INSERT INTO t VALUES ('b');"]
        try setup.run()
        setup.waitUntilExit()
        XCTAssertEqual(setup.terminationStatus, 0)

        struct Row: Decodable { let id: String }
        let result = try SQLiteJSONQuery.run(database: db, query: "SELECT id FROM t ORDER BY id;")
        XCTAssertEqual(result.status, 0)
        let rows = try SQLiteJSONQuery.decodeRows([Row].self, from: result.stdout)
        XCTAssertEqual(rows.map(\.id), ["a", "b"])

        let empty = try SQLiteJSONQuery.run(database: db, query: "SELECT id FROM t WHERE 0;")
        XCTAssertEqual(empty.status, 0)
        let emptyRows = try SQLiteJSONQuery.decodeRows([Row].self, from: empty.stdout)
        XCTAssertTrue(emptyRows.isEmpty)
    }
}
