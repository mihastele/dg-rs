//! datagrip-rs: Open-source database workbench in Rust.
//!
//! A DataGrip alternative built from scratch, with introspection queries
//! reverse-engineered from JetBrains DataGrip's `PgIntroQueries.sql`.
//!
//! Usage:
//!   datagrip-rs connect postgres --host localhost --port 5432 --db mydb --user postgres
//!   datagrip-rs connect sqlite --file ./my.db
//!   datagrip-rs query postgres --host localhost --db mydb --user postgres --sql "SELECT 1"
//!   datagrip-rs introspect postgres --host localhost --db mydb --user postgres

mod db;
mod introspect;
mod model;
mod ui;

use clap::{Parser, Subcommand};
use model::{ConnectionConfig, DbType};

#[derive(Parser)]
#[command(name = "datagrip-rs")]
#[command(about = "Open-source database workbench in Rust — a DataGrip alternative")]
#[command(version)]
#[command(arg_required_else_help = true)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Connect to a database and launch the interactive TUI.
    Connect {
        /// Database type: postgres, sqlite, mysql
        #[arg(value_name = "TYPE")]
        db_type: String,

        #[arg(long, default_value = "localhost")]
        host: String,
        #[arg(long, default_value = "5432")]
        port: u16,
        #[arg(long, default_value = "postgres")]
        db: String,
        #[arg(long, default_value = "postgres")]
        user: String,

        /// Path to SQLite database file.
        #[arg(long)]
        file: Option<String>,
    },

    /// Run a SQL query and print results (headless mode).
    Query {
        #[arg(value_name = "TYPE")]
        db_type: String,

        #[arg(long, default_value = "localhost")]
        host: String,
        #[arg(long, default_value = "5432")]
        port: u16,
        #[arg(long, default_value = "postgres")]
        db: String,
        #[arg(long, default_value = "postgres")]
        user: String,
        #[arg(long)]
        file: Option<String>,

        /// SQL to execute.
        #[arg(short, long)]
        sql: String,

        /// Output format: table, csv, json.
        #[arg(short, long, default_value = "table")]
        format: String,
    },

    /// Introspect a database and print the schema tree (headless mode).
    Introspect {
        #[arg(value_name = "TYPE")]
        db_type: String,

        #[arg(long, default_value = "localhost")]
        host: String,
        #[arg(long, default_value = "5432")]
        port: u16,
        #[arg(long, default_value = "postgres")]
        db: String,
        #[arg(long, default_value = "postgres")]
        user: String,
        #[arg(long)]
        file: Option<String>,
    },
}

