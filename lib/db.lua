local runtime_config = require("lib.runtime_config")
local sha256 = require("lib.sha256")

local M = {}

-- =============================================================================
-- Schema
-- =============================================================================

function M.ensure_schema()
    M._ensure_monitors()
    M._ensure_check_history()
    M._ensure_settings()
    M._ensure_notifications()
    M._ensure_nodes()
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

-- =============================================================================
-- Monitors — Query
-- =============================================================================

function M.list_all()
    local now = os.time()
    local rows = db_query([[
        SELECT m.*,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ? AND is_up = 1) as up_24h,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ?) as total_24h,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ? AND is_up = 1) as up_7d,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ?) as total_7d,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ? AND is_up = 1) as up_30d,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ?) as total_30d
        FROM monitors m
        ORDER BY m.created_at DESC
    ]], { now - 86400, now - 86400, now - 604800, now - 604800, now - 2592000, now - 2592000 })

    for _, m in ipairs(rows) do
        m.uptime_24h = m.total_24h > 0 and math.floor((m.up_24h / m.total_24h) * 100) or nil
        m.uptime_7d = m.total_7d > 0 and math.floor((m.up_7d / m.total_7d) * 100) or nil
        m.uptime_30d = m.total_30d > 0 and math.floor((m.up_30d / m.total_30d) * 100) or nil
    end

    return rows
end

