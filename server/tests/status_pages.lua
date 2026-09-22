local H = require("server.tests.helpers")
local db = require("lib.db")
local status_page = require("lib.db.public_status")

function test_status_page_schema()
    db.ensure_schema()
    local tables = db_query([[SELECT name FROM sqlite_master
        WHERE type = 'table' AND name IN ('status_pages', 'status_page_monitors')
        ORDER BY name]])
    spyweb.assert_eq(#tables, 2)
    spyweb.assert_eq(tables[1].name, "status_page_monitors")
    spyweb.assert_eq(tables[2].name, "status_pages")
end

function test_status_page_crud_slug_and_membership()
    db.ensure_schema()
    db_exec("DELETE FROM status_page_monitors")
    db_exec("DELETE FROM status_pages")
    db_exec("DELETE FROM monitors")

    local monitor_id = db_query([[INSERT INTO monitors (name, url)
        VALUES ('Public Phase 1', 'https://public-phase-1.example.com') RETURNING id]])[1].id

    local monitor_page, err = db.create_status_page({
        type = "monitor",
        monitor_id = monitor_id,
        name = "Public Service",
        description = "Public service description",
        is_public = true,
    })
    spyweb.assert_ne(monitor_page, nil)
    spyweb.assert_eq(err, nil)
    spyweb.assert_eq(monitor_page.type, "monitor")
    spyweb.assert_eq(monitor_page.monitor_id, monitor_id)
    spyweb.assert_eq(monitor_page.is_public, 1)
    local monitor_slug = monitor_page.slug

    local updated = db.update_status_page(monitor_page.id, {
        name = "Renamed Public Service",
        is_public = false,
    })
    spyweb.assert_eq(updated.name, "Renamed Public Service")
    spyweb.assert_eq(updated.is_public, 0)
    spyweb.assert_eq(updated.slug, monitor_slug)

    local group = db.create_status_page({
        type = "group",
        name = "Public Service Group",
        is_public = true,
    })
    spyweb.assert_ne(group, nil)
    spyweb.assert_eq(group.monitor_id, nil)
    spyweb.assert_eq(group.is_public, 1)

    local membership = db.add_status_page_monitor(group.id, monitor_id, 4)
    spyweb.assert_ne(membership, nil)
    spyweb.assert_eq(membership.display_order, 4)
    local members = db.list_status_page_monitors(group.id)
    spyweb.assert_eq(#members, 1)
    spyweb.assert_eq(members[1].id, monitor_id)

    local reordered = db.update_status_page_monitor_order(group.id, monitor_id, 1)
    spyweb.assert_eq(reordered.display_order, 1)
    db.remove_status_page_monitor(group.id, monitor_id)
    spyweb.assert_eq(#db.list_status_page_monitors(group.id), 0)

    db.add_status_page_monitor(group.id, monitor_id, 0)
    db.delete_status_page(group.id)
    spyweb.assert_eq(db.get_status_page(group.id), nil)
    spyweb.assert_ne(db.get(monitor_id), nil)

    db.delete_monitor(monitor_id)
    spyweb.assert_eq(db.get(monitor_id), nil)
    spyweb.assert_eq(db.get_status_page(monitor_page.id), nil)
end

function test_status_page_membership_rejects_monitor_pages()
    db.ensure_schema()
    db_exec("DELETE FROM status_page_monitors")
    db_exec("DELETE FROM status_pages")
    db_exec("DELETE FROM monitors")

    local monitor_id = db_query([[INSERT INTO monitors (name, url)
        VALUES ('Membership Test', 'https://membership-test.example.com') RETURNING id]])[1].id
    local page = db.create_status_page({ type = "monitor", monitor_id = monitor_id, name = "Monitor Page" })
    local membership, err = db.add_status_page_monitor(page.id, monitor_id, 0)
    spyweb.assert_eq(membership, nil)
    spyweb.assert_eq(err, "monitor pages cannot have members")
    db.delete_monitor(monitor_id)
end

function test_public_status_normalization()
    spyweb.assert_eq(status_page.normalize_status(nil, nil), "unknown")
    spyweb.assert_eq(status_page.normalize_status(1, 200), "operational")
    spyweb.assert_eq(status_page.normalize_status(1, 403), "blocked")
    spyweb.assert_eq(status_page.normalize_status(0, 500), "down")
end

function test_public_report_group_member_uses_group_slug_and_utc_month()
    db.ensure_schema()
    db_exec("DELETE FROM status_page_monitors")
    db_exec("DELETE FROM status_pages")
    db_exec("DELETE FROM check_history")
    db_exec("DELETE FROM monitors")

    local monitor_id = db_query([[INSERT INTO monitors (name, url)
        VALUES ('Group-only Report Monitor', 'https://group-only-report.example.com') RETURNING id]])[1].id
    local other_id = db_query([[INSERT INTO monitors (name, url)
        VALUES ('Other Report Monitor', 'https://other-report.example.com') RETURNING id]])[1].id
    local page = db.create_status_page({ type = "group", name = "Report Group", is_public = true })
    db.add_status_page_monitor(page.id, monitor_id, 0)

    db_exec([[INSERT INTO check_history (monitor_id, status_code, is_up, checked_at)
        VALUES (?, 200, 1, CAST(strftime('%s', ?) AS INTEGER))]], { monitor_id, "2025-01-31 23:30:00" })
    db_exec([[INSERT INTO check_history (monitor_id, status_code, is_up, checked_at)
        VALUES (?, 500, 0, CAST(strftime('%s', ?) AS INTEGER))]], { monitor_id, "2025-02-01 00:30:00" })

    local report, err = db.get_public_report(page.slug, { month = "2025-01" }, monitor_id)
    spyweb.assert_ne(report, nil)
    spyweb.assert_eq(err, nil)
    spyweb.assert_eq(#report.summary, 1)
    spyweb.assert_eq(report.summary[1].period, "2025-01-31")
    spyweb.assert_eq(report.months[1], "2025-02")
    spyweb.assert_eq(report.months[2], "2025-01")

    local denied = db.get_public_report(page.slug, { month = "2025-01" }, other_id)
    spyweb.assert_eq(denied, nil)

    local invalid, invalid_err = db.get_public_report(page.slug, { days = 0 }, monitor_id)
    spyweb.assert_eq(invalid, nil)
    spyweb.assert_eq(invalid_err, "Invalid days")

    local response = json_decode(http_get(H.public_api("/status/" .. page.slug .. "/report?month=2025-01&monitor_id=" .. monitor_id)).body)
    spyweb.assert_eq(response.success, true)
    spyweb.assert_eq(#response.data.summary, 1)

    db.delete_status_page(page.id)
    db.delete_monitor(monitor_id)
    db.delete_monitor(other_id)
end

function test_public_group_status_aggregates_members()
    db.ensure_schema()
    db_exec("DELETE FROM status_page_monitors")
    db_exec("DELETE FROM status_pages")
    db_exec("DELETE FROM monitors")

    local ids = {}
    for i, state in ipairs({ 1, 1, 0 }) do
        ids[i] = db_query("INSERT INTO monitors (name, url, is_up, last_status_code) VALUES (?, ?, ?, ?) RETURNING id", {
            "Group Monitor " .. i,
            "https://group-monitor-" .. i .. ".example.com",
            state,
            state == 0 and 500 or (i == 2 and 403 or 200),
        })[1].id
    end

    local page = db.create_status_page({ type = "group", name = "Aggregate Group", is_public = true })
    db.add_status_page_monitor(page.id, ids[1], 2)
    db.add_status_page_monitor(page.id, ids[2], 1)
    db.add_status_page_monitor(page.id, ids[3], 3)

    local result = db.get_public_group_status(page.id)
    spyweb.assert_eq(result.status, "down")
    spyweb.assert_eq(result.monitor_count, 3)
    spyweb.assert_eq(result.operational_count, 1)
    spyweb.assert_eq(result.blocked_count, 1)
    spyweb.assert_eq(result.down_count, 1)
    spyweb.assert_eq(#result.monitors, 3)
    spyweb.assert_eq(#result.incidents, 0)  -- no check_history transitions seeded
    spyweb.assert_eq(result.monitors[1].name, "Group Monitor 2")

    db.delete_status_page(page.id)
    for _, id in ipairs(ids) do db.delete_monitor(id) end
end

function test_public_monitor_status_uses_consensus()
    db.ensure_schema()
    db_exec("DELETE FROM status_page_monitors")
    db_exec("DELETE FROM status_pages")
    db_exec("DELETE FROM monitors")

    local monitor_id = db_query([[INSERT INTO monitors (name, url, is_up, last_status_code)
        VALUES ('Consensus Monitor', 'https://consensus-monitor.example.com', 0, 500)
        RETURNING id]])[1].id
    local page = db.create_status_page({ type = "monitor", monitor_id = monitor_id, name = "Consensus Service", is_public = true })

    db_exec([[INSERT INTO node_reports (monitor_id, node_id, is_up, status_code, reported_at)
        VALUES (?, 1, 1, 200, ?)]], { monitor_id, os.time() })
    db_exec([[INSERT INTO cluster_monitor_state (monitor_id, current_status, last_transition_at, updated_at)
        VALUES (?, 'UP', ?, ?)]], { monitor_id, os.time(), os.time() })

    local result = db.get_public_monitor_status(page.id)
    spyweb.assert_eq(result.name, "Consensus Service")
    spyweb.assert_eq(result.status, "operational")

    db.delete_monitor(monitor_id)
end

function test_status_page_admin_api_crud_and_membership()
    db.ensure_schema()
    db_exec("DELETE FROM status_page_monitors")
    db_exec("DELETE FROM status_pages")
    db_exec("DELETE FROM monitors")

    local monitor_id = db_query([[INSERT INTO monitors (name, url)
        VALUES ('Admin API Monitor', 'https://admin-api-monitor.example.com') RETURNING id]])[1].id
    local headers = { ["Content-Type"] = "application/json" }

    local created = json_decode(http_post(H.api("/status_pages"), json_encode({
        type = "group", name = "Admin API Group", description = "Managed group",
        is_public = true,
    }), headers).body)
    spyweb.assert_eq(created.success, true)
    spyweb.assert_eq(created.data.type, "group")

    local page_id = created.data.id
    local added = json_decode(http_post(H.api("/status_pages/" .. page_id .. "/monitors"), json_encode({
        monitor_id = monitor_id, display_order = 2,
    }), headers).body)
    spyweb.assert_eq(added.success, true)
    spyweb.assert_eq(added.data.display_order, 2)

    local listed = json_decode(http_get(H.api("/status_pages/" .. page_id .. "/monitors")).body)
    spyweb.assert_eq(#listed.data, 1)
    spyweb.assert_eq(listed.data[1].id, monitor_id)

    local updated = json_decode(http_request({
        method = "PUT", url = H.api("/status_pages/" .. page_id),
        body = json_encode({ name = "Renamed Admin Group", is_public = false }), headers = headers,
    }).body)
    spyweb.assert_eq(updated.data.name, "Renamed Admin Group")
    spyweb.assert_eq(updated.data.is_public, 0)

    local removed = json_decode(http_request({
        method = "DELETE", url = H.api("/status_pages/" .. page_id .. "/monitors/" .. monitor_id), headers = {},
    }).body)
    spyweb.assert_eq(removed.data.deleted, true)

    local deleted = json_decode(http_request({
        method = "DELETE", url = H.api("/status_pages/" .. page_id), headers = {},
    }).body)
    spyweb.assert_eq(deleted.data.deleted, true)
    spyweb.assert_ne(db.get(monitor_id), nil)
    db.delete_monitor(monitor_id)
end
