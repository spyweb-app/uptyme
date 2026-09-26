import { apiKey, showAuthModal } from '~stores/auth'
import { instanceName } from '~stores/app'

const BASE = '/api/v'

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

  const json = await res.json()
  if (!json.success) throw new Error(json.error || 'Request failed')

  let data = json.data
  if (data?.items && !Array.isArray(data.items)) data.items = []
  return data as T
}

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
  getHealth: () => request<Health>('/health'),

  getStats: () => request<GlobalStats>('/stats'),

  listMonitors: (opts?: { page?: number; per_page?: number; sort?: string; order?: string; q?: string; enabled?: number }) => {
    const params = new URLSearchParams()
    if (opts) {
      if (opts.page) params.set('page', String(opts.page))
      if (opts.per_page) params.set('per_page', String(opts.per_page))
      if (opts.sort) params.set('sort', opts.sort)
      if (opts.order) params.set('order', opts.order)
      if (opts.q) params.set('q', opts.q)
      if (opts.enabled !== undefined) params.set('enabled', String(opts.enabled))
    }
    const qs = params.toString()
    return request<PaginatedResult<Monitor>>('/monitors' + (qs ? '?' + qs : ''))
  },

  getMonitor: (id: number) => request<Monitor>('/monitors/' + id),

  createMonitor: (data: Partial<Monitor>) =>
    request<Monitor>('/monitors', { method: 'POST', body: JSON.stringify(data) }),

  updateMonitor: (id: number, data: Partial<Monitor>) =>
    request<Monitor>('/monitors/' + id, { method: 'PUT', body: JSON.stringify(data) }),

  deleteMonitor: (id: number) =>
    request<{ deleted: boolean }>('/monitors/' + id, { method: 'DELETE' }),

  getHistory: (id: number, before?: number, limit = 50) => {
    const params = new URLSearchParams()
    if (before) params.set('before', String(before))
    params.set('limit', String(limit))
    return request<Check[]>('/monitors/' + id + '/history?' + params.toString())
  },

  getSummary: (id: number, days = 7, group = 'day') =>
    request<DaySummary[]>('/monitors/' + id + '/summary?days=' + days + '&group=' + group),

  getSettings: () => request<Settings>('/settings'),

  updateSettings: (data: Settings) =>
    request<Settings>('/settings', { method: 'PUT', body: JSON.stringify(data) }),

  exportMonitors: async (format: 'json' | 'csv') => {
    const headers: Record<string, string> = {}
    if (apiKey.value) headers['X-SpyWeb-Key'] = apiKey.value
    const res = await fetch(BASE + '/monitors_export?format=' + format, { headers })
    if (!res.ok) {
      if (res.status === 401) showAuthModal.value = true
      const err = await res.json().catch(() => ({}))
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

  listChannels: () => request<NotificationChannel[]>('/channels'),

  createChannel: (data: Partial<NotificationChannel>) =>
    request<NotificationChannel>('/channels', { method: 'POST', body: JSON.stringify(data) }),

  updateChannel: (id: number, data: Partial<NotificationChannel>) =>
    request<NotificationChannel>('/channels/' + id, { method: 'PUT', body: JSON.stringify(data) }),

  deleteChannel: (id: number) =>
    request<{ deleted: boolean }>('/channels/' + id, { method: 'DELETE' }),

  testChannel: (id: number, message?: string) =>
    request<{ name: string; type: string; response?: any; error?: string; }>('/channels/' + id + '/test', { method: 'PUT', body: JSON.stringify({ message }) }),

  getMonitorChannels: (id: number) =>
    request<number[]>('/monitors/' + id + '/channels'),

  setMonitorChannels: (id: number, channelIds: number[]) =>
    request<{ success: boolean }>('/monitors/' + id + '/channels', { method: 'PUT', body: JSON.stringify(channelIds) }),

  listNodes: () => request<ClusterNode[]>('/nodes'),

  createNode: (data: { name: string; role?: string }) =>
    request<{ node: ClusterNode; token: string }>('/nodes', { method: 'POST', body: JSON.stringify(data) }),

  getNode: (id: number) => request<NodeDetail>('/nodes/' + id),

  getNodeReports: (id: number) => request<NodeReport[]>('/nodes/' + id + '/reports'),

  updateNode: (id: number, data: Partial<ClusterNode>) =>
    request<ClusterNode>('/nodes/' + id, { method: 'PUT', body: JSON.stringify(data) }),

  activateNode: (id: number) =>
    request<ClusterNode>('/nodes/' + id + '/activate', { method: 'PUT' }),

  deactivateNode: (id: number) =>
    request<ClusterNode>('/nodes/' + id + '/deactivate', { method: 'PUT' }),

  resetNodeToken: (id: number) =>
    request<{ node: ClusterNode; token: string }>('/nodes/' + id + '/reset-token', { method: 'PUT' }),

  deleteNode: (id: number) =>
    request<{ deleted: boolean }>('/nodes/' + id, { method: 'DELETE' }),

  listStatusPages: () => request<StatusPage[]>('/status_pages'),

  createStatusPage: (data: Partial<StatusPage>) =>
    request<StatusPage>('/status_pages', { method: 'POST', body: JSON.stringify(data) }),

  updateStatusPage: (id: number, data: Partial<StatusPage>) =>
    request<StatusPage>('/status_pages/' + id, { method: 'PUT', body: JSON.stringify(data) }),

  deleteStatusPage: (id: number) =>
    request<{ deleted: boolean }>('/status_pages/' + id, { method: 'DELETE' }),

  listStatusPageMonitors: (id: number) =>
    request<StatusPageMonitor[]>('/status_pages/' + id + '/monitors'),

  addStatusPageMonitor: (id: number, monitor_id: number, display_order = 0) =>
    request<{ status_page_id: number; monitor_id: number; display_order: number }>('/status_pages/' + id + '/monitors', {
      method: 'POST', body: JSON.stringify({ monitor_id, display_order }),
    }),

  updateStatusPageMonitorOrder: (id: number, monitor_id: number, display_order: number) =>
    request<{ status_page_id: number; monitor_id: number; display_order: number }>('/status_pages/' + id + '/monitors/' + monitor_id, {
      method: 'PUT', body: JSON.stringify({ display_order }),
    }),

  removeStatusPageMonitor: (id: number, monitor_id: number) =>
    request<{ deleted: boolean }>('/status_pages/' + id + '/monitors/' + monitor_id, { method: 'DELETE' }),
}
