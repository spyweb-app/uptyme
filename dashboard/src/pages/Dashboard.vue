<template>
  <header class="topbar">
    <div class="topbar-left">
      <h1 class="title">
        <span class="i-mdi-view-dashboard-outline text-[var(--accent)] mr-2" />
        Dashboard
      </h1>
      <span v-if="stats" class="last-updated">
        Updated {{ formatRelative(stats.generated_at) }}
      </span>
    </div>
    <div class="topbar-actions">
      <button class="btn-secondary" @click="loadStats">
        <span class="i-mdi-refresh" />
      </button>
      <RouterLink class="btn-secondary" to="/monitors">
        <span class="i-mdi-monitor-multiple-outline mr-1" />
        All Monitors
      </RouterLink>
    </div>
  </header>

  <div class="content relative">
    <LoadingOverlay v-if="loading" />
    <template v-else-if="stats">
      <section class="panel health-panel">
        <div class="panel-title">
          Monitor Health
          <span class="panel-sub">{{ stats.aggregates.enabled }} enabled · {{ stats.aggregates.disabled }} disabled</span>
        </div>
        <div class="health-bar" role="img" aria-label="Monitor health breakdown">
          <span v-if="stats.aggregates.up" class="health-segment is-up" :style="{ width: healthPercent(stats.aggregates.up) }" />
          <span v-if="stats.aggregates.down" class="health-segment is-down" :style="{ width: healthPercent(stats.aggregates.down) }" />
          <span v-if="stats.aggregates.unknown" class="health-segment is-unknown" :style="{ width: healthPercent(stats.aggregates.unknown) }" />
          <span v-if="stats.aggregates.disabled" class="health-segment is-disabled" :style="{ width: healthPercent(stats.aggregates.disabled) }" />
        </div>
        <div class="health-legend">
          <span><i class="legend-dot is-up" />Up <b>{{ stats.aggregates.up }}</b></span>
          <span><i class="legend-dot is-down" />Down <b>{{ stats.aggregates.down }}</b></span>
          <span><i class="legend-dot is-unknown" />Unknown <b>{{ stats.aggregates.unknown }}</b></span>
          <span><i class="legend-dot is-disabled" />Disabled <b>{{ stats.aggregates.disabled }}</b></span>
        </div>
      </section>

      <div class="stat-grid">
        <div class="stat-card accent">
          <span class="stat-icon-ring i-mdi-monitor-dashboard" />
          <div class="stat-value">{{ stats.aggregates.total }}</div>
          <div class="stat-label">Monitors</div>
        </div>
        <div class="stat-card" :class="stats.aggregates.active_incidents > 0 ? 'down' : 'muted'">
          <span class="stat-icon-ring i-mdi-fire-alert" />
          <div class="stat-value">{{ stats.aggregates.active_incidents }}</div>
          <div class="stat-label">Active Incidents</div>
        </div>
        <div class="stat-card" :class="uptimeCardClass(stats.aggregates.avg_uptime_24h)">
          <span class="stat-icon-ring i-mdi-clock-check" />
          <div class="stat-value">{{ fmtPct(stats.aggregates.avg_uptime_24h) }}</div>
          <div class="stat-label">Uptime (24h)</div>
        </div>
        <div class="stat-card" :class="uptimeCardClass(stats.aggregates.avg_uptime_7d)">
          <span class="stat-icon-ring i-mdi-gauge" />
          <div class="stat-value">{{ fmtPct(stats.aggregates.avg_uptime_7d) }}</div>
          <div class="stat-label">Uptime (7d)</div>
        </div>
        <div class="stat-card" :class="uptimeCardClass(stats.aggregates.avg_uptime_30d)">
          <span class="stat-icon-ring i-mdi-calendar-check" />
          <div class="stat-value">{{ fmtPct(stats.aggregates.avg_uptime_30d) }}</div>
          <div class="stat-label">Uptime (30d)</div>
        </div>
      </div>

      <div class="grid-2">
        <section class="panel">
          <div class="panel-title">
            Global Uptime (30d)
            <span class="panel-sub">daily aggregate</span>
          </div>
          <div class="chart-wrap">
            <Line :data="chartData" :options="chartOptions" />
          </div>
        </section>

        <section class="panel">
          <div class="panel-title">
            <span>Recent Incidents <span class="panel-sub">latest transitions</span></span>
            <span v-if="incidentTotalPages > 1" class="panel-pagination">
              <button class="page-btn" :disabled="incidentsPage <= 1" @click="incidentsPage--">
                <span class="i-mdi-chevron-left" />
              </button>
              <span class="page-info">{{ incidentsPage }}/{{ incidentTotalPages }}</span>
              <button class="page-btn" :disabled="incidentsPage >= incidentTotalPages" @click="incidentsPage++">
                <span class="i-mdi-chevron-right" />
              </button>
            </span>
          </div>
          <div v-if="stats.incidents.length === 0" class="panel-empty">
            No recent incidents
          </div>
          <template v-else>
            <ul class="incident-list">
              <li v-for="inc in paginatedIncidents" :key="inc.monitor_id + '-' + inc.started_at" class="incident-item">
                <span class="incident-dot" :class="inc.status === 'UP' ? 'is-up' : 'is-down'" />
                <RouterLink class="incident-name" :to="'/monitors'">{{ inc.name }}</RouterLink>
                <span class="incident-url">{{ inc.url }}</span>
                <span v-if="inc.status_code" class="incident-code">{{ inc.status_code }}</span>
                <span class="incident-status" :class="inc.status === 'UP' ? 'is-up' : 'is-down'">
                  {{ inc.status }}
                </span>
                <span class="incident-at">{{ inc.status === 'DOWN' && inc.started_at != null ? 'Down for ' + formatDuration(Date.now()/1000 - inc.started_at) : (inc.resolved_at != null ? formatRelative(inc.resolved_at) : '—') }}</span>
              </li>
            </ul>
          </template>
        </section>
      </div>

      <div class="grid-2 action-grid">
        <section class="panel">
          <div class="panel-title">
            <span>Needs Attention <span class="panel-sub">down or stale monitors</span></span>
            <span v-if="attentionTotalPages > 1" class="panel-pagination">
              <button class="page-btn" :disabled="attentionPage <= 1" @click="attentionPage--">
                <span class="i-mdi-chevron-left" />
              </button>
              <span class="page-info">{{ attentionPage }}/{{ attentionTotalPages }}</span>
              <button class="page-btn" :disabled="attentionPage >= attentionTotalPages" @click="attentionPage++">
                <span class="i-mdi-chevron-right" />
              </button>
            </span>
          </div>
          <div v-if="stats.attention.length === 0" class="panel-empty">Everything looks healthy</div>
          <template v-else>
            <ul class="attention-list">
              <li v-for="item in paginatedAttention" :key="item.monitor_id" class="attention-item">
                <span class="incident-dot" :class="item.status === 'DOWN' ? 'is-down' : 'is-unknown'" />
                <RouterLink class="incident-name" to="/monitors">{{ item.name }}</RouterLink>
                <span class="attention-reason" :class="item.status === 'DOWN' ? 'is-down' : 'is-unknown'">{{ item.reason }}</span>
                <span v-if="item.status_code" class="incident-code">{{ item.status_code }}</span>
                <span class="incident-at">{{ item.last_check_at != null ? formatRelative(item.last_check_at) : 'Never checked' }}</span>
              </li>
            </ul>
          </template>
        </section>

        <section class="panel">
          <div class="panel-title">
            Slowest Monitors
            <span class="panel-sub">average response, last 24h</span>
          </div>
          <div v-if="stats.slowest.length === 0" class="panel-empty">No response data yet</div>
          <ul v-else class="slow-list">
            <li v-for="item in stats.slowest" :key="item.monitor_id" class="slow-item">
              <RouterLink class="incident-name" to="/monitors">{{ item.name }}</RouterLink>
              <span class="incident-url">{{ item.url }}</span>
              <span class="slow-value"><ResponseTime :ms="item.avg_response_time_ms" /></span>
              <span class="slow-samples">{{ item.samples }} checks</span>
            </li>
          </ul>
        </section>
      </div>

      <section v-if="nodeRole === 'central' && stats.nodes.length" class="panel node-health-panel">
        <div class="panel-title">
          Checker Health
          <span class="panel-sub">last contact</span>
        </div>
        <ul class="node-health-list">
          <li v-for="node in stats.nodes" :key="node.id" class="node-health-item">
            <span class="node-status-dot" :class="node.status" />
            <span class="incident-name">{{ node.name }}</span>
            <span class="node-role">{{ node.role }}</span>
            <span class="node-status" :class="node.status">{{ node.status }}</span>
            <span class="incident-at">{{ node.last_seen_at != null ? formatRelative(node.last_seen_at) : 'Never' }}</span>
          </li>
        </ul>
      </section>
    </template>
    <div v-else class="panel-empty pad-lg">
      Failed to load dashboard stats.
    </div>
  </div>
