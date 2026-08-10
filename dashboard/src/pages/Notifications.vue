<template>
  <header class="topbar">
    <h1 class="title">
      <span class="i-mdi-bell-ring-outline text-[var(--accent)] mr-2" />
      Notification Channels
    </h1>
    <button class="btn-primary" @click="openAdd">
      <span class="i-mdi-plus mr-1" />
      Add Channel
    </button>
  </header>

  <div class="content">
    <div class="relative min-h-full">
    <LoadingOverlay v-if="channelStore.loading" design="fallback" />
    <div v-if="channelStore.loading" class="loading">Loading...</div>
    <div v-else-if="channelStore.channels.length === 0" class="empty">
      <span class="i-mdi-bell-off-outline text-5xl text-[var(--text-muted)] opacity-30" />
      <p>No notification channels yet.</p>
      <p class="text-sm text-[var(--text-muted)]">Set up your first channel to get notified when monitors go down.</p>
      <button class="btn-primary" @click="openAdd">+ Add Channel</button>
    </div>
    <div v-else class="channel-list">
      <div v-for="ch in channelStore.channels" :key="ch.id" class="channel-row">
        <label class="toggle" @click.stop>
          <input type="checkbox" :checked="ch.enabled === 1" @change="toggleChannel(ch)" />
          <span class="toggle-slider"></span>
        </label>
        <div class="channel-info">
          <span v-if="ch.type === 'webhook'" class="i-mdi-webhook text-lg text-[var(--accent)]" />
          <span v-else-if="ch.type === 'discord'" class="i-mdi-discord text-lg text-[#5865f2]" />
          <span v-else-if="ch.type === 'slack'" class="i-mdi-slack text-lg text-[#e01e5a]" />
          <span v-else-if="ch.type === 'ntfy'" class="i-mdi-bell-ring text-lg text-[#22c55e]" />
          <span v-else-if="ch.type === 'email'" class="i-mdi-email-outline text-lg text-[var(--up)]" />
          <span v-else class="i-mdi-webhook text-lg text-[var(--text-muted)]" />
          <span class="channel-name">{{ ch.name }}</span>
          <span class="type-badge" :class="ch.type">{{ typeLabel(ch.type) }}</span>
        </div>
        <div class="channel-actions">
          <button class="btn-test" @click="testChannel(ch)" :disabled="sendingId === ch.id">
            <span class="i-mdi-send" />
            {{ sendingId === ch.id ? 'Sending...' : 'Test' }}
          </button>
          <button class="btn-ghost-sm" @click="openEdit(ch)">
            <span class="i-mdi-pencil" />
          </button>
          <button class="btn-ghost-sm danger" @click="deleteChannel(ch)">
            <span class="i-mdi-delete" />
          </button>
        </div>
      </div>
    </div>
    </div>
  </div>

  <div v-if="showTestResult" class="modal-overlay">
    <div class="result-modal">
      <div class="result-header">
        <span class="result-icon" :class="testOk ? 'ok' : 'fail'">
          <span v-if="testOk" class="i-mdi-check-circle" />
          <span v-else class="i-mdi-close-circle" />
        </span>
        <span class="result-title">{{ testOk ? 'Sent' : 'Failed' }}</span>
        <button class="result-close" @click="showTestResult = false">&times;</button>
      </div>
      <div class="result-body">
        <div class="result-field">
          <div class="result-label">Request</div>
          <pre class="result-code">{{ testRequestBody }}</pre>
        </div>
        <div class="result-field">
          <div class="result-label">Response</div>
          <div v-if="testOk" class="result-value">
            <span class="result-badge ok">&#10003; Sent</span>
            {{ testResp.name }} ({{ typeLabel(testResp.type) }})
          </div>
          <div v-else class="result-value fail">
            <span class="result-badge fail">&#10007; Failed</span>
            {{ testError }}
          </div>
        </div>
        <div v-if="testResp.response" class="result-field">
          <div class="result-label">HTTP Response</div>
          <pre class="result-code">{{ testResp.response }}</pre>
        </div>
      </div>
    </div>
  </div>

  <ChannelForm
    v-if="showForm"
    :channel="editingChannel"
    @close="showForm = false"
    @saved="onSaved"
  />

  <ConfirmDialog
    v-if="confirmDelete"
    title="Delete Channel"
    :message="'Delete ' + deletingChannel?.name + '?'"
    @confirm="doDelete"
    @cancel="confirmDelete = false"
  />

</template>

<script setup lang="ts">
import LoadingOverlay from '~com/LoadingOverlay.vue'
import { ref, onMounted, watch } from 'vue'
import { api, type NotificationChannel } from '~lib/api'
import { useChannelStore } from '~stores/channels'
import { showNotification } from '~stores/app'
import { keyVersion } from '~stores/auth'
import ChannelForm from '~com/ChannelForm.vue'
import ConfirmDialog from '~com/ConfirmDialog.vue'

const channelStore = useChannelStore()
const showForm = ref(false)
const editingChannel = ref<NotificationChannel | null>(null)
const confirmDelete = ref(false)
const deletingChannel = ref<NotificationChannel | null>(null)

const sendingId = ref<number | null>(null)

const showTestResult = ref(false)
const testOk = ref(true)
const testError = ref('')
const testResp = ref<{ name: string; type: string; response?: any; error?: string }>({ name: '', type: '' })
const testRequestBody = ref('')

