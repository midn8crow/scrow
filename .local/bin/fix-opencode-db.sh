#!/bin/bash
set -euo pipefail

DB="$HOME/.local/share/opencode/opencode.db"
CUTOFF_DAYS="${1:-14}"
CUTOFF_MS=$(( $(date +%s) - CUTOFF_DAYS * 86400 ))

if pgrep -x opencode >/dev/null 2>&1 || pgrep -f '^opencode$' >/dev/null 2>&1; then
    echo "ERROR: opencode is running. Quit ALL opencode instances first, then rerun."
    exit 1
fi

if [ ! -f "$DB" ]; then
    echo "ERROR: no database at $DB"
    exit 1
fi

SIZE_BEFORE=$(du -h "$DB" | cut -f1)
echo "Backing up database (${SIZE_BEFORE})..."
cp "$DB" "$DB.bak.$(date +%Y%m%d-%H%M%S)"

OLD_IDS=$(sqlite3 "$DB" "SELECT id FROM session WHERE time_created < ${CUTOFF_MS}000;")
if [ -z "$OLD_IDS" ]; then
    echo "No sessions older than ${CUTOFF_DAYS} days. Only running VACUUM."
    sqlite3 "$DB" "VACUUM;"
    echo "Done. ${SIZE_BEFORE} -> $(du -h "$DB" | cut -f1)"
    exit 0
fi

echo "Pruning $(echo "$OLD_IDS" | wc -l) sessions older than ${CUTOFF_DAYS} days..."
for sid in $OLD_IDS; do
    sqlite3 "$DB" <<SQL
BEGIN;
DELETE FROM part WHERE session_id = '$sid';
DELETE FROM message WHERE session_id = '$sid';
DELETE FROM event WHERE aggregate_id = '$sid';
DELETE FROM event_sequence WHERE aggregate_id = '$sid';
DELETE FROM session WHERE id = '$sid';
COMMIT;
SQL
done

echo "Vacuuming..."
sqlite3 "$DB" "VACUUM;"

echo "Done. ${SIZE_BEFORE} -> $(du -h "$DB" | cut -f1)"