</template>

<script setup lang="ts">
defineOptions({ layout: 'default' })

import { ref, computed, onMounted } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  LineElement,
  PointElement,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js'
import 'chart.js/auto'
import { api, type GlobalStats } from '~lib/api'
import LoadingOverlay from '~com/LoadingOverlay.vue'
import ResponseTime from '~com/ResponseTime.vue'
import { formatISODate, formatRelative } from '~lib/dates'
import { nodeRole } from '~stores/app'

ChartJS.register(CategoryScale, LinearScale, LineElement, PointElement, Tooltip, Legend, Filler)

// state
const loading = ref(false)
const stats = ref<GlobalStats | null>(null)

const PAGE_SIZE = 5
const incidentsPage = ref(1)
const attentionPage = ref(1)

// computed
const incidentTotalPages = computed(() => Math.max(1, Math.ceil((stats.value?.incidents.length ?? 0) / PAGE_SIZE)))

const attentionTotalPages = computed(() => Math.max(1, Math.ceil((stats.value?.attention.length ?? 0) / PAGE_SIZE)))

const paginatedIncidents = computed(() => {
  const all = stats.value?.incidents ?? []
  const start = (incidentsPage.value - 1) * PAGE_SIZE
  return all.slice(start, start + PAGE_SIZE)
})

