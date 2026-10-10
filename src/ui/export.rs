//! Export module - save query results to various formats.

use crate::model::ResultSet;
use anyhow::Context;
use std::io::Write;

/// Export results to CSV.
pub fn export_csv(result: &ResultSet, path: &str) -> anyhow::Result<()> {
    let mut wtr = csv::Writer::from_path(path).context("Failed to create CSV file")?;

    // Header
    wtr.write_record(&result.columns)?;

    // Rows
    for row in &result.rows {
        let record: Vec<&str> = row
            .iter()
            .map(|cell| cell.as_deref().unwrap_or(""))
            .collect();
        wtr.write_record(&record)?;
    }

    wtr.flush()?;
    Ok(())
}

/// Export results to JSON array.
pub fn export_json(result: &ResultSet) -> anyhow::Result<String> {
    let data: Vec<serde_json::Map<String, serde_json::Value>> = result
        .rows
        .iter()
        .map(|row| {
            let mut map = serde_json::Map::new();
            for (i, col) in result.columns.iter().enumerate() {
                let value = match &row[i] {
                    Some(v) => serde_json::Value::String(v.clone()),
                    None => serde_json::Value::Null,
                };
                map.insert(col.clone(), value);
            }
            map
        })
        .collect();

    Ok(serde_json::to_string_pretty(&data)?)
}

/// Export results as SQL INSERT statements.
pub fn export_sql_inserts(
    result: &ResultSet,
    table_name: &str,
) -> anyhow::Result<String> {
    let columns = result
        .columns
        .iter()
        .map(|c| format!("\"{}\"", c))
        .collect::<Vec<_>>()
        .join(", ");

    let mut output = String::new();
    for row in &result.rows {
        let values: Vec<String> = row
            .iter()
            .map(|cell| match cell {
                Some(v) => {
                    let escaped = v.replace('\\', "\\\\").replace('\'', "''");
                    format!("'{}'", escaped)
                }
                None => "NULL".to_string(),
            })
            .collect();

        output.push_str(&format!(
            "INSERT INTO \"{}\" ({}) VALUES ({});\n",
            table_name,
            columns,
            values.join(", ")
        ));
    }

    Ok(output)
}

/// Save string to file.
pub fn save_to_file(path: &str, content: &str) -> anyhow::Result<()> {
    let mut file = std::fs::File::create(path).context("Failed to create file")?;
    file.write_all(content.as_bytes())?;
    Ok(())
}
