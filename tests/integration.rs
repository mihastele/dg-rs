//! Integration tests for datagrip-rs.
//! Run with: cargo test -- --test-threads=1

use std::process::Command;
use std::sync::Mutex;

/// Serialize DB creation across tests (SQLite file locking).
static DB_LOCK: Mutex<()> = Mutex::new(());

fn test_db_path() -> String {
    let _guard = DB_LOCK.lock().unwrap();

    // Use a path that works with both rusqlite (test) and our binary
    // /tmp/ works in MSYS bash and is accessible from Windows processes
    let path = std::env::temp_dir().join("datagrip_rs_itest.db");
    let path_str = path.to_string_lossy().to_string();

    // Remove old DB
    let _ = std::fs::remove_file(&path);

    // Create test database using rusqlite (same library as the binary)
    let conn = rusqlite::Connection::open(&path).expect("Failed to create test DB");

    conn.execute_batch(
        r#"
        CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            is_active INTEGER DEFAULT 1
        );
        CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id),
            amount REAL NOT NULL,
            status TEXT DEFAULT 'pending'
        );
        CREATE VIEW active_users AS SELECT * FROM users WHERE is_active = 1;
        INSERT INTO users (name, email) VALUES
            ('Alice', 'alice@test.com'),
            ('Bob', 'bob@test.com'),
            ('Carol', 'carol@test.com');
        INSERT INTO orders (user_id, amount, status) VALUES
            (1, 99.99, 'completed'),
            (2, 49.50, 'pending'),
            (1, 199.00, 'completed');
        "#,
    )
    .expect("Failed to populate test DB");

    drop(conn);
    path_str
}

fn datagrip_bin() -> String {
    let mut path = std::env::current_exe()
        .expect("Failed to get current exe")
        .parent()
        .expect("Failed to get parent") // deps/
        .parent()
        .expect("Failed to get parent") // debug/ or release/
        .to_path_buf();
    path.push("datagrip-rs.exe");
    path.to_string_lossy().to_string()
}

#[test]
fn test_introspect_sqlite() {
    let db_path = test_db_path();
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .args(["introspect", "sqlite", "--file", &db_path])
        .output()
        .expect("Failed to run introspect");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "introspect failed: {}", stdout);
    assert!(stdout.contains("Schema: main"), "Should list main schema: {}", stdout);
    assert!(stdout.contains("users"), "Should find users table: {}", stdout);
    assert!(stdout.contains("orders"), "Should find orders table: {}", stdout);
    assert!(stdout.contains("active_users"), "Should find active_users view: {}", stdout);
}

#[test]
fn test_query_table_format() {
    let db_path = test_db_path();
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .args([
            "query", "sqlite", "--file", &db_path,
            "--sql", "SELECT name, email FROM users ORDER BY name",
            "--format", "table",
        ])
        .output()
        .expect("Failed to run query");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        output.status.success(),
        "query failed: stdout={} stderr={}",
        stdout,
        stderr
    );
    assert!(stdout.contains("Alice"), "Should contain Alice: {}", stdout);
    assert!(stdout.contains("Bob"), "Should contain Bob: {}", stdout);
    assert!(stdout.contains("alice@test.com"), "Should contain email: {}", stdout);
    // Row count goes to stderr
    assert!(stderr.contains("3 rows"), "Should report 3 rows: {}", stderr);
}

#[test]
fn test_query_csv_format() {
    let db_path = test_db_path();
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .args([
            "query", "sqlite", "--file", &db_path,
            "--sql", "SELECT id, name FROM users ORDER BY id",
            "--format", "csv",
        ])
        .output()
        .expect("Failed to run query");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "query failed: {}", stdout);
    assert!(stdout.contains("id,name"), "CSV should have header: {}", stdout);
    assert!(stdout.contains("1,Alice"), "CSV should have data row: {}", stdout);
}

#[test]
fn test_query_json_format() {
    let db_path = test_db_path();
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .args([
            "query", "sqlite", "--file", &db_path,
            "--sql", "SELECT COUNT(*) as cnt FROM orders",
            "--format", "json",
        ])
        .output()
        .expect("Failed to run query");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "query failed: {}", stdout);
    assert!(stdout.contains("\"cnt\""), "JSON should have cnt field: {}", stdout);
    assert!(stdout.contains("\"3\""), "JSON should have value 3: {}", stdout);
}

#[test]
fn test_join_query() {
    let db_path = test_db_path();
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .args([
            "query", "sqlite", "--file", &db_path,
            "--sql", "SELECT u.name, COUNT(o.id) as cnt, SUM(o.amount) as total FROM users u LEFT JOIN orders o ON u.id = o.user_id GROUP BY u.id ORDER BY total DESC",
            "--format", "table",
        ])
        .output()
        .expect("Failed to run join query");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "join query failed: {}", stdout);
    assert!(stdout.contains("Alice"), "Alice should appear: {}", stdout);
    assert!(stdout.contains("298"), "Alice total should be ~298.99: {}", stdout);
}

#[test]
fn test_query_error_handling() {
    let db_path = test_db_path();
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .args([
            "query", "sqlite", "--file", &db_path,
            "--sql", "SELECT * FROM nonexistent_table_xyz",
        ])
        .output()
        .expect("Failed to run query");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let combined = format!("{}{}", stdout, stderr).to_lowercase();
    assert!(
        combined.contains("nonexistent") || combined.contains("error") || combined.contains("no such"),
        "Should report error for missing table: {}",
        combined
    );
}

#[test]
fn test_cli_help() {
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .arg("--help")
        .output()
        .expect("Failed to run --help");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success());
    assert!(stdout.contains("connect"), "Should list connect command");
    assert!(stdout.contains("query"), "Should list query command");
    assert!(stdout.contains("introspect"), "Should list introspect command");
}

#[test]
fn test_cli_version() {
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .arg("--version")
        .output()
        .expect("Failed to run --version");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success());
    assert!(stdout.contains("datagrip-rs"), "Should contain app name");
    assert!(stdout.contains("0.1.0"), "Should contain version");
}

#[test]
fn test_view_query() {
    let db_path = test_db_path();
    let bin = datagrip_bin();

    let output = Command::new(&bin)
        .args([
            "query", "sqlite", "--file", &db_path,
            "--sql", "SELECT name FROM active_users ORDER BY name",
            "--format", "table",
        ])
        .output()
        .expect("Failed to query view");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(output.status.success(), "view query failed: {} {}", stdout, stderr);
    assert!(stderr.contains("3 rows"), "View should return 3 rows: {}", stderr);
}
