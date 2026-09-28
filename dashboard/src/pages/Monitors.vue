<template>
  <header class="topbar">
    <h1 class="title">
      <span class="i-mdi-monitor-dashboard text-[var(--accent)] mr-2" />
      Monitors
    </h1>
    <div class="topbar-actions">
      <template v-if="!isChecker">
        <div class="btn-group">
          <button class="btn-secondary" @click="showExport = !showExport">
            <span class="i-mdi-download mr-1" />
            Export
          </button>
          <div v-if="showExport" class="dropdown" @click.stop>
            <button class="dropdown-item" @click="doExport('json')">
              <span class="i-mdi-code-json mr-1" />JSON
            </button>
            <button class="dropdown-item" @click="doExport('csv')">
              <span class="i-mdi-file-delimited-outline mr-1" />CSV
            </button>
          </div>
        </div>
        <button class="btn-secondary" @click="importInput?.click()">
          <span class="i-mdi-upload mr-1" />
          Import
        </button>
        <input
          ref="importInput"
          type="file"
          accept=".json,.csv"
          class="hidden-input"
          @change="doImport"
        />
        <button class="btn-primary" @click="openAddForm">
          <span class="i-mdi-plus mr-1" />
          Add Monitor
        </button>
      </template>
    </div>
  </header>

  <div class="toolbar">
    <div class="search-box">
      <span class="i-mdi-magnify search-icon" />
      <input v-model="q" placeholder="Search monitors..." @input="onSearchInput" />
    </div>
    <div class="toolbar-right">
      <button class="poll-toggle" title="Refresh" @click="onRefresh">
        <span class="i-mdi-refresh" />
      </button>
      <span class="monitor-count">
        {{ store.total }} monitor{{ store.total !== 1 ? 's' : '' }}
      </span>
      <div class="filter-group">
        <select v-model="sortBy" @change="onFilterChange">
          <option value="name">Name</option>
          <option value="url">URL</option>
          <option value="response_time">Response Time</option>
          <option value="last_check_at">Last Check</option>
          <option value="created_at">Created</option>
        </select>
        <button class="order-btn" @click="toggleOrder"
          :title="sortOrder === 'asc' ? 'Ascending' : 'Descending'">
          <span v-if="sortOrder === 'asc'" class="i-mdi-sort-ascending" />
          <span v-else class="i-mdi-sort-descending" />
        </button>
        <select v-model="enabledFilter" @change="onFilterChange">
          <option :value="-1">All</option>
          <option :value="1">Enabled</option>
          <option :value="0">Disabled</option>
        </select>
      </div>
    </div>
  </div>

  <div class="content">
    <div class="relative min-h-full">
      <LoadingOverlay v-if="store.loading" />
      <template v-else>
        <div v-if="store.monitors.length > 0" class="monitor-list">
          <MonitorCard
          v-for="m in store.monitors"
          :key="m.id"
          :monitor="m"
          :readonly="isChecker"
          @click="selectMonitor(m)"
          />
        </div>
        <div class="empty" v-else>
          <div class="empty-icon">&#9670;</div>
          <template v-if="q === '' && enabledFilter < 0">
            <h2>No monitors yet</h2>
            <p v-if="!isChecker">Add your first URL or import from a file.</p>
            <p v-else>No monitors synced from central yet.</p>
            <div v-if="!isChecker" class="flex gap-3 mt-4">
              <button class="btn-primary" @click="openAddForm">+ Add Monitor</button>
              <button class="btn-secondary" @click="importInput?.click()">Import</button>
            </div>
          </template>
          <template v-else>
            <h2>No monitors match</h2>
            <p>Try different keywords or adjust the filters.</p>
          </template>
        </div>
      </template>
    </div>
  </div>

  <div v-if="store.totalPages > 1" class="pagination">
    <button class="page-btn" :disabled="page <= 1" @click="goToPage(page - 1)">
      <span class="i-mdi-chevron-left" /> Prev
    </button>
    <template v-for="p in pageRange" :key="typeof p === 'string' ? p : p">
      <span v-if="typeof p === 'string'" class="page-ellipsis">{{ p }}</span>
      <button v-else class="page-btn" :class="{ active: p === page }" @click="goToPage(p)">
        {{ p }}
      </button>
    </template>
    <button class="page-btn" :disabled="page >= store.totalPages" @click="goToPage(page + 1)">
      Next <span class="i-mdi-chevron-right" />
    </button>
    <select v-model="perPage" @change="onPerPageChange" class="per-page">
      <option :value="25">25</option>
      <option :value="50">50</option>
      <option :value="100">100</option>
    </select>
  </div>

  <MonitorDetail
    v-if="store.selectedMonitorId"
    @close="onDetailClose"
  />

  <MonitorForm
    v-if="showForm"
    :monitor="editingMonitor"
    @close="showForm = false"
    @saved="onMonitorSaved"
  />
