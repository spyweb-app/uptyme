<template>
  <div>
    <div class="timeline-header">
      <span class="timeline-title">Uptime Timeline</span>
      <div class="timeline-tabs">
        <button
          v-for="d in days"
          :key="d"
          class="tab-btn"
          :class="{ active: selectedDays === d }"
          @click="selectDays(d)"
        >
          {{ d }}d
        </button>
      </div>
    </div>
    <div class="chart-wrap">
      <Bar v-if="hasData" :data="chartData" :options="chartOptions" />
    </div>
    <div v-if="!hasData" class="no-data">No data for this period</div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { Bar } from 'vue-chartjs'
import {
  Chart as ChartJS,
  BarElement,
  LinearScale,
  CategoryScale,
  Tooltip,
} from 'chart.js'
import { api, type DaySummary } from '~lib/api'

ChartJS.register(BarElement, LinearScale, CategoryScale, Tooltip)

const props = defineProps<{
  monitorId: number
}>()

const days = [1, 14, 30]
const selectedDays = ref(14)
const rawData = ref<DaySummary[]>([])

onMounted(() => selectDays(selectedDays.value))

type Slot = { x: string; y: number | null }

function getGroupUnit(d: number): string {
  if (d === 1) return 'hour'
  if (d === 14) return 'halfday'
  return 'day'
}

async function selectDays(d: number) {
  selectedDays.value = d
  rawData.value = await api.getSummary(props.monitorId, d, getGroupUnit(d))
}

function refresh() {
  return selectDays(selectedDays.value)
}

defineExpose({ refresh })

function generateSlots(): Slot[] {
  const now = new Date()
  const unit = getGroupUnit(selectedDays.value)
  const slots: Slot[] = []

  if (unit === 'hour') {
    for (let i = 23; i >= 0; i--) {
      const d = new Date(now)
      d.setUTCHours(d.getUTCHours() - i, 0, 0, 0)
      const key = d.toISOString().slice(0, 13) + ':00:00'
      const match = rawData.value.find(r => r.period === key)
      slots.push({
        x: key,
        y: match && match.total > 0 ? Math.round((match.up_count / match.total) * 100) : null,
      })
    }
  } else if (unit === 'halfday') {
      for (let i = 13; i >= 0; i--) {
      const day = new Date(now)
      day.setUTCDate(day.getUTCDate() - i)
      const dayStr = day.toISOString().slice(0, 10)
      const amKey = dayStr + 'T00:00:00'
      const amMatch = rawData.value.find(r => r.period === amKey)
      slots.push({
        x: amKey,
        y: amMatch && amMatch.total > 0 ? Math.round((amMatch.up_count / amMatch.total) * 100) : null,
      })
      const pmKey = dayStr + 'T12:00:00'
      const pmMatch = rawData.value.find(r => r.period === pmKey)
      slots.push({
        x: pmKey,
        y: pmMatch && pmMatch.total > 0 ? Math.round((pmMatch.up_count / pmMatch.total) * 100) : null,
      })
    }
  } else {
    for (let i = 29; i >= 0; i--) {
      const d = new Date(now)
      d.setUTCDate(d.getUTCDate() - i)
      const key = d.toISOString().slice(0, 10)
      const match = rawData.value.find(r => r.period === key)
      slots.push({
        x: key,
        y: match && match.total > 0 ? Math.round((match.up_count / match.total) * 100) : null,
      })
    }
  }

  return slots
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

const slots = computed(() => generateSlots())

const hasData = computed(() => slots.value.some(s => s.y !== null))

const chartData = computed(() => {
  const items = slots.value
  return {
    labels: items.map(s => formatLabel(s.x)),
    datasets: [{
      label: 'Uptime',
      data: items.map(s => s.y),
      backgroundColor: items.map(s => {
        if (s.y === null) return 'transparent'
        return s.y >= 99 ? '#22c55e' : s.y >= 95 ? '#eab308' : '#ef4444'
      }),
      borderRadius: 2,
      categoryPercentage: 0.9,
      barPercentage: 0.9,
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
          if (ctx.parsed.y === null) return 'No data'
          return ctx.parsed.y + '% uptime'
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
      max: 100,
      grid: { display: false },
      ticks: {
        color: '#64748b',
        font: { size: 11 },
        callback: (v: any) => v + '%',
      },
      border: { display: false },
    },
  },
}))
</script>

<style scoped>
.timeline-header {
  @apply flex items-center justify-between mb-2;
}

.timeline-title {
  @apply text-sm font-medium;
}

.timeline-tabs {
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