const paginatedAttention = computed(() => {
  const all = stats.value?.attention ?? []
  const start = (attentionPage.value - 1) * PAGE_SIZE
  return all.slice(start, start + PAGE_SIZE)
})

const chartData = computed(() => ({
  labels: (stats.value?.series ?? []).map((s) => formatISODate(s.period)),
  datasets: [
    {
      label: 'Uptime %',
      data: (stats.value?.series ?? []).map((s) => s.uptime),
      fill: true,
      borderColor: '#22c55e',
      backgroundColor: (ctx: any) => {
        const chart = ctx.chart
        const { ctx: canvasCtx, chartArea } = chart
        if (!chartArea) return 'rgba(34, 197, 94, 0.1)'
        const gradient = canvasCtx.createLinearGradient(0, chartArea.top, 0, chartArea.bottom)
        gradient.addColorStop(0, 'rgba(34, 197, 94, 0.15)')
        gradient.addColorStop(1, 'rgba(34, 197, 94, 0)')
        return gradient
      },
      tension: 0.2,
      pointRadius: 3,
      pointHoverRadius: 5,
    },
  ],
}))

const chartOptions = computed(() => {
  const uptimes = (stats.value?.series ?? []).map((s) => s.uptime)
  const minUptime = uptimes.length > 0 ? Math.min(...uptimes) : undefined
  return {
    responsive: true,
    maintainAspectRatio: false,
    scales: {
      y: {
        suggestedMin: minUptime !== undefined ? Math.max(0, Math.floor(minUptime) - 3) : 0,
        suggestedMax: 100,
        grid: { color: 'rgba(100, 116, 139, 0.08)' },
        ticks: { callback: (v: any) => v + '%' },
      },
      x: {
        grid: { display: false },
      },
    },
    plugins: {
      legend: { display: false },
      tooltip: {
        callbacks: {
          title: (items: any[]) => items[0]?.label ?? '',
          label: (context: any) => {
            const point = stats.value?.series[context.dataIndex]
            if (!point) return `Uptime: ${context.parsed.y}%`
            return [
              `Uptime: ${point.uptime}%`,
              `Checks: ${point.up_count}/${point.total} up`,
            ]
          },
        },
      },
    },
  }
})

// helpers
function uptimeCardClass(val: number | null): string {
  if (val == null) return 'muted'
  if (val >= 99) return 'up'
  if (val >= 95) return 'warning'
  return 'down'
}

function fmtPct(v: number | null): string {
  return v == null ? '—' : v.toFixed(1) + '%'
}

function healthPercent(value: number): string {
  const total = stats.value?.aggregates.total ?? 0
  return total > 0 ? `${(value / total) * 100}%` : '0%'
}

