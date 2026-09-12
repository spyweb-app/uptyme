<template>
  <div>
    <div class="chart-header">
      <div class="metric-toggle">
        <button
          class="toggle-btn"
          :class="{ active: metric === 'response' }"
          @click="metric = 'response'"
        >Response Time</button>
        <button
          class="toggle-btn"
          :class="{ active: metric === 'uptime' }"
          @click="metric = 'uptime'"
        >Uptime</button>
      </div>
      <div class="range-tabs">
        <button
          v-for="d in days"
          :key="d"
          class="tab-btn"
          :class="{ active: selectedDays === d }"
          @click="selectDays(d)"
        >
          {{ d }}D
        </button>
      </div>
    </div>
    <div class="chart-wrap">
      <Line v-if="hasData" :data="chartData" :options="chartOptions" />
    </div>
    <div v-if="!hasData" class="no-data">No data for this period</div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Filler,
} from 'chart.js'
import { api, type DaySummary } from '~lib/api'
import { getPublicReport } from '~lib/publicApi'

ChartJS.register(LineElement, PointElement, LinearScale, CategoryScale, Tooltip, Filler)

// state
const props = defineProps<{
  monitorId: number
  pageSlug?: string
  initialData?: DaySummary[]
}>()

const days = [1, 7, 14, 30]
const selectedDays = ref(30)
const metric = ref<'response' | 'uptime'>('response')
const rawData = ref<DaySummary[]>([])

// computed
const slots = computed(() => {
  const now = new Date()
  const unit = getGroupUnit(selectedDays.value)
  const items: Slot[] = []

  function utcDateKey(d: Date): string {
    const y = d.getUTCFullYear()
    const m = String(d.getUTCMonth() + 1).padStart(2, '0')
    const day = String(d.getUTCDate()).padStart(2, '0')
    return `${y}-${m}-${day}`
  }

  function calcSlot(s: DaySummary): Slot {
    return {
      x: s.period,
      uptime: s.total > 0 ? Math.round((s.up_count / s.total) * 100) : null,
      response: s.avg_response_ms != null ? Math.round(s.avg_response_ms) : null,
    }
  }

  if (unit === 'hour') {
    for (let i = 23; i >= 0; i--) {
      const d = new Date(now)
      d.setUTCHours(d.getUTCHours() - i, 0, 0, 0)
      const key = d.toISOString().slice(0, 13) + ':00:00'
      const match = rawData.value.find(r => r.period === key)
      items.push(match ? calcSlot(match) : { x: key, uptime: null, response: null })
    }
  } else if (unit === 'halfday') {
    for (let i = 13; i >= 0; i--) {
      const day = new Date(now)
      day.setUTCDate(day.getUTCDate() - i)
      const dayStr = day.toISOString().slice(0, 10)
      const amKey = dayStr + 'T00:00:00'
      const amMatch = rawData.value.find(r => r.period === amKey)
      items.push(amMatch ? calcSlot(amMatch) : { x: amKey, uptime: null, response: null })
      const pmKey = dayStr + 'T12:00:00'
      const pmMatch = rawData.value.find(r => r.period === pmKey)
      items.push(pmMatch ? calcSlot(pmMatch) : { x: pmKey, uptime: null, response: null })
    }
  } else {
    for (let i = 29; i >= 0; i--) {
      const d = new Date(now)
      d.setUTCDate(d.getUTCDate() - i)
      const key = utcDateKey(d)
      const match = rawData.value.find(r => r.period === key)
      items.push(match ? calcSlot(match) : { x: key, uptime: null, response: null })
    }
  }

  return items
})

const hasData = computed(() => slots.value.some(s =>
  metric.value === 'uptime' ? s.uptime !== null : s.response !== null
))

