#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."

DB="data"
MONITORS_FILE="scripts/monitors.txt"
CENTRAL=0

for arg in "$@"; do
  case "$arg" in
    --central) CENTRAL=1 ;;
  esac
done

if [ ! -f "$DB" ]; then
  echo "Database not found at $DB"
  echo "Start spyweb at least once so the schema is created, then run this script."
  exit 1
fi

if [ ! -f "$MONITORS_FILE" ]; then
  echo "Monitors file not found at $MONITORS_FILE"
  exit 1
fi

if [ "$CENTRAL" -eq 1 ]; then
  echo "Seeding $DB (central mode: consensus_transitions + node_reports + cluster_monitor_state) ..."
else
  echo "Seeding $DB (standalone mode) ..."
fi

TOTAL=0
while IFS='|' read -r name url; do
  [ -z "$name" ] && continue
  [ "$name" = "name" ] && continue

  EXISTS=$(sqlite3 "$DB" "SELECT id FROM monitors WHERE url = '$url';")
  if [ -n "$EXISTS" ]; then
    echo "  Skipping $name - URL already exists (monitor #$EXISTS)"
    continue
  fi

  MON_ID=$(sqlite3 "$DB" "INSERT INTO monitors (name, url, interval_sec, timeout_ms, is_up, enabled, last_status_code, last_response_time_ms, last_check_at) VALUES ('$name', '$url', 300, 10000, 1, 1, 200, 42, cast(strftime('%s','now') as integer)); SELECT last_insert_rowid();")

  echo "  Seeding monitor #$MON_ID: $name"

  sqlite3 "$DB" << ENDSQL
----------------------------------------------------------------------
-- Prep: temp table to hold shared random fate per section
----------------------------------------------------------------------
DROP TABLE IF EXISTS temp.fate;
CREATE TEMP TABLE fate (rn INTEGER PRIMARY KEY, val INTEGER);

----------------------------------------------------------------------
-- 1. Hourly - last 24h, ~6 checks/hr (every 10 min), 144 rows
----------------------------------------------------------------------
INSERT INTO fate (rn, val)
  WITH RECURSIVE
    hours(h) AS (SELECT 0 UNION ALL SELECT h + 1 FROM hours WHERE h < 23),
    slots(s) AS (SELECT 0 UNION ALL SELECT s + 1 FROM slots WHERE s < 5)
  SELECT h * 6 + s, ABS(RANDOM()) % 100 FROM hours, slots;

WITH RECURSIVE
  hours(h) AS (SELECT 0 UNION ALL SELECT h + 1 FROM hours WHERE h < 23),
  slots(s) AS (SELECT 0 UNION ALL SELECT s + 1 FROM slots WHERE s < 5)
INSERT INTO check_history (monitor_id, status_code, response_time_ms, is_up, checked_at)
SELECT
  $MON_ID,
  CASE
    WHEN f.val < 4 THEN 503
    WHEN f.val < 7 THEN 200 + (ABS(RANDOM()) % 200)
    ELSE 200
  END,
  CASE
    WHEN f.val < 4 THEN 300 + (ABS(RANDOM()) % 800)
    WHEN (ABS(RANDOM()) % 25 = 0) THEN 120 + (ABS(RANDOM()) % 300)
    ELSE 25 + ABS(12 - h) * 3 + (ABS(RANDOM()) % 35)
  END,
  CASE WHEN f.val < 4 THEN 0 ELSE 1 END,
  cast(strftime('%s', 'now', '-' || (23 - h) || ' hours', '+' || (s * 10) || ' minutes') as integer)
FROM hours, slots
JOIN fate f ON f.rn = h * 6 + s;

DELETE FROM fate;

----------------------------------------------------------------------
-- 2. Half-day - days 7-1 ago, 24 checks per half-day
----------------------------------------------------------------------
INSERT INTO fate (rn, val)
  WITH RECURSIVE
    days(d) AS (SELECT 1 UNION ALL SELECT d + 1 FROM days WHERE d < 7),
    halves(h) AS (SELECT 0 UNION ALL SELECT 1),
    slots(s) AS (SELECT 0 UNION ALL SELECT s + 1 FROM slots WHERE s < 23)
  SELECT d * 48 + h * 24 + s, ABS(RANDOM()) % 100 FROM days, halves, slots;

WITH RECURSIVE
  days(d) AS (SELECT 1 UNION ALL SELECT d + 1 FROM days WHERE d < 7),
  halves(h) AS (SELECT 0 UNION ALL SELECT 1),
  slots(s) AS (SELECT 0 UNION ALL SELECT s + 1 FROM slots WHERE s < 23)
