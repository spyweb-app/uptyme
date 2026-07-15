local M = {}

function M.ensure_schema()
  M._ensure_monitors()
  M._ensure_check_history()
  M._ensure_settings()
  M._ensure_notifications()
  M._ensure_nodes()
  M._ensure_node_reports()
  M._ensure_cluster_monitor_state()
end

function M._ensure_monitors()
  db_exec([[
    CREATE TABLE IF NOT EXISTS monitors (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        name                    TEXT NOT NULL,
        url                     TEXT NOT NULL UNIQUE,
        method                  TEXT DEFAULT 'HEAD',
        interval_sec            INTEGER DEFAULT 300,
        timeout_ms              INTEGER DEFAULT 10000,
        check_value             TEXT DEFAULT '',
        is_up                   INTEGER DEFAULT 1,
        last_status_code        INTEGER,
        last_response_time_ms   INTEGER,
        last_check_at           INTEGER,
        consecutive_failures    INTEGER DEFAULT 0,
        enabled                 INTEGER DEFAULT 1,
        desktop_notify          INTEGER DEFAULT 0,
        check_cert              INTEGER DEFAULT 0,
        cert_threshold_days     INTEGER DEFAULT 14,
        cert_last_check         INTEGER,
        cert_not_after          TEXT,
        cert_days_left          INTEGER,
        created_at              INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER)),
        updated_at              INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER))
    )
  ]])
end

function M._ensure_check_history()
  db_exec([[
    CREATE TABLE IF NOT EXISTS check_history (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        monitor_id      INTEGER NOT NULL,
        status_code     INTEGER,
        response_time_ms INTEGER,
        is_up           INTEGER,
        error_message   TEXT,
        checked_at      INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER)),
        FOREIGN KEY (monitor_id) REFERENCES monitors(id) ON DELETE CASCADE
    )
  ]])
  db_exec([[CREATE INDEX IF NOT EXISTS idx_history_monitor ON check_history(monitor_id, checked_at DESC)]])
end

function M._ensure_settings()
  db_exec([[
    CREATE TABLE IF NOT EXISTS settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )
  ]])
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('role', 'standalone')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('sync_interval_sec', '10')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('node_liveness_sec', '90')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('monitors_version', '0')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('retention_days', '90')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('alert_cooldown_sec', '300')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('instance_name', 'PULSE')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('cert_threshold_days', '14')")
end

function M._ensure_notifications()
  db_exec([[
    CREATE TABLE IF NOT EXISTS notification_channels (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        type        TEXT NOT NULL,
        config      TEXT NOT NULL DEFAULT '{}',
        enabled     INTEGER DEFAULT 1,
        created_at  INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER))
    )
  ]])

  db_exec([[
    CREATE TABLE IF NOT EXISTS monitor_notifications (
        monitor_id  INTEGER NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
        channel_id  INTEGER NOT NULL REFERENCES notification_channels(id) ON DELETE CASCADE,
        PRIMARY KEY (monitor_id, channel_id)
    )
  ]])
end

function M._ensure_nodes()
  db_exec([[
    CREATE TABLE IF NOT EXISTS nodes (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        role          TEXT NOT NULL DEFAULT 'checker',
        token_prefix  TEXT NOT NULL UNIQUE,
        token_hash    TEXT NOT NULL,
        last_seen_at  INTEGER,
        active        INTEGER DEFAULT 1,
        created_at    INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER)),
        updated_at    INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER))
    )
  ]])
end

function M._ensure_node_reports()
  db_exec([[
    CREATE TABLE IF NOT EXISTS node_reports (
        monitor_id       INTEGER NOT NULL,
        node_id          INTEGER NOT NULL,
        is_up            INTEGER NOT NULL,
        status_code      INTEGER,
        response_time_ms INTEGER,
        error_message    TEXT,
        reported_at      INTEGER NOT NULL,
        PRIMARY KEY (monitor_id, node_id)
    )
  ]])
end

function M._ensure_cluster_monitor_state()
  db_exec([[
    CREATE TABLE IF NOT EXISTS cluster_monitor_state (
        monitor_id          INTEGER PRIMARY KEY,
        current_status      TEXT NOT NULL,
        last_transition_at  INTEGER,
        last_alerted_status TEXT,
        last_alerted_at     INTEGER,
        updated_at          INTEGER NOT NULL
    )
  ]])
end

return M
