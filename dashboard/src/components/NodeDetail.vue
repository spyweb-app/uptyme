<template>
  <div class="slide-over-backdrop" @click.self="store.selectedNodeId = null">
    <div class="slide-panel">
      <div class="panel-header">
        <div class="panel-header-left">
          <label class="toggle" @click.stop>
            <input type="checkbox" :checked="node.active === 1" @change="toggleActive" />
            <span class="toggle-slider"></span>
          </label>
          <div>
            <input
              v-if="renaming"
              class="panel-title-input editing"
              :value="nodeName"
              ref="nameInput"
              @blur="rename"
              @keydown.enter="rename"
            />
            <h2 v-else class="panel-title" @click="startRename">{{ nodeName }}</h2>
            <span class="panel-meta">ID: {{ node.id }}</span>
          </div>
        </div>
        <div class="panel-header-right">
          <button v-if="renaming" class="btn-ghost btn-save" @click="saveRename">Save</button>
          <button v-else class="btn-ghost" @click="startRename">Rename</button>
          <button class="btn-danger" @click="confirmResetToken = true">Reset Token</button>
          <button class="btn-danger" @click="confirmDelete = true">Delete</button>
          <button class="close-btn" @click="store.selectedNodeId = null">&times;</button>
        </div>
      </div>

      <div class="panel-body">
        <div class="stats-row">
          <div class="stat-box">
            <span class="stat-box-value">{{ node.last_seen_at ? formatRelative(node.last_seen_at) : '-' }}</span>
            <span class="stat-box-label">Last Seen</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value">{{ reports.length }}</span>
            <span class="stat-box-label">Reports</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value">{{ uniqueMonitors }}</span>
            <span class="stat-box-label">Monitors</span>
          </div>
          <div class="stat-box">
            <span class="stat-box-value" :class="node.active === 1 ? 'text-up' : 'text-[var(--text-muted)]'">
              {{ node.active === 1 ? 'Active' : 'Inactive' }}
            </span>
            <span class="stat-box-label">Status</span>
          </div>
        </div>

        <div class="section-card">
          <h3 class="section-title">Details</h3>
          <div class="detail-grid">
            <div class="detail-field">
              <span class="detail-label">Name</span>
              <span class="detail-value">{{ node.name }}</span>
            </div>
            <div class="detail-field">
              <span class="detail-label">ID</span>
              <span class="detail-value monospace">{{ node.id }}</span>
            </div>
            <div class="detail-field">
              <span class="detail-label">Local Name</span>
              <span class="detail-value">{{ node.local_name || '-' }}</span>
            </div>
            <div class="detail-field">
              <span class="detail-label">Created</span>
              <span class="detail-value">{{ formatDate(node.created_at) }}</span>
            </div>
            <div class="detail-field">
              <span class="detail-label">Updated</span>
              <span class="detail-value">{{ formatDate(node.updated_at) }}</span>
            </div>
          </div>
        </div>

        <div class="section-card">
          <h3 class="section-title">Recent Reports</h3>
          <table class="detail-table" v-if="reports.length > 0">
            <thead>
              <tr>
                <th>Time</th>
                <th>Monitor</th>
                <th>Status</th>
                <th>Code</th>
                <th>Response</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(r, i) in reports" :key="i">
                <td>{{ formatDateTime(r.reported_at) }}</td>
                <td class="monitor-cell">
                  <span class="monitor-name">{{ r.monitor_name || '-' }}</span>
                </td>
                <td>
                  <span :class="r.is_up ? 'text-up' : 'text-down'">
                    {{ r.is_up ? 'UP' : 'DOWN' }}
                  </span>
                </td>
                <td>{{ r.status_code ?? '-' }}</td>
                <td>{{ r.response_time_ms != null ? r.response_time_ms + 'ms' : '-' }}</td>
                <td class="error-cell">{{ r.error_message || '-' }}</td>
              </tr>
            </tbody>
          </table>
          <div v-else class="no-data">No reports yet</div>
        </div>
      </div>
    </div>

    <div v-if="showToken" class="modal-overlay" @click.self="showToken = ''">
      <div class="modal">
        <div class="modal-header">
          <h2 class="modal-title">Token Reset</h2>
          <button class="close-btn" @click="showToken = ''">&times;</button>
        </div>
        <div class="modal-body">
          <p class="token-desc">Copy this token now. It will not be shown again.</p>
          <div class="token-display" @click="copyToken">
            <code>{{ showToken }}</code>
            <span class="copy-hint" v-if="!copied">Click to copy</span>
            <span class="copy-hint copied" v-else>Copied!</span>
          </div>
          <button class="btn-primary w-full mt-4" @click="showToken = ''">Done</button>
        </div>
      </div>
    </div>

    <ConfirmDialog
      v-if="confirmResetToken"
      title="Reset Token"
      :message="'Reset the auth token for ' + nodeName + '? The current token will stop working immediately.'"
      confirm-text="Reset"
      @confirm="doResetToken"
      @cancel="confirmResetToken = false"
    />

    <ConfirmDialog
      v-if="confirmDelete"
      title="Delete Node"
      :message="'Delete ' + nodeName + '? This will permanently remove the node and all its reports.'"
      @confirm="doDelete"
      @cancel="confirmDelete = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, nextTick } from 'vue'