INSERT INTO check_history (monitor_id, status_code, response_time_ms, is_up, checked_at)
SELECT
  $MON_ID,
  CASE
    WHEN f.val < 6 THEN 500
    WHEN f.val < 9 THEN 200 + (ABS(RANDOM()) % 200)
    ELSE 200
  END,
  CASE
    WHEN f.val < 6 THEN 300 + (ABS(RANDOM()) % 900)
    WHEN (ABS(RANDOM()) % 30 = 0) THEN 120 + (ABS(RANDOM()) % 300)
    ELSE 40 + (ABS(RANDOM()) % 55)
  END,
  CASE WHEN f.val < 6 THEN 0 ELSE 1 END,
  cast(strftime('%s', 'now', '-' || d || ' days', 'start of day') as integer)
    + CASE WHEN h = 0 THEN 3600 + s * 1500 ELSE 43200 + s * 1500 END
FROM days, halves, slots
JOIN fate f ON f.rn = d * 48 + h * 24 + s;

DELETE FROM fate;

----------------------------------------------------------------------
-- 3. Daily - days 30-7 ago, ~24 checks/day (every ~1 hr)
----------------------------------------------------------------------
INSERT INTO fate (rn, val)
  WITH RECURSIVE
    days(d) AS (SELECT 7 UNION ALL SELECT d + 1 FROM days WHERE d < 30),
    slots(s) AS (SELECT 0 UNION ALL SELECT s + 1 FROM slots WHERE s < 23)
  SELECT d * 24 + s, ABS(RANDOM()) % 100 FROM days, slots;

WITH RECURSIVE
  days(d) AS (SELECT 7 UNION ALL SELECT d + 1 FROM days WHERE d < 30),
  slots(s) AS (SELECT 0 UNION ALL SELECT s + 1 FROM slots WHERE s < 23)
INSERT INTO check_history (monitor_id, status_code, response_time_ms, is_up, checked_at)
SELECT
  $MON_ID,
  CASE
    WHEN f.val < 4 THEN 503
    WHEN f.val < 7 THEN 200 + (ABS(RANDOM()) % 200)
    ELSE 200
  END,
  CASE
    WHEN f.val < 4 THEN 300 + (ABS(RANDOM()) % 800)
    WHEN (ABS(RANDOM()) % 30 = 0) THEN 120 + (ABS(RANDOM()) % 300)
    ELSE 50 + (ABS(RANDOM()) % 50)
  END,
  CASE WHEN f.val < 4 THEN 0 ELSE 1 END,
  cast(strftime('%s', 'now', '-' || d || ' days', 'start of day') as integer) + s * 3600
FROM days, slots
JOIN fate f ON f.rn = d * 24 + s;

DROP TABLE IF EXISTS temp.fate;
ENDSQL

  if [ "$CENTRAL" -eq 1 ]; then
    NOW=$(sqlite3 "$DB" "SELECT cast(strftime('%s','now') as integer);")

    sqlite3 "$DB" << ENDSQL
-- node_reports: central's own vote for this monitor
INSERT OR IGNORE INTO node_reports (monitor_id, node_id, is_up, status_code, response_time_ms, reported_at)
SELECT $MON_ID, 1, is_up, status_code, response_time_ms, checked_at
FROM check_history WHERE monitor_id = $MON_ID ORDER BY checked_at DESC LIMIT 1;

-- consensus_transitions: detect state changes from check_history
INSERT INTO consensus_transitions (monitor_id, status, transitioned_at)
SELECT $MON_ID,
       CASE WHEN is_up = 0 THEN 'DOWN' ELSE 'UP' END,
       checked_at
FROM (
  SELECT is_up, checked_at,
         LAG(is_up) OVER (ORDER BY checked_at) AS prev_is_up
  FROM check_history WHERE monitor_id = $MON_ID
)
WHERE prev_is_up IS NOT NULL AND is_up != prev_is_up;

-- cluster_monitor_state: current status = last check
INSERT OR IGNORE INTO cluster_monitor_state (monitor_id, current_status, last_transition_at, updated_at)
SELECT $MON_ID,
       CASE WHEN is_up = 1 THEN 'UP' ELSE 'DOWN' END,
       checked_at,
       $NOW
FROM check_history WHERE monitor_id = $MON_ID ORDER BY checked_at DESC LIMIT 1;
ENDSQL

    CT_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM consensus_transitions WHERE monitor_id = $MON_ID;")
    echo "    + consensus_transitions: $CT_COUNT rows"
  fi

  TOTAL=$((TOTAL + 1))
done < "$MONITORS_FILE"

echo ""
echo "Done. Total monitors seeded: $TOTAL"
echo ""
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM check_history")
echo "Total check_history rows: $COUNT"
if [ "$CENTRAL" -eq 1 ]; then
  CT_TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM consensus_transitions")
  echo "Total consensus_transitions rows: $CT_TOTAL"
  NR_TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM node_reports")
  echo "Total node_reports rows: $NR_TOTAL"
fi