</template>

<script setup lang="ts">
defineOptions({ layout: 'default' })

import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api, type Monitor } from '~lib/api'
import { useMonitorStore } from '~stores/monitors'
import LoadingOverlay from '~com/LoadingOverlay.vue'
import MonitorCard from '~com/MonitorCard.vue'
import MonitorDetail from '~com/MonitorDetail.vue'
import MonitorForm from '~com/MonitorForm.vue'
import { showNotification, nodeRole } from '~stores/app'

const store = useMonitorStore()
const route = useRoute()
const router = useRouter()

const isChecker = computed(() => nodeRole.value === 'checker')

const showForm = ref(false)
const editingMonitor = ref<Monitor | null>(null)
const showExport = ref(false)
const importInput = ref<HTMLInputElement>()

const q = ref('')
const sortBy = ref('created_at')
const sortOrder = ref('desc')
const enabledFilter = ref(-1)
const page = ref(1)
const perPage = ref(25)

let searchTimer: ReturnType<typeof setTimeout> | null = null

async function loadMonitors() {
  await store.load({
    page: page.value,
    per_page: perPage.value,
    sort: sortBy.value,
    order: sortOrder.value,
    q: q.value,
    enabled: enabledFilter.value >= 0 ? enabledFilter.value : undefined,
  })
}

function onRefresh() {
  loadMonitors()
}

function onSearchInput() {
  if (searchTimer) clearTimeout(searchTimer)
  searchTimer = setTimeout(() => {
    page.value = 1
    loadMonitors()
  }, 300)
}

function onFilterChange() {
  page.value = 1
  loadMonitors()
}

function onPerPageChange() {
  page.value = 1
  loadMonitors()
}

function goToPage(n: number) {
  page.value = n
  loadMonitors()
}

function toggleOrder() {
  sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc'
  onFilterChange()
}

const pageRange = computed(() => {
  const tp = store.totalPages
  const cur = page.value
  if (tp <= 10) {
    return Array.from({ length: tp }, (_, i) => i + 1)
  }
  const pages: (number | string)[] = []
  for (let i = 1; i <= 3; i++) pages.push(i)
  const start = Math.max(4, cur - 2)
  const end = Math.min(tp - 3, cur + 2)
  if (start > 4) pages.push('...')
  for (let i = start; i <= end; i++) pages.push(i)
  if (end < tp - 3) pages.push('...')
  for (let i = tp - 2; i <= tp; i++) pages.push(i)
  return pages
})

function openAddForm() {
  editingMonitor.value = null
  showForm.value = true
}

function selectMonitor(m: Monitor) {
  if (isChecker.value) return
  store.selectedMonitorId = m.id
}

function onDetailClose() {
  store.selectedMonitorId = null
  if (store.monitors.length === 0 && page.value > 1) {
    goToPage(page.value - 1)
  }
}

function onMonitorSaved() {
  showForm.value = false
  editingMonitor.value = null
  showNotification('Monitor created', 'success')
}

async function doExport(format: 'json' | 'csv') {
  showExport.value = false
  try {
    await api.exportMonitors(format)
    showNotification(`Exported as ${format.toUpperCase()}`, 'success')
  } catch (e: any) {
    showNotification(e.message || 'Export failed', 'error')
  }
}

async function doImport(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  const text = await file.text()
  const contentType = file.name.endsWith('.csv') ? 'text/csv' : 'application/json'
  try {
    const result = await api.importMonitors(text, contentType)
    page.value = 1
    await loadMonitors()
    showNotification(`Imported ${result.imported}, skipped ${result.skipped}, failed ${result.failed}`, 'success')
  } catch (err: any) {
    showNotification(err.message || 'Import failed', 'error')
  }
  ;(e.target as HTMLInputElement).value = ''
}

function onClickAway(e: MouseEvent) {
  const target = e.target as HTMLElement
  if (!target.closest('.btn-group')) showExport.value = false
}

async function openMonitorFromQuery(id: number) {
  if (searchTimer) clearTimeout(searchTimer)
  q.value = ''
  enabledFilter.value = -1
  page.value = 1
  await loadMonitors()
  if (store.monitors.some(m => m.id === id)) {
    store.selectedMonitorId = id
  } else {
    try {
      const mon = await api.getMonitor(id)
      store.monitors.push(mon)
      store.selectedMonitorId = id
    } catch {
      showNotification('Monitor not found', 'error')
    }
  }
  router.replace({ path: '/monitors' })
}