const chartData = computed(() => {
  const items = slots.value
  const isResponse = metric.value === 'response'
  const lineColor = isResponse ? '#e11d48' : '#22c55e'

  return {
    labels: items.map(s => formatLabel(s.x)),
    datasets: [{
      label: isResponse ? 'Response Time' : 'Uptime',
      data: items.map(s => isResponse ? s.response : s.uptime),
      borderColor: lineColor,
      backgroundColor: (ctx: any) => {
        if (!ctx.chart.chartArea) return isResponse ? 'rgba(225,29,72,0.1)' : 'rgba(34,197,94,0.1)'
        const grad = ctx.chart.ctx.createLinearGradient(
          0, ctx.chart.chartArea.top,
          0, ctx.chart.chartArea.bottom
        )
        if (isResponse) {
          grad.addColorStop(0, 'rgba(225,29,72,0.3)')
          grad.addColorStop(0.6, 'rgba(225,29,72,0.06)')
          grad.addColorStop(1, 'rgba(225,29,72,0)')
        } else {
          grad.addColorStop(0, 'rgba(34,197,94,0.3)')
          grad.addColorStop(0.6, 'rgba(34,197,94,0.06)')
          grad.addColorStop(1, 'rgba(34,197,94,0)')
        }
        return grad
      },
      borderWidth: 2,
      pointRadius: 0,
      pointHitRadius: 8,
      hoverRadius: 4,
      tension: 0.3,
      fill: true,
    }],
  }
})

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    tooltip: {
      callbacks: {
        title: (ctx: any) => ctx[0].label,
        label: (ctx: any) => {
          const idx = ctx.dataIndex
          const slot = slots.value[idx]
          const lines: string[] = []
          if (slot.uptime != null) lines.push('Uptime: ' + slot.uptime + '%')
          else lines.push('Uptime: N/A')
          if (slot.response != null) lines.push('Response: ' + slot.response + 'ms')
          else lines.push('Response: N/A')
          return lines
        },
      },
    },
    legend: { display: false },
  },
  scales: {
    x: {
      type: 'category' as const,
      grid: { display: false },
      ticks: {
        color: '#64748b',
        font: { size: 11 },
        maxRotation: 45,
      },
      border: { display: false },
    },
    y: {
      min: metric.value === 'uptime' ? 90 : undefined,
      max: metric.value === 'uptime' ? 100 : undefined,
      grid: { display: false },
      ticks: {
        color: '#64748b',
        font: { size: 11 },
        callback: (v: any) => metric.value === 'uptime' ? v + '%' : v + 'ms',
      },
      border: { display: false },
    },
  },
}))

// helpers
interface Slot {
  x: string
  uptime: number | null
  response: number | null
}

function getGroupUnit(d: number): string {
  if (d === 1) return 'hour'
  if (d <= 14) return 'halfday'
  return 'day'
}

function formatLabel(period: string): string {
  const unit = getGroupUnit(selectedDays.value)
  if (unit === 'hour') {
    return period.slice(11, 16)
  }
  if (unit === 'halfday') {
    const isPM = period.slice(11, 19) === '12:00:00'
    const d = new Date(period.slice(0, 10) + 'T00:00:00Z')
    const date = d.toLocaleString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
    return date + ' ' + (isPM ? 'PM' : 'AM')
  }
  const d = new Date(period + 'T00:00:00Z')
  return d.toLocaleString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
}

// lifecycle
async function selectDays(d: number) {
  selectedDays.value = d
  if (props.pageSlug) {
    const data = await getPublicReport(props.pageSlug, {
      days: d,
      group: getGroupUnit(d),
      monitorId: props.monitorId,
    })
    rawData.value = data.summary
  } else {
    rawData.value = await api.getSummary(props.monitorId, d, getGroupUnit(d))
  }
}

onMounted(() => {
  if (props.initialData) {
    rawData.value = props.initialData
    const sample = props.initialData[0]?.period ?? ''
    if (sample.includes('T12:') || sample.includes('T00:')) selectedDays.value = 14
    else if (sample.length >= 13 && sample.includes('T')) selectedDays.value = 1
    else selectedDays.value = 30
  } else {
    selectDays(selectedDays.value)
  }
})
</script>

<style scoped>
.chart-header {
  @apply flex items-center justify-between mb-2;
}

.metric-toggle {
  @apply flex gap-1;
}

.toggle-btn {
  @apply px-[10px] py-[3px] text-xs border border-[var(--border-active)] bg-transparent text-[var(--text-secondary)] rounded-md cursor-pointer transition-all duration-150;

  &:hover { @apply border-[var(--accent)] text-[var(--text)]; }
  &.active { @apply bg-[var(--accent)] text-white border-[var(--accent)]; }
}

.range-tabs {
  @apply flex gap-1;
}

.tab-btn {
  @apply px-[10px] py-[3px] text-xs border border-[var(--border-active)] bg-transparent text-[var(--text-secondary)] rounded-md cursor-pointer transition-all duration-150;

  &:hover { @apply border-[var(--accent)] text-[var(--text)]; }
  &.active { @apply bg-[var(--accent)] text-white border-[var(--accent)]; }
}

.chart-wrap {
  width: 100%;
  height: 160px;
}

.no-data {
  @apply text-center text-[var(--text-muted)] text-[13px] p-5;
}
</style>
