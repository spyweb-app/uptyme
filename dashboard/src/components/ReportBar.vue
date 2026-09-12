<template>
  <div class="report-bar">
    <div v-if="showNav" class="bar-nav">
      <button class="nav-btn" :disabled="!hasPrevMonth || !pageSlug" @click="prevMonth">‹</button>
      <span class="nav-label">{{ monthLabel }}</span>
      <button class="nav-btn" :disabled="!hasNextMonth || !pageSlug" @click="nextMonth">›</button>
    </div>
    <div class="bar-row">
      <div
        v-for="slot in slots"
        :key="slot.key"
        class="bar-segment"
        :class="barClass(slot)"
        @mouseenter="showTooltip($event, slot)"
        @mouseleave="hideTooltip"
      />
    </div>
    <div class="bar-footer">
      <span class="footer-label">{{ footerLeft }}</span>
      <span class="footer-uptime" v-if="overallUptime != null">Overall {{ overallUptime }}%</span>
      <span class="footer-label">{{ footerRight }}</span>
    </div>
    <Teleport to="body">
      <div v-if="tooltip.visible" class="bar-tooltip" :style="{ left: tooltip.x + 'px', top: tooltip.y + 'px' }">
        <div class="tooltip-date">{{ tooltip.date }}</div>
        <div class="tooltip-row">Uptime: <strong>{{ tooltip.uptime }}</strong></div>
        <div class="tooltip-row">Avg Response: <strong>{{ tooltip.response }}</strong></div>
        <div class="tooltip-row">Checks: <strong>{{ tooltip.up }} up</strong>, <strong class="text-down">{{ tooltip.down }} down</strong>, <strong class="text-blocked">{{ tooltip.blocked }} blocked</strong></div>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { type DaySummary } from '~lib/api'
import { getPublicReport } from '~lib/publicApi'

// state
const props = defineProps<{
  monitorId: number
  pageSlug?: string
  initialData?: DaySummary[]
}>()

const rawData = ref<DaySummary[]>([])
const currentMonth = ref('')
const hasPrevMonth = ref(false)
const hasNextMonth = ref(false)
const months = ref<string[]>([])
const viewMode = ref<'range' | 'month'>('range')

const tooltip = ref({
  visible: false,
  x: 0,
  y: 0,
  date: '',
  uptime: '',
  response: '',
  up: 0,
  down: 0,
  blocked: 0,
})

// computed
const monthLabel = computed(() => formatMonth(currentMonth.value))

const showNav = computed(() => {
  return hasPrevMonth.value || hasNextMonth.value
})

const overallUptime = computed(() => {
  const valid = rawData.value.filter(s => s.total > 0)
  if (valid.length === 0) return null
  const totalChecks = valid.reduce((sum, s) => sum + s.total, 0)
  const upChecks = valid.reduce((sum, s) => sum + s.up_count, 0)
  return totalChecks > 0 ? Math.round((upChecks / totalChecks) * 10000) / 100 : null
})

const footerLeft = computed(() => {
  if (slots.value.length === 0) return ''
  const first = slots.value[0]
  if (viewMode.value === 'month') {
    return formatDayLabel(first.key)
  }
  return `${slots.value.length} days ago`
})

const footerRight = computed(() => {
  if (slots.value.length === 0) return ''
  const last = slots.value[slots.value.length - 1]
  if (last.key === todayKey()) return 'Today'
  return formatDayLabel(last.key)
})

const slots = computed(() => {
  if (viewMode.value === 'month') {
    return buildMonthSlots(rawData.value, currentMonth.value)
  }
  return buildRangeSlots(rawData.value)
})

// helpers
interface Slot {
  key: string
  uptime: number | null
  response: number | null
  total: number
  down: number
  blocked: number
  up: number
}

function todayKey(): string {
  const d = new Date()
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
}

function isCurrentMonth(): boolean {
  const now = new Date()
  const cm = currentMonth.value
  return cm === `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
}

function formatMonth(month: string): string {
  const [y, m] = month.split('-')
  const d = new Date(Date.UTC(Number(y), Number(m) - 1, 1))
  return d.toLocaleString('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' })
}

function barClass(slot: Slot): string {
  if (slot.uptime == null) return 'bar-gray'
  if (slot.uptime === 100) return 'bar-green'
  if (slot.uptime >= 99) return 'bar-yellow'
  if (slot.uptime >= 95) return 'bar-orange'
  return 'bar-red'
}

function formatDayLabel(dateStr: string): string {
  const [y, m, d] = dateStr.split('-').map(Number)
  const date = new Date(Date.UTC(y, m - 1, d))
  return date.toLocaleString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
}

function buildRangeSlots(data: DaySummary[]): Slot[] {
  const now = new Date()
  const items: Slot[] = []
  for (let i = 29; i >= 0; i--) {
    const d = new Date(now)
    d.setUTCDate(d.getUTCDate() - i)
    const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
    const match = data.find(s => s.period === key)
    items.push(makeSlot(key, match))
  }
  return items
}

function buildMonthSlots(data: DaySummary[], month: string): Slot[] {
  const [y, m] = month.split('-').map(Number)
  const daysInMonth = new Date(y, m, 0).getDate()
  const items: Slot[] = []
  for (let d = 1; d <= daysInMonth; d++) {
    const key = `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
    const match = data.find(s => s.period === key)
    items.push(makeSlot(key, match))
  }
  return items
}

