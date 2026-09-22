<template>
  <div class="slide-over-backdrop" @click.self="$emit('close')">
    <div class="slide-panel">
      <div class="panel-header">
        <div class="panel-header-left">
          <StatusBadge :isUp="monitor.enabled === 0 ? undefined : monitor.is_up" :statusCode="monitor.enabled === 0 ? undefined : monitor.last_status_code" />
          <div>
            <h2 class="panel-title">{{ monitor.name }}</h2>
            <span class="panel-url">{{ monitor.url }}</span>
          </div>
        </div>
        <div class="panel-header-right">
          <button class="btn-ghost" title="Refresh" @click="refreshDetail"><span class="i-mdi-refresh" /></button>
          <button v-if="nodeRole !== 'checker'" class="btn-ghost" @click="editMonitor">Edit</button>
          <button v-if="nodeRole !== 'checker'" class="btn-danger" @click="confirmDelete = true">Delete</button>
          <button class="close-btn" @click="$emit('close')">&times;</button>
        </div>
      </div>

      <div class="panel-body">
        <div class="stats-row">
          <div class="stat-box">
            <span class="stat-box-value"><ResponseTime :ms="monitor.last_response_time_ms" /></span>
            <span class="stat-box-label">Response Time</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value" :class="uptimeColor(monitor.uptime_24h)">{{ monitor.uptime_24h ?? '-' }}%</span>
            <span class="stat-box-label">24h Uptime</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value" :class="uptimeColor(monitor.uptime_7d)">{{ monitor.uptime_7d ?? '-' }}%</span>
            <span class="stat-box-label">7d Uptime</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value" :class="uptimeColor(monitor.uptime_30d)">{{ monitor.uptime_30d ?? '-' }}%</span>
            <span class="stat-box-label">30d Uptime</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value">{{ formatInterval(monitor.interval_sec) }}</span>
            <span class="stat-box-label">Check Interval</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value">{{ monitor.last_status_code ?? '-' }}</span>
            <span class="stat-box-label">Last Status</span>
          </div>
          <div v-if="monitor.check_cert === 1 && monitor.cert_not_after" class="stat-box">
            <span class="stat-box-value" :class="certColor(monitor.cert_days_left)">{{ monitor.cert_days_left }}d</span>
            <span class="stat-box-label">Cert Expires</span>
          </div>
        </div>

        <div v-if="monitor.check_cert === 1 && monitor.cert_not_after" class="cert-info">
          <div class="cert-field">
            <span class="cert-label">Not After</span>
            <span class="cert-value">{{ formatISODate(monitor.cert_not_after) }}</span>
          </div>
          <div class="cert-field">
            <span class="cert-label">Threshold</span>
            <span class="cert-value">{{ monitor.cert_threshold_days > 0 ? monitor.cert_threshold_days + ' days' : 'Instance default' }}</span>
          </div>
        </div>

        <div class="charts-section">
          <UptimeTimeline :monitorId="monitor.id" ref="timelineRef" />
        </div>

        <div class="charts-section">
          <ResponseTimeChart :monitorId="monitor.id" />
        </div>

        <div class="history-section">
          <h3 class="section-title">Recent Checks</h3>
          <table class="detail-table" v-if="monHistory.length > 0">
            <thead>
              <tr>
                <th>Time</th>
                <th>Status</th>
                <th>Code</th>
                <th>Response</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="h in monHistory" :key="h.id">
                <td>{{ formatDateTime(h.checked_at) }}</td>
                <td>
                  <span :class="checkStatusClass(h)">
                    {{ checkStatusLabel(h) }}
                  </span>
                </td>
                <td>{{ h.status_code }}</td>
                <td><ResponseTime :ms="h.response_time_ms" /></td>
                <td class="error-cell">{{ h.error_message || '-' }}</td>
              </tr>
            </tbody>
          </table>
          <div v-else class="no-data">No checks recorded yet</div>
          <button
            v-if="hasMore"
            class="load-more"
            @click="loadMore"
          >
            Load more
          </button>
        </div>
      </div>

      <ConfirmDialog
        v-if="confirmDelete"
        title="Delete Monitor"
        message="Are you sure? This will delete all check history."
        @confirm="doDelete"
        @cancel="confirmDelete = false"
      />
    </div>

    <MonitorForm
      v-if="showEditForm"
      :monitor="monitor"
      @close="showEditForm = false"
      @saved="onEdited"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { api, type Check } from '~lib/api'