function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`
  return `${Math.floor(seconds / 86400)}d`
}

// lifecycle
async function loadStats() {
  loading.value = true
  try {
    stats.value = await api.getStats()
    incidentsPage.value = 1
    attentionPage.value = 1
  } catch {
    stats.value = null
  } finally {
    loading.value = false
  }
}

onMounted(loadStats)
</script>

<style scoped>
.topbar-left {
  @apply flex flex-col gap-0.5;
}

.last-updated {
  @apply text-[12px] text-[var(--text-muted)];
}

.topbar-actions {
  @apply flex items-center gap-3;
}

.content {
  padding: 24px;
  overflow: auto;
}

.stat-grid {
  @apply grid gap-4 mb-6;
  grid-template-columns: repeat(auto-fit, minmax(145px, 1fr));
}

.stat-card {
  --card-color: var(--text-muted);
  @apply flex flex-col items-center gap-1.5 p-5 rounded-xl border border-[var(--border)] transition-all duration-200;
  background: color-mix(in srgb, var(--card-color) 4%, var(--surface));
}

.stat-card:hover {
  @apply -translate-y-0.5 shadow-lg;
  border-color: var(--border-active);
}

.stat-card.accent { --card-color: var(--accent); }
.stat-card.up     { --card-color: var(--up); }
.stat-card.down   { --card-color: var(--down); }
.stat-card.warning { --card-color: var(--blocked); }
.stat-card.muted  { --card-color: var(--text-muted); }

.stat-icon-ring {
  @apply w-11 h-11 rounded-full flex items-center justify-center text-[20px];
  background: color-mix(in srgb, var(--card-color) 45%, transparent);
  color: var(--card-color);
}

.stat-value {
  @apply text-[26px] font-semibold tabular-nums;
  color: var(--card-color);
}

.stat-label {
  @apply text-[11px] uppercase tracking-[0.5px] text-[var(--text-muted)];
}

.grid-2 {
  @apply grid gap-4;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
}

.panel {
  @apply rounded-xl border border-[var(--border)] bg-[var(--surface)] p-5;
}

.panel-title {
  @apply text-[15px] font-semibold mb-1 flex items-center justify-between;
}

.panel-sub {
  @apply text-[12px] font-normal text-[var(--text-muted)];
}

.panel-empty {
  @apply text-[13px] text-[var(--text-muted)] py-8 text-center;
}

.panel-empty.pad-lg {
  @apply py-[30vh];
}

.chart-wrap {
  position: relative;
  height: 260px;
}

.health-panel {
  @apply mb-4;
}

.health-bar {
  @apply flex w-full h-3 rounded-full overflow-hidden bg-[var(--input)] mt-4;
}

.health-segment {
  min-width: 2px;
}

.health-segment.is-up, .legend-dot.is-up { background: var(--up); }
.health-segment.is-down, .legend-dot.is-down { background: var(--down); }
.health-segment.is-unknown, .legend-dot.is-unknown { background: var(--blocked); }
.health-segment.is-disabled, .legend-dot.is-disabled { background: var(--text-muted); }

.health-legend {
  @apply flex flex-wrap gap-x-5 gap-y-2 mt-3 text-[12px] text-[var(--text-muted)];
}

.health-legend span {
  @apply inline-flex items-center gap-1.5;
}

.health-legend b {
  @apply font-medium text-[var(--text)];
}

.legend-dot {
  @apply w-2 h-2 rounded-full;
}

.incident-list {
  @apply flex flex-col divide-y divide-[var(--border)] mt-2;
}

.incident-item {
  @apply flex items-center gap-3 py-2.5 text-[13px];
}

.incident-dot {
  @apply w-2 h-2 rounded-full shrink-0;
}

.incident-dot.is-up { background: var(--up); }
.incident-dot.is-down { background: var(--down); }

.incident-status {
  @apply text-xs font-medium shrink-0;
}

.incident-status.is-up { color: var(--up); }
.incident-status.is-down { color: var(--down); }

.incident-code {
  @apply text-[11px] font-mono font-medium px-1.5 py-0.5 rounded;
  background: color-mix(in srgb, var(--down) 10%, transparent);
  color: var(--down);
}

.incident-name {
  @apply font-medium cursor-pointer hover:underline;
}

.incident-url {
  @apply text-[var(--text-muted)] truncate max-w-[180px];
}

.incident-at {
  @apply text-[12px] text-[var(--text-muted)] whitespace-nowrap ml-auto;
}

.action-grid {
  @apply mt-4;
}

.panel-pagination {
  @apply flex items-center gap-1.5;
}

.page-btn {
  @apply w-7 h-7 flex items-center justify-center border border-[var(--border)] bg-[var(--input)] text-[var(--text)] rounded-lg cursor-pointer transition-all duration-150;

  &:hover:not(:disabled) {
    @apply border-[var(--border-hover)] bg-[var(--hover)];
  }

  &:disabled {
    @apply opacity-40 cursor-default;
  }
}

.page-info {
  @apply text-[12px] text-[var(--text-muted)] tabular-nums;
}

.attention-list, .slow-list, .node-health-list {
  @apply flex flex-col divide-y divide-[var(--border)] mt-2;
}

.attention-item, .slow-item, .node-health-item {
  @apply flex items-center gap-3 py-2.5 text-[13px] min-w-0;
}

.attention-reason, .node-status {
  @apply text-[11px] font-medium uppercase shrink-0;
}

.attention-reason.is-down, .node-status.stale, .node-status.inactive { color: var(--down); }
.attention-reason.is-unknown { color: var(--blocked); }
.node-status.online { color: var(--up); }

.slow-value {
  @apply font-medium tabular-nums ml-auto whitespace-nowrap;
  color: var(--accent);
}

.slow-samples, .node-role {
  @apply text-[11px] text-[var(--text-muted)] whitespace-nowrap;
}

.node-health-panel {
  @apply mt-4;
}

.node-status-dot {
  @apply w-2 h-2 rounded-full shrink-0;
}

.node-status-dot.online { background: var(--up); }
.node-status-dot.stale, .node-status-dot.inactive { background: var(--down); }
</style>
