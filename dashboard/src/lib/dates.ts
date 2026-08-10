const pad = (n: number) => String(n).padStart(2, '0')

/** Epoch seconds → YYYY/MM/DD */
export function formatDate(ts: number): string {
  const d = new Date(ts * 1000)
  return `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())}`
}

/** ISO 8601 date string → YYYY/MM/DD (no timezone drift) */
export function formatISODate(iso: string): string {
  const m = iso?.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return '-'
  return `${m[1]}/${m[2]}/${m[3]}`
}

/** Epoch seconds → YYYY/MM/DD HH:MM */
export function formatDateTime(ts: number): string {
  const d = new Date(ts * 1000)
  return `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** Epoch seconds → "Just now" / "Xm ago" / "Xh ago" / YYYY/MM/DD */
export function formatRelative(ts: number): string {
  const d = new Date(ts * 1000)
  const now = new Date()
  const diff = (now.getTime() - d.getTime()) / 1000
  if (diff < 60) return 'Just now'
  if (diff < 3600) return Math.floor(diff / 60) + 'm ago'
  if (diff < 86400) return Math.floor(diff / 3600) + 'h ago'
  return formatDate(ts)
}
