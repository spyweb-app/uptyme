import { apiKey, showAuthModal } from '~stores/auth'
import { instanceName, showNotification } from '~stores/app'

const BASE = '/api/v'

function proxyError(status: number): Error {
  const message = status === 403
    ? `Blocked (HTTP ${status}) - your IP is likely restricted or not allowlisted by the reverse proxy`
    : `Expected JSON but got an HTML page (HTTP ${status}) - a reverse proxy answered instead of the app. Check that it forwards /api/*`
  const err = new Error(message) as Error & { proxy?: boolean }
  err.proxy = true
  return err
}

async function request<T>(url: string, opts?: RequestInit): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (apiKey.value) headers['X-SpyWeb-Key'] = apiKey.value

  const res = await fetch(BASE + url, {
    ...opts,
    headers: { ...headers, ...opts?.headers as Record<string, string> | undefined },
  })

  if (res.status === 401) {
    if (!showAuthModal.value) showAuthModal.value = true
    throw new Error('Unauthorized')
  }

  let json: any
  try {
    json = await res.json()
  } catch {
    const err = proxyError(res.status)
    showNotification(err.message, 'error')
    throw err
  }

  if (!json.success) throw new Error(json.error || `Request failed (HTTP ${res.status})`)

  let data = json.data
  if (data?.items && !Array.isArray(data.items)) data.items = []
  return data as T
}

const qs = (p?: Record<string, string | number | undefined>) => {
  if (!p) return ''
  const pairs = Object.entries(p).filter(([, v]) => v !== undefined)
  if (!pairs.length) return ''
  return '?' + pairs.map(([k, v]) => k + '=' + encodeURIComponent(String(v))).join('&')
}

const get = <T>(url: string, p?: Record<string, string | number | undefined>) => request<T>(url + qs(p))
const post = <T>(url: string, data: unknown) => request<T>(url, { method: 'POST', body: JSON.stringify(data) })
const put = <T>(url: string, data?: unknown) => request<T>(url, { method: 'PUT', body: JSON.stringify(data) })
const del = (url: string) => request<{ deleted: boolean }>(url, { method: 'DELETE' })

export interface PaginatedResult<T> {
  items: T[]
  total: number
  page: number
  per_page: number
  total_pages: number
}

export interface Monitor {
  id: number
  name: string
  url: string
  method: string
  interval_sec: number
  timeout_ms: number
  check_value: string
  desktop_notify: number
  is_up: number
  last_status_code: number | null
  last_response_time_ms: number | null
  last_check_at: number | null
  consecutive_failures: number
  enabled: number
  check_cert: number
  cert_threshold_days: number
  cert_last_check: number | null
  cert_not_after: string | null
  cert_days_left: number | null
  created_at: number
  updated_at: number
  uptime_24h: number | null
  uptime_7d: number | null
  uptime_30d: number | null
}

export interface Check {
  id: number
  monitor_id: number
  status_code: number
  response_time_ms: number
  is_up: number
  error_message: string | null
  checked_at: number
}

export interface DaySummary {
  period: string
  total: number
  up_count: number
  down_checks: number
  blocked_checks: number
  avg_response_ms: number | null
}

export interface Settings {
  [key: string]: string
}

export interface NotificationChannel {
  id: number
  name: string
  type: string
  config: string
  enabled: number
  created_at: number
}

export interface ClusterNode {
  id: number
  name: string
  local_name?: string
  role: string
  last_seen_at: number | null
  active: number
  created_at: number
  updated_at: number
  stale_alert_minutes?: number
}

export interface NodeDetail extends ClusterNode {
  token_prefix: string
}

export interface NodeReport {
  monitor_id: number
  monitor_name: string | null
  monitor_url: string | null
  is_up: number
  status_code: number | null
  response_time_ms: number | null
  error_message: string | null
  reported_at: number
}

export interface Health {
  status: string
  headless: boolean
}

export interface StatusPage {
  id: number
  slug: string
  type: 'monitor' | 'group'
  monitor_id: number | null
  name: string
  description: string
  is_public: number
  created_at: number
  updated_at: number
}

export interface StatusPageMonitor extends Monitor {
  display_order: number
}

export interface StatsAggregates {
  total: number
  enabled: number
  disabled: number
  up: number
  down: number
  unknown: number
  active_incidents: number
  avg_uptime_24h: number | null
  avg_uptime_7d: number | null
  avg_uptime_30d: number | null
}

export interface StatsSeriesPoint {
  period: string
  total: number
  up_count: number
  uptime: number
}

export interface StatsIncident {
  monitor_id: number
  name: string
  url: string
  status: string
  status_code: number | null
  started_at: number | null
  resolved_at: number | null
}

export interface StatsAttention {
  monitor_id: number
  name: string
  url: string
  reason: string
  status: string
  status_code: number | null
  last_response_time_ms: number | null
  last_check_at: number | null
}

