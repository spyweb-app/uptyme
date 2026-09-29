export interface PublicMonitorStatus {
  monitor_id?: number
  name: string
  slug?: string
  status: 'operational' | 'blocked' | 'down' | 'unknown'
  last_checked_at: number | null
  summary?: { period: string; total: number; up_count: number; down_checks: number; blocked_checks: number; avg_response_ms: number | null }[]
}

export interface PublicIncident {
  monitor_id: number
  name: string
  url: string
  status: string
  started_at: number | null
  resolved_at: number | null
}

export interface PublicMonitorPage extends PublicMonitorStatus {
  description?: string
  last_response_time_ms?: number | null
  last_status_code?: number | null
  interval_sec?: number
  uptime_24h?: number | null
  uptime_7d?: number | null
  uptime_30d?: number | null
  summary?: { period: string; total: number; up_count: number; down_checks: number; blocked_checks: number; avg_response_ms: number | null }[]
  history?: { id: number; monitor_id: number; status_code: number; response_time_ms: number; is_up: number; error_message: string | null; checked_at: number }[]
  incidents?: PublicIncident[]
}

export interface PublicGroupPage {
  name: string
  description: string
  slug: string
  status: PublicMonitorStatus['status']
  monitor_count: number
  operational_count: number
  blocked_count: number
  down_count: number
  unknown_count: number
  monitors: PublicMonitorStatus[]
  incidents: PublicIncident[]
}

export type PublicStatusPage = (PublicMonitorPage | PublicGroupPage) & { theme?: string; instance_name?: string }

export interface PublicReport {
  summary: NonNullable<PublicMonitorStatus['summary']>
  months: string[]
}

export async function getPublicStatus(slug: string, params?: { days?: number; group?: string; month?: string }): Promise<PublicStatusPage> {
  let url = '/api/public/status/' + encodeURIComponent(slug)
  if (params) {
    const qs = new URLSearchParams()
    if (params.days != null) qs.set('days', String(params.days))
    if (params.group) qs.set('group', params.group)
    if (params.month) qs.set('month', params.month)
    const qsStr = qs.toString()
    if (qsStr) url += '?' + qsStr
  }
  const res = await fetch(url)
  const json = await res.json().catch(() => ({}))
  if (!res.ok || !json.success) {
    throw new Error(res.status === 404 ? 'Status page not found' : (json.error || 'Unable to load status page'))
  }
  return json.data as PublicStatusPage
}

export async function getPublicReport(
  slug: string,
  params: { month?: string; days?: number; group?: string; monitorId?: number } = {},
): Promise<PublicReport> {
  const qs = new URLSearchParams()
  if (params.month) qs.set('month', params.month)
  if (params.days != null) qs.set('days', String(params.days))
  if (params.group) qs.set('group', params.group)
  if (params.monitorId != null) qs.set('monitor_id', String(params.monitorId))

  const query = qs.toString()
  const url = `/api/public/status/${encodeURIComponent(slug)}/report${query ? `?${query}` : ''}`
  const res = await fetch(url)
  const json = await res.json().catch(() => ({}))
  if (!res.ok || !json.success) throw new Error(json.error || 'Unable to load report')
  return json.data as PublicReport
}
