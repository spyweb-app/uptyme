<template>
  <header class="topbar">
    <h1 class="title">
      <span class="i-mdi-web-box text-[var(--accent)] mr-2" />
      Status Pages
    </h1>
    <button class="btn-primary" @click="openCreate">
      <span class="i-mdi-plus mr-1" />
      New Page
    </button>
  </header>

  <div class="content">
    <LoadingOverlay v-if="loading" design="fallback" />

    <div v-else-if="pages.length === 0" class="empty">
      <span class="i-mdi-web-box text-5xl text-[var(--text-muted)] opacity-30" />
      <p>No status pages yet.</p>
      <p class="text-sm text-[var(--text-muted)]">Create your first public status page to share uptime with customers.</p>
      <button class="btn-primary mt-3" @click="openCreate">Create your first page</button>
    </div>

    <div v-else class="page-list">
      <article v-for="page in pages" :key="page.id" class="page-card">
        <div class="card-main">
          <label class="toggle" @click.stop>
            <input type="checkbox" :checked="page.is_public === 1" @change="togglePublic(page)" />
            <span class="toggle-slider"></span>
          </label>

          <span class="page-icon" :class="page.type === 'monitor' ? 'icon-monitor' : 'icon-group'">
            <span v-if="page.type === 'monitor'" class="i-mdi-monitor" />
            <span v-else class="i-mdi-web" />
          </span>

          <div class="card-info">
            <div class="card-header-row">
              <h2 class="card-name">{{ page.name }}</h2>
              <span class="type-badge" :class="page.type">
                {{ page.type === 'monitor' ? 'Monitor' : 'Group' }}
              </span>
            </div>
            <p v-if="page.description" class="card-description">{{ page.description }}</p>
          </div>
        </div>

        <div class="card-actions">
          <a v-if="page.is_public === 1" :href="publicLink(page)" target="_blank" rel="noopener" class="btn-secondary btn-small no-underline" title="Preview public page">
            <span class="i-mdi-open-in-new mr-1" />
            Preview
          </a>
          <button class="btn-ghost-sm" @click="copyLink(page)" title="Copy URL">
            <span class="i-mdi-content-copy" />
          </button>
          <button class="btn-ghost-sm" @click="openEdit(page)" title="Edit page">
            <span class="i-mdi-pencil" />
          </button>
          <button class="btn-ghost-sm danger" @click="confirmDelete(page)" title="Delete page">
            <span class="i-mdi-delete" />
          </button>
        </div>
      </article>
    </div>
  </div>

  <div v-if="editing" class="modal-overlay">
    <div class="modal">
      <div class="modal-header">
        <h2 class="modal-title">{{ editing.id ? 'Edit status page' : 'New status page' }}</h2>
        <button class="close-btn" @click="closeModal">&times;</button>
      </div>

      <form class="modal-body" @submit.prevent="savePage">
        <div class="field">
          <label class="label">Type</label>
          <select class="input" v-model="form.type" :disabled="!!editing.id" @change="onTypeChange">
            <option value="group">Group</option>
            <option value="monitor">Individual monitor</option>
          </select>
        </div>

        <div v-if="form.type === 'monitor' && !editing.id" class="field">
          <label class="label">Monitor</label>
          <SearchSelect
            mode="single"
            v-model="selectedMonitor"
            :items="availableMonitors"
            :loading="monitorsLoading"
            placeholder="Search monitors..."
            label-key="name"
            sublabel-key="url"
            @search="searchMonitors"
            @focus="onMembersFocus"
          />
          <span v-if="errors.monitor_id" class="field-error">{{ errors.monitor_id }}</span>
        </div>

        <div v-if="form.type === 'monitor' && editing.id && editingMonitor" class="field">
          <label class="label">Monitor</label>
          <div class="readonly-monitor">
            <span class="i-mdi-monitor" />
            <div>
              <span class="readonly-monitor-name">{{ editingMonitor.name }}</span>
              <span class="readonly-monitor-url">{{ editingMonitor.url }}</span>
            </div>
          </div>
        </div>

        <div class="field">
          <label class="label">Public name</label>
          <input class="input" :class="{ invalid: errors.name }" v-model="form.name" placeholder="Customer API" @input="clearError('name')" />
          <span v-if="errors.name" class="field-error">{{ errors.name }}</span>
        </div>

        <div class="field">
          <label class="label">Description</label>
          <textarea class="input description-input" v-model="form.description" placeholder="Optional description shown publicly" />
        </div>

        <div v-if="form.type === 'group'" class="field">
          <label class="label">Group Members</label>
          <SearchSelect
            mode="multi"
            v-model="selectedMembers"
            :items="availableMonitors"
            :loading="monitorsLoading"
            placeholder="Search monitors to add..."
            label-key="name"
            sublabel-key="url"
            @search="searchMonitors"
            @focus="onMembersFocus"
          />
          <span v-if="errors.members" class="field-error">{{ errors.members }}</span>
        </div>

        <label class="checkbox-label">
          <input type="checkbox" v-model.number="form.is_public" :true-value="1" :false-value="0" />
          <span class="i-mdi-earth" />
          Publish this page
        </label>

        <div class="modal-actions">
          <button type="button" class="btn-secondary" @click="closeModal">Cancel</button>
          <button type="submit" class="btn-primary" :disabled="saving">
            {{ saving ? 'Saving...' : editing.id ? 'Save Changes' : 'Create Page' }}
          </button>
        </div>
      </form>
    </div>
  </div>

  <ConfirmDialog
    v-if="confirmDeletePage"
    title="Delete status page"
    :message="deleteMessage"
    @confirm="doDelete"
    @cancel="confirmDeletePage = null"
  />