function M.monitor_list(opts)
    local page = opts.page or 1
    local per_page = opts.per_page or 25
    local sort = opts.sort or "created_at"
    local order = opts.order or "desc"
    local q = opts.q or ""
    local enabled = opts.enabled

    local allowed_sorts = {
        name = "m.name",
        url = "m.url",
        response_time = "m.last_response_time_ms",
        created_at = "m.created_at",
        last_check_at = "m.last_check_at",
    }
    local sort_col = allowed_sorts[sort] or "m.created_at"
    local order_dir = order == "desc" and "DESC" or "ASC"

    local where_parts = {}
    local where_params = {}

    if q ~= "" then
        where_parts[#where_parts + 1] = "(m.name LIKE ? OR m.url LIKE ?)"
        where_params[#where_params + 1] = "%" .. q .. "%"
        where_params[#where_params + 1] = "%" .. q .. "%"
    end

    if enabled ~= nil then
        where_parts[#where_parts + 1] = "m.enabled = ?"
        where_params[#where_params + 1] = enabled
    end

    local where_clause = ""
    if #where_parts > 0 then
        where_clause = " WHERE " .. table.concat(where_parts, " AND ")
    end

    local count_row = db_query("SELECT COUNT(*) as cnt FROM monitors m" .. where_clause, where_params)
    local total = count_row[1].cnt

    local now = os.time()
    local uptime_params = { now - 86400, now - 86400, now - 604800, now - 604800, now - 2592000, now - 2592000 }
    local all_params = {}
    for _, v in ipairs(uptime_params) do all_params[#all_params + 1] = v end
    for _, v in ipairs(where_params) do all_params[#all_params + 1] = v end

    local offset = (page - 1) * per_page
    all_params[#all_params + 1] = per_page
    all_params[#all_params + 1] = offset

    local rows = db_query([[
        SELECT m.*,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ? AND is_up = 1) as up_24h,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ?) as total_24h,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ? AND is_up = 1) as up_7d,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ?) as total_7d,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ? AND is_up = 1) as up_30d,
            (SELECT COUNT(*) FROM check_history WHERE monitor_id = m.id AND checked_at >= ?) as total_30d
        FROM monitors m
    ]] .. where_clause .. " ORDER BY " .. sort_col .. " " .. order_dir .. " LIMIT ? OFFSET ?", all_params)

    for _, m in ipairs(rows) do
        m.uptime_24h = m.total_24h > 0 and math.floor((m.up_24h / m.total_24h) * 100) or nil
        m.uptime_7d = m.total_7d > 0 and math.floor((m.up_7d / m.total_7d) * 100) or nil
        m.uptime_30d = m.total_30d > 0 and math.floor((m.up_30d / m.total_30d) * 100) or nil
    end

    local total_pages = math.ceil(total / per_page)
    if total_pages < 1 then total_pages = 1 end

    return {
        items = rows,
        total = total,
        page = page,
        per_page = per_page,
        total_pages = total_pages,
    }
end

function M.export_all()
    return db_query("SELECT * FROM monitors ORDER BY created_at DESC")
end

function M.export_syncable()
    return db_query([[
        SELECT id, name, url, method, interval_sec, timeout_ms, check_value,
               enabled, desktop_notify, check_cert, cert_threshold_days,
               created_at, updated_at
        FROM monitors
        ORDER BY created_at DESC
    ]])
end

function M.get(id)
    local rows = db_query("SELECT * FROM monitors WHERE id = ?", { id })
    return rows[1]
end

function M.get_by_url(url)
    local rows = db_query("SELECT * FROM monitors WHERE url = ?", { url })
    return rows[1]
end

function M.get_history(id, before, limit)
    return db_query([[
        SELECT id, monitor_id, status_code, response_time_ms, is_up, error_message, checked_at
        FROM check_history
        WHERE monitor_id = ? AND checked_at < ?
        ORDER BY checked_at DESC
        LIMIT ?
    ]], { id, before, limit })
end

function M.get_summary(id, days, group_unit)
    local since = os.time() - (days * 86400)

    if group_unit == "hour" then
        return db_query([[
            SELECT strftime('%Y-%m-%dT%H:00:00', checked_at, 'unixepoch') as period,
                   COUNT(*) as total,
                   SUM(is_up) as up_count
            FROM check_history
            WHERE monitor_id = ? AND checked_at >= ?
            GROUP BY period
            ORDER BY period DESC
        ]], { id, since })
    end

    if group_unit == "halfday" then
        return db_query([[
            SELECT strftime('%Y-%m-%dT', checked_at, 'unixepoch') ||
                   CASE WHEN cast(strftime('%H', checked_at, 'unixepoch') as integer) < 12
                        THEN '00:00:00' ELSE '12:00:00' END as period,
                   COUNT(*) as total,
                   SUM(is_up) as up_count
            FROM check_history
            WHERE monitor_id = ? AND checked_at >= ?
            GROUP BY period
            ORDER BY period DESC
        ]], { id, since })
    end

    -- default: group by day
    return db_query([[
        SELECT date(checked_at, 'unixepoch') as period,
               COUNT(*) as total,
               SUM(is_up) as up_count
        FROM check_history
        WHERE monitor_id = ? AND checked_at >= ?
        GROUP BY period
        ORDER BY period DESC
    ]], { id, since })
end

-- =============================================================================
-- Monitors — Write
-- =============================================================================

function M.insert_monitor(entry)
    local ok, err = pcall(db_exec, [[
        INSERT OR IGNORE INTO monitors (name, url, method, interval_sec, timeout_ms, check_value, enabled, desktop_notify, check_cert, cert_threshold_days)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        entry.name,
        entry.url,
        entry.method or "HEAD",
        entry.interval_sec or 300,
        entry.timeout_ms or 10000,
        entry.check_value or "",
        entry.enabled == nil and 1 or (entry.enabled ~= 0 and 1 or 0),
        entry.desktop_notify == nil and 0 or (entry.desktop_notify ~= 0 and 1 or 0),
        entry.check_cert == nil and 0 or (entry.check_cert ~= 0 and 1 or 0),
        entry.cert_threshold_days or 14,
    })
    return ok, err
end

function M.update_monitor(id, sets, params)
    table.insert(sets, "updated_at = ?")
    table.insert(params, os.time())
    table.insert(params, id)
    db_exec("UPDATE monitors SET " .. table.concat(sets, ", ") .. " WHERE id = ?", params)
end

function M.delete_monitor(id)
    db_exec("DELETE FROM monitors WHERE id = ?", { id })
end

function M.sync_from_central(rows)
    rows = rows or {}
    local now = os.time()
    local seen = {}

    for _, entry in ipairs(rows) do
        local id = tonumber(entry.id)
        if id and entry.name and entry.url then
            seen[#seen + 1] = id
            local current = M.get(id)
            local params = {
                entry.name,
                entry.url,
                entry.method or "HEAD",
                entry.interval_sec or 300,
                entry.timeout_ms or 10000,
                entry.check_value or "",
                entry.enabled == nil and 1 or (entry.enabled ~= 0 and 1 or 0),
                entry.desktop_notify == nil and 0 or (entry.desktop_notify ~= 0 and 1 or 0),
                entry.check_cert == nil and 0 or (entry.check_cert ~= 0 and 1 or 0),
                entry.cert_threshold_days or 14,
                now,
            }

            if current then
                db_exec([[
                    UPDATE monitors
                    SET name = ?, url = ?, method = ?, interval_sec = ?, timeout_ms = ?,
                        check_value = ?, enabled = ?, desktop_notify = ?, check_cert = ?,
                        cert_threshold_days = ?, updated_at = ?
                    WHERE id = ?
                ]], {
                    params[1], params[2], params[3], params[4], params[5], params[6],
                    params[7], params[8], params[9], params[10], params[11], id
                })
            else
                db_exec([[
                    INSERT INTO monitors (
                        id, name, url, method, interval_sec, timeout_ms, check_value,
                        enabled, desktop_notify, check_cert, cert_threshold_days,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ]], {
                    id, params[1], params[2], params[3], params[4], params[5], params[6],
                    params[7], params[8], params[9], params[10], entry.created_at or now, entry.updated_at or now
                })
            end
        end
    end

    local disable_params = { now }
    local disable_clause = ""
    if #seen > 0 then
        local placeholders = {}
        for _, id in ipairs(seen) do
            placeholders[#placeholders + 1] = "?"
            disable_params[#disable_params + 1] = id
        end
        disable_clause = " AND id NOT IN (" .. table.concat(placeholders, ", ") .. ")"
    end

    db_exec("UPDATE monitors SET enabled = 0, updated_at = ? WHERE enabled = 1" .. disable_clause, disable_params)
end

-- =============================================================================
-- Monitors — Lifecycle (used by hooks)
-- =============================================================================

function M.claim_next_due()
    local now = os.time()
    return db_query([[
        UPDATE monitors
        SET last_check_at = ?
        WHERE id = (
            SELECT id FROM monitors
            WHERE enabled = 1
              AND (last_check_at IS NULL OR (? - last_check_at) >= interval_sec)
            ORDER BY last_check_at ASC
            LIMIT 1
        )
        RETURNING id, name, url, method, timeout_ms, check_value, is_up, consecutive_failures,
                  check_cert, cert_threshold_days, cert_last_check
    ]], { now, now })
end

function M.insert_check(monitor_id, status_code, response_time_ms, is_up, error_message)
    local now = os.time()
    db_exec("INSERT INTO check_history (monitor_id, status_code, response_time_ms, is_up, error_message, checked_at) VALUES (?, ?, ?, ?, ?, ?)",
        { monitor_id, status_code, response_time_ms, is_up, error_message, now })
end

function M.update_monitor_status(monitor_id, is_up, status_code, response_time_ms, consecutive_failures)
    local now = os.time()
    db_exec("UPDATE monitors SET is_up = ?, last_status_code = ?, last_response_time_ms = ?, consecutive_failures = ?, updated_at = ? WHERE id = ?",
        { is_up, status_code, response_time_ms, consecutive_failures, now, monitor_id })
end

function M.update_cert_info(monitor_id, not_after, days_left, checked_at)
    db_exec("UPDATE monitors SET cert_not_after = ?, cert_days_left = ?, cert_last_check = ?, updated_at = ? WHERE id = ?",
        { not_after, days_left, checked_at, os.time(), monitor_id })
end

-- =============================================================================
-- Settings
-- =============================================================================

function M.get_settings()
    local rows = db_query("SELECT key, value FROM settings")
    local settings = {}
    for _, row in ipairs(rows) do
        settings[row.key] = row.value
    end

    if runtime_config.enabled() then
        local bootstrap = runtime_config.bootstrap_settings()
        for key, value in pairs(bootstrap) do
            if settings[key] == nil or settings[key] == "" then
                settings[key] = value
            end
        end
    end

    return settings
end

function M.update_settings(data)
    for key, value in pairs(data) do
        db_exec("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", { key, tostring(value) })
    end
    return M.get_settings()
end

function M.get_retention_days()
    local rows = db_query("SELECT value FROM settings WHERE key = 'retention_days'")
    return tonumber(rows[1] and rows[1].value) or 90
end

function M.get_alert_cooldown_sec()
    local rows = db_query("SELECT value FROM settings WHERE key = 'alert_cooldown_sec'")
    return tonumber(rows[1] and rows[1].value) or 300
end

function M.get_cert_threshold_days()
    local rows = db_query("SELECT value FROM settings WHERE key = 'cert_threshold_days'")
    return tonumber(rows[1] and rows[1].value) or 14
end

function M.get_node_by_prefix(prefix)
    local rows = db_query("SELECT * FROM nodes WHERE token_prefix = ?", { prefix })
    return rows[1]
end

function M.get_node(id)
    local rows = db_query("SELECT * FROM nodes WHERE id = ?", { id })
    return rows[1]
end

function M.list_nodes()
    return db_query("SELECT * FROM nodes ORDER BY created_at DESC")
end

function M.create_node(data)
    local token = data.token or ""
    local prefix, secret = token:match("^([^%.]+)%.(.+)$")
    if not prefix or not secret then
        return nil, "invalid token format"
    end

    local ok, err = pcall(db_exec, [[
        INSERT INTO nodes (name, role, token_prefix, token_hash, active)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        data.name,
        data.role or "checker",
        prefix,
        sha256.hex(secret),
        data.active == nil and 1 or (data.active ~= 0 and 1 or 0),
    })
    if not ok then return nil, err end
    return M.get_node_by_prefix(prefix)
end

function M.touch_node(id)
    db_exec("UPDATE nodes SET last_seen_at = ?, updated_at = ? WHERE id = ?", {
        os.time(),
        os.time(),
        id,
    })
end

function M.get_monitors_version()
    local rows = db_query("SELECT value FROM settings WHERE key = 'monitors_version'")
    return tonumber(rows[1] and rows[1].value) or 0
end

function M.bump_monitors_version()
    db_exec("UPDATE settings SET value = CAST(value AS INTEGER) + 1 WHERE key = 'monitors_version'")
end

-- =============================================================================
-- Notification Channels
-- =============================================================================

function M.list_channels()
    return db_query("SELECT * FROM notification_channels ORDER BY name ASC")
end

function M.get_channel(id)
    local rows = db_query("SELECT * FROM notification_channels WHERE id = ?", { id })
    return rows[1]
end

function M.create_channel(data)
    local ok, err = pcall(db_exec, "INSERT INTO notification_channels (name, type, config, enabled) VALUES (?, ?, ?, ?)", {
        data.name,
        data.type,
        data.config or "{}",
        data.enabled == nil and 1 or (data.enabled ~= 0 and 1 or 0)
    })
    if not ok then return nil, err end
    local rows = db_query("SELECT * FROM notification_channels WHERE id = last_insert_rowid()")
    return rows[1]
end

function M.update_channel(id, data)
    local sets = {}
    local params = {}
    local updatable = { "name", "type", "config", "enabled" }
    for _, field in ipairs(updatable) do
        if data[field] ~= nil then
            table.insert(sets, field .. " = ?")
            table.insert(params, data[field])
        end
    end
    if #sets == 0 then return M.get_channel(id) end
    table.insert(params, id)
    db_exec("UPDATE notification_channels SET " .. table.concat(sets, ", ") .. " WHERE id = ?", params)
    return M.get_channel(id)
end

function M.delete_channel(id)
    db_exec("DELETE FROM notification_channels WHERE id = ?", { id })
end

-- =============================================================================
-- Monitor-Channel Relations
-- =============================================================================

function M.get_monitor_channel_ids(monitor_id)
    local rows = db_query("SELECT channel_id FROM monitor_notifications WHERE monitor_id = ?", { monitor_id })
    local ids = {}
    for _, r in ipairs(rows) do
        table.insert(ids, r.channel_id)
    end
    return ids
end

function M.set_monitor_channels(monitor_id, ids)
    db_exec("DELETE FROM monitor_notifications WHERE monitor_id = ?", { monitor_id })
    for _, channel_id in ipairs(ids or {}) do
        db_exec("INSERT INTO monitor_notifications (monitor_id, channel_id) VALUES (?, ?)", { monitor_id, channel_id })
    end
end

function M.get_alert_channels(monitor_id)
    return db_query([[
        SELECT c.* FROM notification_channels c
        JOIN monitor_notifications mn ON mn.channel_id = c.id
        WHERE mn.monitor_id = ? AND c.enabled = 1
    ]], { monitor_id })
end

-- =============================================================================
-- Retention
-- =============================================================================

function M.cleanup_old_history(days)
    days = days or M.get_retention_days()
    local cutoff = os.time() - (days * 86400)
    local deleted = db_exec("DELETE FROM check_history WHERE checked_at < ?", { cutoff })
    return deleted
end

return M