const typeLabels: Record<string, string> = {
  webhook: 'Webhook', discord: 'Discord', slack: 'Slack',
  ntfy: 'NTFY', email: 'Email',
}

function typeLabel(type: string): string {
  return typeLabels[type] || type
}

function openAdd() {
  editingChannel.value = null
  showForm.value = true
}

function openEdit(ch: NotificationChannel) {
  editingChannel.value = ch
  showForm.value = true
}

async function toggleChannel(ch: NotificationChannel) {
  const newVal = ch.enabled ? 0 : 1
  try {
    await channelStore.toggleEnabled(ch.id, newVal)
    showNotification(newVal ? 'Channel enabled' : 'Channel disabled', 'success')
  } catch (e: any) {
    showNotification(e.message, 'error')
  }
}

async function deleteChannel(ch: NotificationChannel) {
  deletingChannel.value = ch
  confirmDelete.value = true
}

async function doDelete() {
  if (!deletingChannel.value) return
  try {
    await channelStore.remove(deletingChannel.value.id)
    showNotification('Channel deleted', 'success')
    deletingChannel.value = null
    confirmDelete.value = false
  } catch (e: any) {
    showNotification(e.message, 'error')
  }
}

async function testChannel(ch: NotificationChannel) {
  const body = { message: 'Test notification from PULSE' }
  sendingId.value = ch.id
  testRequestBody.value = JSON.stringify(body, null, 2)
  try {
    const resp = await api.testChannel(ch.id, body.message)
    testOk.value = !resp.error
    testError.value = resp.error || ''
    testResp.value = resp
  } catch (e: any) {
    testOk.value = false
    testError.value = e.message
    testResp.value = { name: ch.name, type: ch.type, response: null }
  } finally {
    sendingId.value = null
    showTestResult.value = true
  }
}

function onSaved() {
  showForm.value = false
  editingChannel.value = null
}

watch(keyVersion, () => { channelStore.load() })

onMounted(() => { channelStore.load() })
</script>

<style scoped>
.loading, .empty {
  @apply flex flex-col items-center justify-center h-[40vh] text-[var(--text-muted)] gap-3;
}

.channel-list {
  @apply flex flex-col gap-2;
}

.channel-row {
  @apply flex items-center justify-between bg-[var(--surface)] border border-[var(--border)] rounded-xl px-5 py-4;
  gap: 12px;
}



.channel-info {
  @apply flex items-center gap-3 flex-1 min-w-0;
}

.channel-name {
  @apply text-sm font-medium;
}

.type-badge {
  @apply text-[11px] px-2 py-0.5 rounded-full font-medium;

  &.webhook { background: color-mix(in srgb, var(--accent) 10%, transparent); color: var(--accent); }
  &.discord { background: color-mix(in srgb, #5865f2 10%, transparent); color: #5865f2; }
  &.slack { background: color-mix(in srgb, #e01e5a 10%, transparent); color: #e01e5a; }
  &.ntfy { background: color-mix(in srgb, #22c55e 10%, transparent); color: #22c55e; }
  &.email { background: color-mix(in srgb, var(--up) 10%, transparent); color: var(--up); }
}

.channel-actions {
  @apply flex items-center gap-2;
}

.btn-test {
  @apply inline-flex items-center gap-1 px-3 py-1 border border-[var(--border)] rounded-lg text-[12px] cursor-pointer transition-all duration-150 bg-transparent text-[var(--text-muted)];

  &:hover:not(:disabled) { @apply border-[var(--accent)] text-[var(--accent)]; }
  &:disabled { @apply opacity-50 cursor-not-allowed; }
}

.btn-ghost-sm {
  @apply inline-flex items-center px-2 py-1 border-none bg-transparent text-[var(--text-muted)] text-[12px] cursor-pointer rounded-lg;
  transition: color 0.15s;

  &:hover { @apply text-[var(--text)]; }
  &.danger:hover { @apply text-[var(--down)]; }
}

.result-modal {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  width: 100%;
  max-width: 420px;
  box-shadow: 0 25px 50px -12px rgba(0,0,0,0.4);
  margin: 0 1rem;
  overflow: hidden;
}

.result-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 16px 20px;
  border-bottom: 1px solid var(--border);
}

.result-icon { font-size: 18px; display: flex; }
.result-icon.ok { color: var(--up); }
.result-icon.fail { color: var(--down); }

.result-title {
  font-size: 15px;
  font-weight: 600;
  flex: 1;
}

.result-close {
  font-size: 22px;
  color: var(--text-muted);
  background: transparent;
  border: none;
  cursor: pointer;
  line-height: 1;
  padding: 0;
}
.result-close:hover { color: var(--text); }

.result-body {
  padding: 16px 20px 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.result-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.result-label {
  font-size: 11px;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.result-code {
  font-size: 12px;
  color: var(--text-muted);
  background: var(--base);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 10px 12px;
  overflow-x: auto;
  margin: 0;
  font-family: 'Menlo', 'Monaco', monospace;
  line-height: 1.5;
}

.result-value {
  font-size: 13px;
  color: var(--text);
}

.result-value.fail {
  color: var(--down);
}

.result-badge {
  font-weight: 600;
  margin-right: 4px;
}

.result-badge.ok { color: var(--up); }
.result-badge.fail { color: var(--down); }
</style>
