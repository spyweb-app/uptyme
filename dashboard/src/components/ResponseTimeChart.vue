<template>
  <div>
    <div class="chart-title">Response Time (last 100 checks)</div>
    <div class="chart-wrap">
      <Line v-if="hasData" :data="chartData" :options="chartOptions" />
    </div>
    <div v-if="!hasData" class="no-data">No data yet</div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  TimeScale,
  Tooltip,
  Filler,
} from 'chart.js'
import 'chart.js/auto'
import 'chartjs-adapter-date-fns'
import { useMonitorStore } from '~stores/monitors'

ChartJS.register(LineElement, PointElement, LinearScale, TimeScale, Tooltip, Filler)

const props = defineProps<{
  monitorId: number
}>()

const store = useMonitorStore()

const chartData = computed(() => {
  const checks = store.historyMap[props.monitorId] || []
  const points = checks
    .filter(h => h.response_time_ms > 0)
    .reverse()
    .map(h => ({ x: h.checked_at * 1000, y: h.response_time_ms }))
  return {
    datasets: [{
      label: 'Response Time',
      data: points,
    borderColor: '#e11d48',
    backgroundColor: (ctx: any) => {
      if (!ctx.chart.chartArea) return 'rgba(225, 29, 72, 0.1)'
      const grad = ctx.chart.ctx.createLinearGradient(
        0, ctx.chart.chartArea.top,
        0, ctx.chart.chartArea.bottom
      )
      grad.addColorStop(0, 'rgba(225, 29, 72, 0.3)')
      grad.addColorStop(0.6, 'rgba(225, 29, 72, 0.06)')
      grad.addColorStop(1, 'rgba(225, 29, 72, 0)')
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

const hasData = computed(() => {
  const checks = store.historyMap[props.monitorId] || []
  return checks.some(h => h.response_time_ms > 0)
})

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    tooltip: {
      callbacks: {
        label: (ctx: any) => ctx.parsed.y + 'ms',
      },
    },
    legend: { display: false },
  },
  scales: {
    x: {
      type: 'time' as const,
      time: { unit: 'hour' as const },
      grid: { display: false },
      ticks: { color: '#64748b', font: { size: 11 } },
      border: { display: false },
    },
    y: {
      grid: {
        color: () => getComputedStyle(document.documentElement).getPropertyValue('--border').trim() || '#1f1f23',
      },
      ticks: {
        color: '#64748b',
        font: { size: 11 },
        callback: (v: any) => v + 'ms',
      },
      beginAtZero: true,
    },
  },
}))

</script>

<style scoped>
.chart-title {
  @apply text-sm font-medium mb-2;
}


</style>
