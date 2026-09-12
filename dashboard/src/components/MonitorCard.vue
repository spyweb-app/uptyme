<template>
  <div class="monitor-card" :class="{ readonly }">
    <div class="card-left">
      <span class="status-dot" :class="dotColor" />
      <label class="toggle" @click.stop v-if="!readonly">
        <input type="checkbox" :checked="monitor.enabled === 1" @change="toggleEnabled" />
        <span class="toggle-slider"></span>
      </label>
      <div class="card-info">
        <span class="card-name">{{ monitor.name }}</span>
        <span class="card-url">{{ monitor.url }}</span>
      </div>
    </div>
    <div class="card-right">
      <div class="status-text" :class="monitor.enabled === 1 ? 'running' : 'paused'">
        <span v-if="monitor.enabled === 1" class="i-mdi-play-circle-outline mr-1" />
        <span v-else class="i-mdi-pause-circle-outline mr-1" />
        {{ monitor.enabled === 1 ? 'Running' : 'Paused' }}
      </div>
      <div class="stat" v-if="monitor.last_response_time_ms">
        <span class="stat-value"><ResponseTime :ms="monitor.last_response_time_ms" /></span>
        <span class="stat-label">Response</span>
      </div>
      <div class="stat" v-if="monitor.uptime_24h">
        <span class="stat-value" :class="uptimeClass(monitor.uptime_24h)">
          {{ monitor.uptime_24h }}%
        </span>
        <span class="stat-label">24h uptime</span>
      </div>
      <div class="stat" v-if="monitor.uptime_7d">
        <span class="stat-value" :class="uptimeClass(monitor.uptime_7d)">
          {{ monitor.uptime_7d }}%
        </span>
        <span class="stat-label">7d uptime</span>
      </div>
      <div class="stat">
        <span class="stat-value">{{ formatInterval(monitor.interval_sec) }}</span>
        <span class="stat-label">Interval</span>
      </div>
      <StatusBadge :isUp="monitor.enabled === 0 ? undefined : monitor.is_up" :statusCode="monitor.enabled === 0 ? undefined : monitor.last_status_code" />
      <div class="card-arrow" v-if="!readonly">&#8250;</div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { Monitor } from '~lib/api'
import { useMonitorStore } from '~stores/monitors'
import { showNotification } from '~stores/app'
import StatusBadge from './StatusBadge.vue'
import ResponseTime from './ResponseTime.vue'

// state
const props = defineProps<{
  monitor: Monitor
  readonly?: boolean
}>()

const store = useMonitorStore()

// computed
const dotColor = computed(() => {
  if (props.monitor.enabled === 0) return 'paused'
  if (props.monitor.is_up === 1) return 'up'
  if (props.monitor.last_status_code && props.monitor.last_status_code >= 400 && props.monitor.last_status_code < 500) return 'blocked'
  if (props.monitor.is_up === 0) return 'down'
  return 'paused'
})

// helpers
function uptimeClass(val: number) {
  if (val >= 99) return 'text-green-400'
  if (val >= 95) return 'text-yellow-400'
  return 'text-red-400'
}

function formatInterval(sec: number) {
  if (sec >= 3600) return Math.round(sec / 3600) + 'h'
  if (sec >= 60) return Math.round(sec / 60) + 'm'
  return sec + 's'
}

// lifecycle
async function toggleEnabled() {
  const newVal = props.monitor.enabled === 1 ? 0 : 1
  try {
    await store.toggleEnabled(props.monitor.id, newVal)
    showNotification(newVal ? 'Monitor enabled' : 'Monitor disabled', 'success')
  } catch (e: any) {
    showNotification(e.message, 'error')
  }
}
</script>

<style scoped>
.monitor-card {
  @apply flex items-center justify-between bg-[var(--surface)] border border-[var(--border)] rounded-xl px-[18px] py-[14px] cursor-pointer transition-all duration-150;

  &:hover { @apply border-[var(--border-active)] bg-[var(--elevated)]; }

  &.readonly {
    @apply cursor-default;
    &:hover { @apply border-[var(--border)] bg-[var(--surface)]; }
  }
}

.card-left {
  @apply flex items-center gap-3 min-w-0;
}

.card-info {
  @apply flex flex-col gap-0.5 min-w-0;
}

.card-name {
  @apply text-sm font-medium truncate;
}

.card-url {
  @apply text-xs text-[var(--text-muted)] truncate max-w-[320px];
}

.card-right {
  @apply flex items-center gap-5 shrink-0;
}

.stat {
  @apply flex flex-col items-center gap-[1px] min-w-[56px];
}

.stat-value {
  @apply text-[13px] font-semibold tabular-nums;
}

.stat-label {
  @apply text-[10px] text-[var(--text-muted)] uppercase tracking-[0.5px];
}

.card-arrow {
  @apply text-xl text-[var(--arrow)] ml-1;
}

.status-dot {
  @apply w-2 h-2 rounded-full shrink-0;

  &.up { background: var(--up); }
  &.down { background: var(--down); }
  &.blocked { background: var(--blocked); }
  &.paused { background: var(--paused); }
}

.toggle {
  @apply relative inline-block w-9 h-5 shrink-0;

  & input {
    @apply opacity-0 w-0 h-0;
  }
}

.toggle-slider {
  @apply absolute cursor-pointer inset-0 bg-[var(--border-hover)] rounded-[20px];
  transition: 0.2s;

  &::before {
    content: '';
    position: absolute;
    height: 16px;
    width: 16px;
    left: 2px;
    bottom: 2px;
    background: var(--text-muted);
    border-radius: 50%;
    transition: 0.2s;
  }
}

.toggle input:checked + .toggle-slider {
  background: var(--up);

  &::before {
    transform: translateX(16px);
    background: #fff;
  }
}

.status-text {
  @apply text-[11px] font-semibold uppercase tracking-[0.5px];

  &.running { color: var(--up); }
  &.paused { color: var(--blocked); }
}
</style>