import { api, type NodeReport } from '~lib/api'
import { showNotification } from '~stores/app'
import { useNodeStore } from '~stores/nodes'
import { formatRelative, formatDate, formatDateTime } from '~lib/dates'
import ConfirmDialog from './ConfirmDialog.vue'

const store = useNodeStore()

const node = computed(() => store.nodes.find(n => n.id === store.selectedNodeId)!)
const nodeName = ref(node.value?.name ?? '')
const renaming = ref(false)
const nameInput = ref<HTMLInputElement>()
const confirmResetToken = ref(false)
const confirmDelete = ref(false)
const showToken = ref('')
const copied = ref(false)

const reports = ref<NodeReport[]>([])
const uniqueMonitors = computed(() => new Set(reports.value.map(r => r.monitor_id)).size)

function startRename() {
  renaming.value = true
  nextTick(() => nameInput.value?.focus())
}

async function doRename(val: string) {
  val = val.trim()
  if (!val || val === nodeName.value) {
    renaming.value = false
    return
  }
  try {
    await store.updateNode(node.value.id, { name: val })
    nodeName.value = val
    showNotification('Node renamed', 'success')
  } catch (e: any) {
    showNotification(e.message, 'error')
  }
  renaming.value = false
}

function rename(e: Event) {
  doRename((e.target as HTMLInputElement).value)
}

function saveRename() {
  if (nameInput.value) doRename(nameInput.value.value)
}

async function toggleActive() {
  try {
    await store.toggleActive(node.value)
    showNotification(node.value.active === 1 ? 'Node activated' : 'Node deactivated', 'success')
  } catch (e: any) {
    showNotification(e.message, 'error')
  }
}

async function doResetToken() {
  confirmResetToken.value = false
  try {
    const token = await store.resetNodeToken(node.value.id)
    showToken.value = token
    showNotification('Token reset for ' + nodeName.value, 'success')
  } catch (e: any) {
    showNotification(e.message, 'error')
  }
}

async function doDelete() {
  try {
    await store.remove(node.value.id)
    confirmDelete.value = false
    showNotification('Node deleted', 'success')
  } catch (e: any) {
    showNotification(e.message, 'error')
    confirmDelete.value = false
  }
}

async function copyToken() {
  try {
    await navigator.clipboard.writeText(showToken.value)
    copied.value = true
    setTimeout(() => { copied.value = false }, 2000)
  } catch {}
}

onMounted(async () => {
  try {
    reports.value = await api.getNodeReports(node.value.id)
  } catch {}
})
</script>

<style scoped>
.panel-title-input {
  @apply text-lg font-semibold bg-transparent border-none outline-none p-0;
  min-width: 50px;

  &.editing {
    @apply border-b border-[var(--accent)];
  }
}

.btn-save {
  @apply text-[var(--up)];
}

.panel-meta {
  @apply text-xs text-[var(--text-muted)];
}

.stats-row {
  @apply grid grid-cols-4 gap-[10px] mb-6;
}

.section-card {
  @apply mb-6 bg-[var(--elevated)] border border-[var(--border)] rounded-xl p-4;
}

.detail-grid {
  @apply grid grid-cols-2 gap-x-6 gap-y-3;
}

.detail-field {
  @apply flex flex-col gap-0.5;
}

.detail-label {
  @apply text-[11px] text-[var(--text-muted)] uppercase tracking-[0.5px];
}

.detail-value {
  @apply text-sm;
}

.monospace {
  @apply font-mono text-xs;
}

.monitor-cell {
  @apply max-w-[200px] overflow-hidden truncate;
}

.monitor-name {
  @apply text-sm;
}

.modal-overlay {
  @apply fixed inset-0 bg-black/50 z-[60] flex items-center justify-center;
}

.modal {
  @apply bg-[var(--surface)] border border-[var(--border)] rounded-xl w-full max-w-[420px] shadow-lg mx-4;
}
</style>