</template>

<script setup lang="ts">
import { onMounted, ref, computed, reactive, watch } from 'vue'
import { api, type Monitor, type StatusPage } from '~lib/api'
import { showNotification } from '~stores/app'
import LoadingOverlay from '~com/LoadingOverlay.vue'
import ConfirmDialog from '~com/ConfirmDialog.vue'
import SearchSelect from '~com/SearchSelect.vue'

// state
const pages = ref<StatusPage[]>([])
const monitors = ref<Monitor[]>([])
const loading = ref(true)
const saving = ref(false)
const editing = ref<StatusPage | null>(null)
const confirmDeletePage = ref<StatusPage | null>(null)

const errors = reactive<Record<string, string>>({})

const form = reactive<{
  type: 'monitor' | 'group'
  monitor_id: number
  name: string
  description: string
  is_public: number
}>({
  type: 'group',
  monitor_id: 0,
  name: '',
  description: '',
  is_public: 0
})

const selectedMembers = ref<any[]>([])
const selectedMonitor = ref<any>(null)
const editingMonitor = ref<Monitor | null>(null)
const availableMonitors = ref<Monitor[]>([])
const monitorsLoading = ref(false)
const existingMemberIds = ref<Set<number>>(new Set())
let monitorsSearchTimer: ReturnType<typeof setTimeout> | null = null

// computed
const deleteMessage = computed(() =>
  confirmDeletePage.value ? `Delete "${confirmDeletePage.value.name}"?` : ''
)

// helpers
function clearError(field: string) {
  delete errors[field]
}

function validateForm(): boolean {
  let valid = true
  if (!form.name.trim()) {
    errors.name = 'Name is required'
    valid = false
  }
  if (form.type === 'monitor' && !form.monitor_id) {
    errors.monitor_id = 'Select a monitor'
    valid = false
  }
  return valid
}

function publicLink(page: StatusPage): string {
  return `${window.location.origin}/status/${encodeURIComponent(page.slug)}`
}

async function copyLink(page: StatusPage) {
  try {
    await navigator.clipboard.writeText(publicLink(page))
    showNotification('URL copied to clipboard', 'success')
  } catch {
    showNotification('Failed to copy URL', 'error')
  }
}

// lifecycle
async function searchMonitors(query: string) {
  if (monitorsSearchTimer) clearTimeout(monitorsSearchTimer)
  monitorsLoading.value = true
  monitorsSearchTimer = setTimeout(async () => {
    try {
      const result = await api.listMonitors({ q: query, per_page: 20 })
      availableMonitors.value = Array.isArray(result.items) ? result.items : []
    } catch (err: any) {
      showNotification(err.message, 'error')
    } finally {
      monitorsLoading.value = false
    }
  }, query ? 300 : 0)
}

function onMembersFocus() {
  if (!availableMonitors.value.length) {
    searchMonitors('')
  }
}

