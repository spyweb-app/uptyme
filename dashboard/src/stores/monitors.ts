import { defineStore } from 'pinia'
import { ref } from 'vue'
import { api, type Monitor, type Check } from '~lib/api'

export const useMonitorStore = defineStore('monitors', () => {
  const monitors = ref<Monitor[]>([])
  const total = ref(0)
  const totalPages = ref(0)
  const loading = ref(false)
  const historyMap = ref<Record<number, Check[]>>({})
  const selectedMonitorId = ref<number | null>(null)

  async function load(opts?: {
    page?: number
    per_page?: number
    sort?: string
    order?: string
    q?: string
    enabled?: number
  }) {
    loading.value = true
    try {
      const result = await api.listMonitors(opts)
      monitors.value = Array.isArray(result.items) ? result.items : []
      total.value = result.total
      totalPages.value = result.total_pages
    } catch {
      //silence error
    } finally {
      loading.value = false
    }
  }

  async function toggleEnabled(id: number, enabled: number) {
    await api.updateMonitor(id, { enabled })
    const m = monitors.value.find(m => m.id === id)
    if (m) m.enabled = enabled
  }

  async function remove(id: number) {
    await api.deleteMonitor(id)
    monitors.value = monitors.value.filter(m => m.id !== id)
    total.value = Math.max(0, total.value - 1)
    if (total.value === 0) totalPages.value = 1
    if (selectedMonitorId.value === id) selectedMonitorId.value = null
  }

  async function create(data: Partial<Monitor>) {
    const mon = await api.createMonitor(data)
    monitors.value.push(mon)
    total.value++
    return mon
  }

  async function update(id: number, data: Partial<Monitor>) {
    const updated = await api.updateMonitor(id, data)
    patch(updated)
  }

  async function setChannels(id: number, channelIds: number[]) {
    await api.updateMonitor(id, { channel_ids: channelIds })
  }

  function patch(updated: Partial<Monitor>) {
    const idx = monitors.value.findIndex(m => m.id === updated.id)
    if (idx !== -1) {
      monitors.value[idx] = { ...monitors.value[idx], ...updated }
    }
  }

  async function fetchHistory(id: number, limit = 100) {
    const data = await api.getHistory(id, undefined, limit)
    historyMap.value = { ...historyMap.value, [id]: data }
  }

  async function appendHistory(id: number, checks: Check[]) {
    const existing = historyMap.value[id] || []
    historyMap.value = { ...historyMap.value, [id]: [...existing, ...checks] }
  }

  return { monitors, total, totalPages, loading, historyMap, selectedMonitorId, load, toggleEnabled, remove, create, update, setChannels, fetchHistory, appendHistory }
})