export interface StatsSlowMonitor {
  monitor_id: number
  name: string
  url: string
  avg_response_time_ms: number
  samples: number
}

export interface StatsNode {
  id: number
  name: string
  role: string
  active: number
  last_seen_at: number | null
  status: string
}

export interface GlobalStats {
  generated_at: number
  aggregates: StatsAggregates
  series: StatsSeriesPoint[]
  incidents: StatsIncident[]
  attention: StatsAttention[]
  slowest: StatsSlowMonitor[]
  nodes: StatsNode[]
}

export const api = {
  getHealth: () => get<Health>('/health'),

  getStats: () => get<GlobalStats>('/stats'),

  listMonitors: (opts?: { page?: number; per_page?: number; sort?: string; order?: string; q?: string; enabled?: number }) =>
    get<PaginatedResult<Monitor>>('/monitors', opts),

  getMonitor: (id: number) => get<Monitor>('/monitors/' + id),

  createMonitor: (data: Partial<Monitor>) => post<Monitor>('/monitors', data),

  updateMonitor: (id: number, data: Partial<Monitor> & { channel_ids?: number[] }) =>
    put<Monitor>('/monitors/' + id, data),

  deleteMonitor: (id: number) => del('/monitors/' + id),

  getHistory: (id: number, before?: number, limit = 50) =>
    get<Check[]>('/monitors/' + id, { view: 'history', before, limit }),

  getSummary: (id: number, days = 7, group = 'day') =>
    get<DaySummary[]>('/monitors/' + id, { view: 'summary', days, group }),

  getSettings: () => get<Settings>('/settings'),

  verifyKey: async (key: string): Promise<boolean> => {
    const res = await fetch(BASE + '/health', {
      headers: { 'Content-Type': 'application/json', 'X-SpyWeb-Key': key },
    })
    if (res.status === 401) return false
    const json = await res.json().catch(() => null)
    if (json === null) throw proxyError(res.status)
    return json?.success === true
  },

  updateSettings: (data: Settings) => put<Settings>('/settings', data),

  exportMonitors: async (format: 'json' | 'csv') => {
    const headers: Record<string, string> = {}
    if (apiKey.value) headers['X-SpyWeb-Key'] = apiKey.value
    const res = await fetch(BASE + '/monitors_export?format=' + format, { headers })
    if (!res.ok) {
      if (res.status === 401) showAuthModal.value = true
      const err = await res.json().catch(() => null)
      if (!err) throw res.status === 401 ? new Error('Unauthorized') : proxyError(res.status)
      throw new Error(err.error || 'Export failed')
    }
    const blob = await res.blob()
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = instanceName.value + '-monitors.' + format
    a.click()
    URL.revokeObjectURL(url)
  },

  importMonitors: (body: string, contentType: string) =>
    request<{ imported: number; skipped: number; failed: number; total: number }>('/monitors_import', {
      method: 'POST',
      headers: { 'Content-Type': contentType },
      body,
    }),

  listChannels: () => get<NotificationChannel[]>('/channels'),

  createChannel: (data: Partial<NotificationChannel>) => post<NotificationChannel>('/channels', data),

  updateChannel: (id: number, data: Partial<NotificationChannel>) => put<NotificationChannel>('/channels/' + id, data),

  deleteChannel: (id: number) => del('/channels/' + id),

  testChannel: (id: number, message?: string) =>
    put<{ name: string; type: string; response?: any; error?: string; }>('/channels/' + id + '/test', { message }),

  getMonitorChannels: (id: number) => get<number[]>('/monitors/' + id, { view: 'channels' }),

  listNodes: () => get<ClusterNode[]>('/nodes'),

  createNode: (data: { name: string; role?: string }) =>
    post<{ node: ClusterNode; token: string }>('/nodes', data),

  getNode: (id: number) => get<NodeDetail>('/nodes/' + id),

  getNodeReports: (id: number) => get<NodeReport[]>('/nodes/' + id, { view: 'reports' }),

  updateNode: (id: number, data: Partial<ClusterNode>) => put<ClusterNode>('/nodes/' + id, data),

  resetNodeToken: (id: number) =>
    put<{ node: ClusterNode; token: string }>('/nodes/' + id + '/reset-token'),

  deleteNode: (id: number) => del('/nodes/' + id),

  listStatusPages: () => get<StatusPage[]>('/status_pages'),

  createStatusPage: (data: Partial<StatusPage>) => post<StatusPage>('/status_pages', data),

  updateStatusPage: (id: number, data: Partial<StatusPage> & { monitors?: { monitor_id: number; display_order?: number }[] }) =>
    put<StatusPage>('/status_pages/' + id, data),

  deleteStatusPage: (id: number) => del('/status_pages/' + id),

  listStatusPageMonitors: (id: number) => get<StatusPageMonitor[]>('/status_pages/' + id, { view: 'monitors' }),
}