async function loadExistingMembers(pageId: number) {
  try {
    const members = await api.listStatusPageMonitors(pageId)
    existingMemberIds.value = new Set(members.map(m => m.id))
    selectedMembers.value = members.map(m => ({ id: m.id, name: m.name, url: m.url }))
  } catch (err: any) {
    showNotification(err.message, 'error')
  }
}

async function load() {
  loading.value = true
  try {
    const [pagesRes, monitorsRes] = await Promise.all([
      api.listStatusPages(),
      api.listMonitors({ per_page: 100 })
    ])
    pages.value = pagesRes
    monitors.value = Array.isArray(monitorsRes.items) ? monitorsRes.items : []
  } catch (err: any) {
    showNotification(err.message, 'error')
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editing.value = {} as StatusPage
  resetForm()
  form.type = 'group'
}

function openEdit(page: StatusPage) {
  editing.value = page
  editingMonitor.value = null
  Object.assign(form, {
    type: page.type,
    monitor_id: page.monitor_id || 0,
    name: page.name,
    description: page.description,
    is_public: page.is_public
  })
  if (page.type === 'group') {
    loadExistingMembers(page.id)
  }
  if (page.type === 'monitor' && page.monitor_id) {
    api.getMonitor(page.monitor_id).then(m => {
      editingMonitor.value = m
    }).catch(() => {})
  }
}

function onTypeChange() {
  if (form.type === 'monitor') {
    selectedMembers.value = []
    existingMemberIds.value = new Set()
    availableMonitors.value = []
  } else {
    selectedMonitor.value = null
  }
}

function resetForm() {
  Object.assign(form, {
    type: 'group',
    monitor_id: 0,
    name: '',
    description: '',
    is_public: 0
  })
  errors.name = ''
  errors.monitor_id = ''
  errors.members = ''
  selectedMembers.value = []
  selectedMonitor.value = null
  editingMonitor.value = null
  existingMemberIds.value = new Set()
  availableMonitors.value = []
}

function closeModal() {
  editing.value = null
  resetForm()
}

async function savePage() {
  if (!validateForm()) return

  saving.value = true

  try {
    const data = {
      type: form.type,
      monitor_id: form.type === 'monitor' ? form.monitor_id : undefined,
      name: form.name.trim(),
      description: form.description,
      is_public: form.is_public
    }

    let page: StatusPage
    if (editing.value?.id) {
      page = await api.updateStatusPage(editing.value.id, data)
      pages.value = pages.value.map(p => p.id === page.id ? page : p)
    } else {
      page = await api.createStatusPage(data)
      pages.value.push(page)
    }

    if (form.type === 'group' && page.id) {
      await syncMembers(page.id)
    }

    showNotification('Status page saved', 'success')
    closeModal()
  } catch (err: any) {
    showNotification(err.message, 'error')
  } finally {
    saving.value = false
  }
}

async function syncMembers(pageId: number) {
  try {
    await api.updateStatusPage(pageId, {
      monitors: selectedMembers.value.map((m, i) => ({ monitor_id: m.id, display_order: i })),
    })
  } catch (err: any) {
    showNotification(`Failed to sync monitors: ${err.message}`, 'error')
  }
}

async function togglePublic(page: StatusPage) {
  try {
    const updated = await api.updateStatusPage(page.id, { is_public: page.is_public !== 1 ? 1 : 0 })
    pages.value = pages.value.map(p => p.id === updated.id ? updated : p)
  } catch (err: any) {
    showNotification(err.message, 'error')
  }
}

function confirmDelete(page: StatusPage) {
  confirmDeletePage.value = page
}

async function doDelete() {
  if (!confirmDeletePage.value) return
  try {
    await api.deleteStatusPage(confirmDeletePage.value.id)
    pages.value = pages.value.filter(p => p.id !== confirmDeletePage.value!.id)
    showNotification('Status page deleted', 'success')
  } catch (err: any) {
    showNotification(err.message, 'error')
  } finally {
    confirmDeletePage.value = null
  }
}

watch(selectedMonitor, (m) => {
  form.monitor_id = m?.id || 0
})

onMounted(() => {
  load()
})
</script>

<style scoped>
.empty {
  @apply flex flex-col items-center justify-center h-[40vh] text-[var(--text-muted)] gap-3;
}

.page-list {
  @apply flex flex-col gap-2;
}

.page-card {
  @apply flex items-center justify-between bg-[var(--surface)] border border-[var(--border)] rounded-xl px-5 py-4 gap-4 transition-all duration-150;

  &:hover { @apply bg-[var(--elevated)] border-[var(--border-hover)]; }
}

.card-main {
  @apply flex items-center gap-3 flex-1 min-w-0;
}

.page-icon {
  @apply flex-shrink-0 w-8 h-8 rounded-lg flex items-center justify-center text-lg;
  background: color-mix(in srgb, var(--accent) 10%, transparent);
  color: var(--accent);

  &.icon-group {
    background: color-mix(in srgb, var(--blocked) 10%, transparent);
    color: var(--blocked);
  }
}

.card-info {
  @apply flex-1 min-w-0;
}

.card-header-row {
  @apply flex items-center gap-2;
}

.card-name {
  @apply text-base font-medium truncate;
}

.type-badge {
  @apply text-[11px] px-2 py-0.5 rounded-full font-medium shrink-0;

  &.group { background: color-mix(in srgb, var(--blocked) 10%, transparent); color: var(--blocked); }
  &.monitor { background: color-mix(in srgb, var(--accent) 10%, transparent); color: var(--accent); }
}

.card-description {
  @apply text-sm text-[var(--text-muted)] mt-1 truncate;
}

.card-actions {
  @apply flex items-center gap-2 shrink-0;
}

.btn-small {
  @apply px-3 py-1.5 text-xs;
}

.btn-ghost-sm {
  @apply inline-flex items-center px-2 py-1 border-none bg-transparent text-[var(--text-muted)] text-[12px] cursor-pointer rounded-lg;
  transition: color 0.15s;

  &:hover { @apply text-[var(--text)]; }
  &.danger:hover { @apply text-[var(--down)]; }
}

/* Toggle switch */
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

/* Modal */
.modal-overlay {
  @apply fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50;
}

.modal {
  @apply bg-[var(--surface)] rounded-xl border border-[var(--border)] shadow-2xl w-full max-w-2xl mx-4 max-h-[90vh] flex flex-col;
}

.modal-header {
  @apply flex items-center justify-between px-6 py-5 border-b border-[var(--border)];
}

.modal-title {
  @apply text-lg font-semibold;
}

.close-btn {
  @apply text-2xl text-[var(--text-muted)] bg-transparent border-none cursor-pointer;
  line-height: 1;

  &:hover { @apply text-[var(--text)]; }
}

.modal-body {
  @apply flex-1 overflow-y-auto p-6;
}

.modal-actions {
  @apply flex justify-end gap-2 mt-6 pt-4 border-t border-[var(--border)];
}

/* Form */
.field {
  @apply mb-4;
}

.label {
  @apply block text-sm font-medium text-[var(--text-secondary)] mb-1;
}

.input {
  @apply w-full bg-[var(--input)] border border-[var(--border)] rounded-lg px-3 py-2 text-[var(--text)] placeholder-[var(--text-muted)] focus:outline-none focus:border-[var(--accent)] focus:ring-1 focus:ring-[var(--accent)];

  &.invalid { @apply border-[var(--down)] focus:border-[var(--down)] focus:ring-[var(--down)]; }
}

.description-input {
  @apply min-h-[80px] resize-y;
}

.checkbox-label {
  @apply flex items-center gap-2 text-sm cursor-pointer select-none;
  @apply text-[var(--text-secondary)];

  input { @apply accent-[var(--accent)]; }
}

.field-error {
  @apply block text-[11px] text-[var(--down)] mt-1;
}

.readonly-monitor {
  @apply flex items-center gap-3 p-3 bg-[var(--bg)] border border-[var(--border)] rounded-lg;
  i { @apply text-lg text-[var(--accent)]; }
}
.readonly-monitor-name { @apply block text-sm font-medium; }
.readonly-monitor-url { @apply block text-xs text-[var(--text-muted)] mt-0.5 break-all; }

@media (max-width: 600px) {
  .page-card {
    @apply flex-col items-stretch gap-3;
  }

  .card-main {
    @apply flex-col items-start gap-2;
  }

  .card-actions {
    @apply justify-start;
  }

  .modal {
    @apply mx-2 max-h-[95vh];
  }
}
</style>