import { nodeRole } from '~stores/app'
import { useMonitorStore } from '~stores/monitors'
import { showNotification } from '~stores/app'
import { formatDateTime, formatISODate } from '~lib/dates'
import StatusBadge from './StatusBadge.vue'
import UptimeTimeline from './UptimeTimeline.vue'
import ResponseTimeChart from './ResponseTimeChart.vue'
import MonitorForm from './MonitorForm.vue'
import ConfirmDialog from './ConfirmDialog.vue'
import ResponseTime from './ResponseTime.vue'

// state
const emit = defineEmits<{
  close: []
}>()

const store = useMonitorStore()

const hasMore = ref(true)
const confirmDelete = ref(false)
const showEditForm = ref(false)
const timelineRef = ref<InstanceType<typeof UptimeTimeline> | null>(null)

// computed
const monitor = computed(() => store.monitors.find(m => m.id === store.selectedMonitorId)!)

const monHistory = computed(() => store.historyMap[store.selectedMonitorId!] || [])

// guards
function isBlocked(code: number | null) {
  return code !== null && code >= 400 && code < 500
}

// helpers
function uptimeColor(val: number | null) {
  if (val === null) return ''
  if (val >= 99) return 'text-green-400'
  if (val >= 95) return 'text-yellow-400'
  return 'text-red-400'
}

function formatInterval(sec: number) {
  if (sec >= 3600) return Math.round(sec / 3600) + 'h'
  if (sec >= 60) return Math.round(sec / 60) + 'm'
  return sec + 's'
}

function checkStatusClass(h: Check) {
  if (isBlocked(h.status_code)) return 'text-amber-400'
  return h.is_up ? 'text-green-400' : 'text-red-400'
}

function checkStatusLabel(h: Check) {
  if (isBlocked(h.status_code) && h.is_up) return 'BLOCKED'
  return h.is_up ? 'UP' : 'DOWN'
}

function certColor(daysLeft: number | null) {
  if (daysLeft === null) return ''
  if (daysLeft > 30) return 'text-green-400'
  if (daysLeft > 14) return 'text-yellow-400'
  return 'text-red-400'
}

// lifecycle
async function loadMore() {
  const last = monHistory.value[monHistory.value.length - 1]
  if (!last) return
  const data = await api.getHistory(store.selectedMonitorId!, last.checked_at)
  store.appendHistory(store.selectedMonitorId!, data)
  hasMore.value = data.length === 50
}

async function doDelete() {
  try {
    await store.remove(store.selectedMonitorId!)
    showNotification('Monitor deleted', 'success')
    confirmDelete.value = false
    store.selectedMonitorId = null
    emit('close')
  } catch (e: any) {
    showNotification(e.message, 'error')
  }
}

function editMonitor() {
  showEditForm.value = true
}

function onEdited() {
  showEditForm.value = false
  showNotification('Monitor updated', 'success')
}

async function refreshDetail() {
  await store.fetchHistory(store.selectedMonitorId!, 100)
  hasMore.value = (store.historyMap[store.selectedMonitorId!]?.length ?? 0) === 100
  timelineRef.value?.refresh()
}

onMounted(async () => {
  await refreshDetail()
})
</script>

<style scoped>
.panel-url {
  @apply text-xs text-[var(--text-muted)] break-all;
}

.stats-row {
  @apply grid grid-cols-3 gap-[10px] mb-6;
}

.cert-info {
  @apply flex gap-4 mb-6 p-3 bg-[var(--elevated)] border border-[var(--border)] rounded-lg;
}

.cert-field {
  @apply flex flex-col gap-1;
}

.cert-label {
  @apply text-[11px] text-[var(--text-muted)] uppercase tracking-[0.5px];
}

.cert-value {
  @apply text-sm font-medium;
}

.charts-section {
  @apply mb-6 bg-[var(--elevated)] border border-[var(--border)] rounded-xl p-4;
}

.load-more {
  @apply block mx-auto mt-3 px-5 py-2 bg-transparent border border-[var(--border-active)] text-[var(--text-secondary)] rounded-lg cursor-pointer text-[13px] transition-all duration-150;

  &:hover { @apply border-[var(--accent)] text-[var(--text)]; }
}
</style>