fn parse_config(
    db_type: &str,
    host: &str,
    port: u16,
    db: &str,
    user: &str,
    file: Option<String>,
) -> anyhow::Result<ConnectionConfig> {
    match db_type.to_lowercase().as_str() {
        "postgres" | "postgresql" | "pg" => Ok(ConnectionConfig::postgres(host, port, db, user)),
        "sqlite" | "sqlite3" => {
            let path = file.ok_or_else(|| anyhow::anyhow!("SQLite requires --file <path>"))?;
            Ok(ConnectionConfig::sqlite(&path, &path))
        }
        "mysql" | "mariadb" => {
            let mut cfg = ConnectionConfig::postgres(host, port, db, user);
            cfg.db_type = DbType::MySql;
            cfg.name = format!("{}@{}", user, host);
            Ok(cfg)
        }
        other => anyhow::bail!("Unknown database type: '{}'. Use: postgres, sqlite, mysql", other),
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    // No subcommand = show help and exit gracefully
    let Some(command) = cli.command else {
        // This is handled by arg_required_else_help, but just in case:
        eprintln!("Usage: datagrip-rs <COMMAND>\n\nCommands:\n  connect     Connect to a database and launch the interactive TUI\n  query       Run a SQL query and print results (headless mode)\n  introspect  Introspect a database and print the schema tree\n\nOptions:\n  -h, --help     Print help\n  -V, --version  Print version");
        std::process::exit(0);
    };

    match command {
        Commands::Connect {
            db_type,
            host,
            port,
            db,
            user,
            file,
        } => {
            let config = parse_config(&db_type, &host, port, &db, &user, file)?;
            run_tui(config).await?;
        }

        Commands::Query {
            db_type,
            host,
            port,
            db,
            user,
            file,
            sql,
            format,
        } => {
            let config = parse_config(&db_type, &host, port, &db, &user, file)?;
            run_headless_query(&config, &sql, &format).await?;
        }

        Commands::Introspect {
            db_type,
            host,
            port,
            db,
            user,
            file,
        } => {
            let config = parse_config(&db_type, &host, port, &db, &user, file)?;
            run_headless_introspect(&config).await?;
        }
    }

    Ok(())
}

async fn run_headless_query(
    config: &ConnectionConfig,
    sql: &str,
    format: &str,
) -> anyhow::Result<()> {
    let mut db = db::create_connection(config).await?;

    println!("Connected to {}", config.connection_string());
    let version = db.server_version().await?;
    println!("Server: {}", version);
    println!();

    let result = db.query(sql).await?;

    match format {
        "csv" => {
            let mut wtr = csv::Writer::from_writer(std::io::stdout());
            wtr.write_record(&result.columns)?;
            for row in &result.rows {
                let record: Vec<&str> = row
                    .iter()
                    .map(|c| c.as_deref().unwrap_or(""))
                    .collect();
                wtr.write_record(&record)?;
            }
            wtr.flush()?;
        }
        "json" => {
            println!("{}", ui::export::export_json(&result)?);
        }
        _ => {
            // Pretty table
            print_table(&result);
        }
    }

    eprintln!(
        "\n{} rows in {}ms",
        result.row_count, result.execution_time_ms
    );

    Ok(())
}

async fn run_headless_introspect(config: &ConnectionConfig) -> anyhow::Result<()> {
    let mut db = db::create_connection(config).await?;

    println!("Connected to {}", config.connection_string());
    let version = db.server_version().await?;
    println!("Server: {}", version);
    println!();

    let schemas = db.introspect().await?;

    for schema in &schemas {
        println!("📁 Schema: {}", schema.name);
        for table in &schema.tables {
            println!(
                "  {} {} ({} columns)",
                table.kind.icon(),
                table.name,
                table.columns.len()
            );
            for col in &table.columns {
                let pk = if col.is_primary_key { " 🔑" } else { "" };
                let null = if col.nullable { "NULL" } else { "NOT NULL" };
                println!(
                    "      {}{}  {}  {}{}",
                    col.name,
                    pk,
                    col.type_spec,
                    null,
                    col.default_value
                        .as_ref()
                        .map(|d| format!("  DEFAULT {}", d))
                        .unwrap_or_default()
                );
            }
        }
        println!();
    }

    Ok(())
}

fn print_table(result: &model::ResultSet) {
    if result.columns.is_empty() {
        println!("(no results)");
        return;
    }

    // Calculate column widths
    let mut widths: Vec<usize> = result.columns.iter().map(|c| c.len()).collect();
    for row in result.rows.iter().take(1000) {
        for (i, cell) in row.iter().enumerate() {
            let len = cell.as_deref().unwrap_or("NULL").len();
            if len > widths[i] {
                widths[i] = len;
            }
        }
    }
    // Cap widths
    for w in widths.iter_mut() {
        *w = (*w).min(40);
    }

    // Header
    let header: String = result
        .columns
        .iter()
        .enumerate()
        .map(|(i, c)| format!(" {:width$} ", c, width = widths[i]))
        .collect::<Vec<_>>()
        .join("│");
    println!("{}", header);
    println!("{}", "─".repeat(header.len()));

    // Rows
    for row in result.rows.iter().take(1000) {
        let line: String = row
            .iter()
            .enumerate()
            .map(|(i, cell)| {
                let val = cell.as_deref().unwrap_or("NULL");
                let truncated = if val.len() > widths[i] {
                    format!("{}…", &val[..widths[i].saturating_sub(1)])
                } else {
                    val.to_string()
                };
                format!(" {:width$} ", truncated, width = widths[i])
            })
            .collect::<Vec<_>>()
            .join("│");
        println!("{}", line);
    }

    if result.rows.len() > 1000 {
        println!("... ({} more rows)", result.rows.len() - 1000);
    }
}

async fn run_tui(config: ConnectionConfig) -> anyhow::Result<()> {
    use crossterm::{
        event::{self, Event},
        execute,
        terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
    };
    use ratatui::{backend::CrosstermBackend, Terminal};

    // Connect first — if this fails, print error to stderr and exit cleanly
    // (no TUI cleanup needed since we haven't touched the terminal yet)
    let db = match db::create_connection(&config).await {
        Ok(db) => db,
        Err(e) => {
            eprintln!("\n❌ Connection failed: {}", e);
            eprintln!("   Target: {}", config.connection_string());
            eprintln!("\n   Check that:");
            eprintln!("   - The database server is running");
            eprintln!("   - Host/port are correct");
            eprintln!("   - Credentials are correct (set PGPASSWORD env var for PostgreSQL)");
            eprintln!("   - For SQLite, the file path exists");
            std::process::exit(1);
        }
    };

    // Print connection info before entering TUI (visible if TUI fails to start)
    eprintln!("Connected to {}", config.connection_string());

    // Setup terminal — wrap in a guard so we always restore on panic/error
    enable_raw_mode()?;
    let mut stdout = std::io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app
    let mut app = ui::app::App::new(db, config.clone());
    app.load_schemas().await;

    // Get server version
    {
        let db = app.db.lock().await;
        if let Ok(v) = db.server_version().await {
            app.status_message = format!("Connected: {}", v);
        }
    }

    // Event loop with panic safety
    let loop_result: anyhow::Result<()> = async {
        loop {
            terminal.draw(|f| app.render(f))?;

            if event::poll(std::time::Duration::from_millis(100))? {
                if let Event::Key(key) = event::read()? {
                    if handle_key(&mut app, key).await {
                        break;
                    }
                }
            }

            if app.should_quit {
                break;
            }
        }
        Ok(())
    }
    .await;

    // ALWAYS restore terminal, even on error
    let _ = disable_raw_mode();
    let _ = execute!(terminal.backend_mut(), LeaveAlternateScreen);
    let _ = terminal.show_cursor();

    // If the loop errored, report it after terminal is restored
    if let Err(e) = loop_result {
        eprintln!("\n❌ TUI error: {}", e);
        return Err(e);
    }

    Ok(())
}

async fn handle_key(app: &mut ui::app::App, key: crossterm::event::KeyEvent) -> bool {
    use crossterm::event::{KeyCode, KeyModifiers};

    match key.code {
        // Quit
        KeyCode::Char('q') if key.modifiers.contains(KeyModifiers::CONTROL) => return true,

        // Help
        KeyCode::F(1) => {
            app.show_help = !app.show_help;
        }

        // Tab: cycle focus
        KeyCode::Tab => {
            app.focus = match app.focus {
                ui::app::Focus::SchemaTree => ui::app::Focus::SqlEditor,
                ui::app::Focus::SqlEditor => ui::app::Focus::Results,
                ui::app::Focus::Results => ui::app::Focus::SchemaTree,
            };
        }

        // Run query
        KeyCode::F(5) => {
            app.run_query().await;
            app.focus = ui::app::Focus::Results;
        }

        // Ctrl+Enter: run query
        KeyCode::Enter if key.modifiers.contains(KeyModifiers::CONTROL) => {
            app.run_query().await;
            app.focus = ui::app::Focus::Results;
        }

        // Export CSV
        KeyCode::Char('e') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            if let Some(result) = &app.result {
                match ui::export::export_csv(result, "query_export.csv") {
                    Ok(_) => app.status_message = "Exported to query_export.csv".to_string(),
                    Err(e) => app.status_message = format!("Export error: {}", e),
                }
            }
        }

        // Navigation in schema tree
        KeyCode::Up => match app.focus {
            ui::app::Focus::SchemaTree => app.prev_schema(),
            ui::app::Focus::Results => app.scroll_results_up(),
            _ => {}
        },
        KeyCode::Down => match app.focus {
            ui::app::Focus::SchemaTree => app.next_schema(),
            ui::app::Focus::Results => app.scroll_results_down(),
            _ => {}
        },
        KeyCode::Left => {
            if app.focus == ui::app::Focus::SchemaTree {
                if let Some(expanded) = app.expanded_schemas.get_mut(app.selected_schema) {
                    *expanded = false;
                }
            }
        }
        KeyCode::Right => {
            if app.focus == ui::app::Focus::SchemaTree {
                app.toggle_schema();
            }
        }

        // Text input (when not in a special mode)
        KeyCode::Char(c) => {
            if !key.modifiers.contains(KeyModifiers::CONTROL) {
                app.input_char(c);
            }
        }
        KeyCode::Backspace => {
            app.input_backspace();
        }
        KeyCode::Enter => {
            if app.focus == ui::app::Focus::SqlEditor || !app.sql_input.trim().is_empty() {
                app.run_query().await;
                app.focus = ui::app::Focus::Results;
            } else {
                app.input_newline();
            }
        }
        KeyCode::Esc => {
            if app.show_help {
                app.show_help = false;
            } else {
                app.sql_input.clear();
                app.cursor_pos = 0;
            }
        }

        _ => {}
    }

    false
}
