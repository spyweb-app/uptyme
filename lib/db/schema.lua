local M = {}

function M.ensure_schema()
  M._ensure_monitors()
  M._ensure_check_history()
  M._ensure_settings()
  M._ensure_notifications()
  M._ensure_nodes()
  M._ensure_node_reports()
  M._ensure_cluster_monitor_state()
  M._ensure_consensus_transitions()
  M._ensure_status_pages()
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
        cert_threshold_days     INTEGER DEFAULT 0,
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
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('node_liveness_sec', '90')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('monitors_version', '0')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('retention_days', '90')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('alert_cooldown_sec', '300')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('instance_name', 'UPTYME')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('cert_threshold_days', '14')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('consensus_min_nodes', '2')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('consensus_quorum_pct', '51')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('treat_4xx_as_down', '0')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('status_page_slug_style', 'name_random')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('status_page_random_length', '5')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('status_page_name_max_length', '20')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('status_page_theme', 'light')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('checker_stale_alert', '0')")
  db_exec("INSERT OR IGNORE INTO settings (key, value) VALUES ('checker_stale_channel_id', '0')")
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
        local_name    TEXT,
        role          TEXT NOT NULL DEFAULT 'checker',
        token_prefix  TEXT NOT NULL UNIQUE,
        token_hash    TEXT NOT NULL,
        last_seen_at  INTEGER,
        active        INTEGER DEFAULT 1,
        stale_alert_minutes INTEGER NOT NULL DEFAULT 0,
        stale_alerted_at    INTEGER,
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

function M._ensure_consensus_transitions()
  db_exec([[
    CREATE TABLE IF NOT EXISTS consensus_transitions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        monitor_id      INTEGER NOT NULL,
        status          TEXT NOT NULL CHECK (status IN ('UP', 'DOWN')),
        transitioned_at INTEGER NOT NULL
    )
  ]])
  db_exec([[CREATE INDEX IF NOT EXISTS idx_consensus_transitions_monitor
    ON consensus_transitions(monitor_id, transitioned_at)]])
end

function M._ensure_status_pages()
  db_exec([[
    CREATE TABLE IF NOT EXISTS status_pages (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        slug        TEXT NOT NULL UNIQUE,
        type        TEXT NOT NULL CHECK (type IN ('monitor', 'group')),
        monitor_id  INTEGER REFERENCES monitors(id) ON DELETE CASCADE,
        name        TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        is_public   INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER)),
        updated_at  INTEGER DEFAULT (cast(strftime('%s','now') AS INTEGER))
    )
  ]])
  db_exec([[CREATE UNIQUE INDEX IF NOT EXISTS idx_status_pages_monitor
    ON status_pages(monitor_id) WHERE type = 'monitor']])
  db_exec([[
    CREATE TABLE IF NOT EXISTS status_page_monitors (
        status_page_id INTEGER NOT NULL REFERENCES status_pages(id) ON DELETE CASCADE,
        monitor_id     INTEGER NOT NULL REFERENCES monitors(id) ON DELETE CASCADE,
        display_order  INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (status_page_id, monitor_id)
    )
  ]])
  db_exec([[CREATE INDEX IF NOT EXISTS idx_status_page_monitors_monitor
    ON status_page_monitors(monitor_id)]])
end

return M