function makeSlot(key: string, match?: DaySummary): Slot {
  if (!match || match.total === 0) {
    return { key, uptime: null, response: null, total: 0, down: 0, blocked: 0, up: 0 }
  }
  return {
    key,
    uptime: Math.round((match.up_count / match.total) * 100),
    response: match.avg_response_ms != null ? Math.round(match.avg_response_ms) : null,
    total: match.total,
    down: match.down_checks,
    blocked: match.blocked_checks,
    up: match.up_count,
  }
}

function detectMonthFromData(data: DaySummary[]): string {
  if (data.length === 0) {
    const now = new Date()
    return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
  }
  const sample = data[0]?.period ?? ''
  if (sample.length >= 7) return sample.slice(0, 7)
  const now = new Date()
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`
}

function prevMonthKey(month: string): string {
  const [y, m] = month.split('-').map(Number)
  const d = new Date(Date.UTC(y, m - 2, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
}

function nextMonthKey(month: string): string {
  const [y, m] = month.split('-').map(Number)
  const d = new Date(Date.UTC(y, m, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
}

function showTooltip(e: MouseEvent, slot: Slot) {
  const [y, m, d] = slot.key.split('-').map(Number)
  const date = new Date(y, m - 1, d)
  tooltip.value = {
    visible: true,
    x: e.clientX,
    y: e.clientY - 80,
    date: date.toLocaleString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }),
    uptime: slot.uptime != null ? slot.uptime + '%' : 'N/A',
    response: slot.response != null ? slot.response + 'ms' : 'N/A',
    up: slot.up,
    down: slot.down,
    blocked: slot.blocked,
  }
}

function hideTooltip() {
  tooltip.value.visible = false
}

// lifecycle
async function goToMonth(month: string) {
  currentMonth.value = month
  viewMode.value = 'month'
  if (!props.pageSlug) return
  const result = await getPublicReport(props.pageSlug, {
    month,
    monitorId: props.monitorId,
  })
  rawData.value = result.summary
  if (months.value.length === 0) months.value = result.months
  hasPrevMonth.value = months.value.some(m => m < month)
  hasNextMonth.value = !isCurrentMonth() && months.value.some(m => m > month)
}

async function prevMonth() {
  if (!hasPrevMonth.value) return
  await goToMonth(prevMonthKey(currentMonth.value))
}

async function nextMonth() {
  if (!hasNextMonth.value) return
  await goToMonth(nextMonthKey(currentMonth.value))
}

async function init() {
  if (props.initialData && props.initialData.length > 0) {
    rawData.value = props.initialData
    currentMonth.value = detectMonthFromData(props.initialData)
    viewMode.value = 'range'
    hasPrevMonth.value = props.initialData.some(s => s.period < currentMonth.value)
    hasNextMonth.value = isCurrentMonth() ? false : props.initialData.some(s => s.period > currentMonth.value)
  } else if (props.pageSlug) {
    const result = await getPublicReport(props.pageSlug, {
      days: 30,
      group: 'day',
      monitorId: props.monitorId,
    })
    rawData.value = result.summary
    months.value = result.months
    currentMonth.value = detectMonthFromData(result.summary)
    viewMode.value = 'range'
    hasPrevMonth.value = months.value.some(m => m < currentMonth.value)
    hasNextMonth.value = !isCurrentMonth() && months.value.some(m => m > currentMonth.value)
  }
}

onMounted(() => init())

onBeforeUnmount(() => hideTooltip())
</script>

<style scoped>
.report-bar {
  @apply w-full;
}

.bar-nav {
  @apply flex items-center justify-center gap-3 mb-3;
}

.nav-btn {
  @apply w-7 h-7 flex items-center justify-center text-sm border border-[var(--border-active)] bg-transparent text-[var(--text-secondary)] rounded-md cursor-pointer transition-all duration-150;

  &:hover:not(:disabled) { @apply border-[var(--accent)] text-[var(--text)]; }
  &:disabled { @apply opacity-30 cursor-not-allowed; }
}

.nav-label {
  @apply text-sm font-medium min-w-[120px] text-center;
}

.bar-row {
  @apply flex gap-[5px] w-full;
}

.bar-segment {
  flex: 1;
  height: 50px;
  border-radius: 2px;
  cursor: pointer;
  transition: opacity 0.15s;

  &:hover { opacity: 0.8; }
}

.bar-green { @apply bg-[var(--up)]; }
.bar-yellow { @apply bg-yellow-500; }
.bar-orange { @apply bg-orange-500; }
.bar-red { @apply bg-[var(--down)]; }
.bar-gray { @apply bg-[var(--border)]; }

.bar-footer {
  @apply flex items-center justify-between mt-2;
}

.footer-label {
  @apply text-[11px] text-[var(--text-muted)];
}

.footer-uptime {
  @apply text-[12px] font-medium text-[var(--text-secondary)];
}

.bar-tooltip {
  @apply fixed z-[9999] bg-[var(--surface)] border border-[var(--border)] rounded-lg px-3 py-2 text-[12px] pointer-events-none shadow-lg;
}

.tooltip-date {
  @apply font-medium mb-1;
}

.tooltip-row {
  @apply text-[var(--text-secondary)];
}

.text-down { @apply text-[var(--down)]; }
.text-blocked { @apply text-[var(--blocked)]; }
</style>