onMounted(() => {
  const raw = route.query.id
  const id = Number(Array.isArray(raw) ? raw[0] : raw)
  if (Number.isFinite(id) && id > 0) {
    openMonitorFromQuery(id)
  } else {
    loadMonitors()
  }
  document.addEventListener('click', onClickAway)
})

onUnmounted(() => {
  document.removeEventListener('click', onClickAway)
})
</script>

<style scoped>
.topbar-actions {
  @apply flex items-center gap-4;
}

.empty {
  @apply flex flex-col items-center justify-center h-[60vh] text-center gap-3;

  & h2 {
    @apply text-xl font-semibold;
  }

  & p {
    @apply text-[var(--text-muted)] text-sm;
  }
}

.empty-icon {
  @apply text-[48px] text-[var(--accent)] opacity-30;
}

.monitor-list {
  @apply flex flex-col gap-2;
}

.btn-group {
  @apply relative;
}

.dropdown {
  @apply absolute top-full left-0 mt-1 bg-[var(--input)] border border-[var(--border-hover)] rounded-lg overflow-hidden z-50 min-w-[100px];
}

.dropdown-item {
  @apply block w-full px-4 py-2 border-none bg-transparent text-[var(--text)] text-[13px] text-left cursor-pointer;
  transition: background 0.1s;

  &:hover {
    @apply bg-[var(--border-hover)];
  }
}

.hidden-input {
  @apply hidden;
}

.toolbar {
  @apply flex items-center justify-between px-7 py-3 border-b border-[var(--border)] bg-[var(--surface)] gap-4;
}

.search-box {
  @apply flex items-center flex-1 max-w-sm bg-[var(--input)] border border-[var(--border)] rounded-lg px-3 py-1.5;

  &:focus-within {
    @apply border-[var(--accent)];
  }
}

.search-icon {
  @apply text-[var(--text-muted)] mr-2 shrink-0;
}

.search-box input {
  @apply bg-transparent border-none text-[var(--text)] text-[13px] outline-none w-full placeholder-[var(--text-muted)];
}

.toolbar-right {
  @apply flex items-center gap-4 shrink-0;
}

.monitor-count {
  @apply text-[13px] text-[var(--text-muted)] whitespace-nowrap;
}

.filter-group {
  @apply flex items-center gap-2;
}

.filter-group select {
  @apply bg-[var(--input)] border border-[var(--border)] text-[var(--text)] text-[13px] rounded-lg px-2.5 py-1.5 outline-none cursor-pointer;

  &:focus {
    @apply border-[var(--accent)];
  }
}

.poll-toggle {
  @apply w-8 h-8 flex items-center justify-center bg-[var(--input)] border border-[var(--border)] rounded-lg text-[var(--text-muted)] cursor-pointer transition-all duration-150 mr-2;

  &:hover {
    @apply text-[var(--text)] border-[var(--border-hover)];
  }

  &.active {
    @apply text-[var(--accent)] border-[var(--accent)];
  }
}

.order-btn {
  @apply w-8 h-8 flex items-center justify-center bg-[var(--input)] border border-[var(--border)] rounded-lg text-[var(--text-muted)] cursor-pointer transition-all duration-150;

  &:hover {
    @apply text-[var(--text)] border-[var(--border-hover)];
  }
}

.pagination {
  @apply flex items-center justify-center gap-1.5 px-7 py-3 border-t border-[var(--border)] bg-[var(--base)] shrink-0;
}

.page-btn {
  @apply px-3 py-1.5 border border-[var(--border)] bg-[var(--input)] text-[var(--text)] text-[13px] rounded-lg cursor-pointer transition-all duration-150 flex items-center gap-1;

  &:hover:not(:disabled) {
    @apply border-[var(--border-hover)] bg-[var(--hover)];
  }

  &:disabled {
    @apply opacity-40 cursor-default;
  }

  &.active {
    @apply bg-[var(--accent)] border-[var(--accent)] text-white;
  }
}

.page-ellipsis {
  @apply px-1 text-[var(--text-muted)] text-[13px];
}

.per-page {
  @apply ml-3 bg-[var(--input)] border border-[var(--border)] text-[var(--text)] text-[13px] rounded-lg px-2 py-1.5 outline-none cursor-pointer;
}
</style>
