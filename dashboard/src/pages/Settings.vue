<template>
  <form class="settings-page" @submit.prevent="saveSettings">
    <header class="topbar">
      <h1 class="title">
        <span class="i-mdi-cog-outline text-[var(--accent)] mr-2" />
        Settings
      </h1>

      <div class="topbar-actions">
        <span v-if="isDirty && !loading" class="dirty-badge">
          <span class="i-mdi-circle-medium" />
          Unsaved changes
        </span>
        <button v-if="isDirty && !loading" type="button" class="btn-ghost" @click="discard">
          Discard
        </button>
        <button type="submit" class="btn-primary" :disabled="loading || saving || !isDirty">
          <span v-if="saving" class="i-mdi-loading animate-spin mr-1" />
          {{ saving ? 'Saving...' : 'Save Changes' }}
        </button>
      </div>
    </header>

    <div class="content">
      <div class="settings-wrap">
        <section class="settings-card">
          <div class="card-head">
            <span class="card-icon"><span class="i-mdi-tune-variant" /></span>
            <div class="card-head-text">
              <h2 class="card-title">General</h2>
              <p class="card-desc">Instance identity, data retention and alert behaviour.</p>
            </div>
          </div>

          <div class="card-body">
            <div class="field field-full">
              <label class="label" for="instance-name">Instance Name</label>
              <input id="instance-name" class="input" :class="{ invalid: errors.name }" v-model="instanceName" :placeholder="currentInstanceName" maxlength="100" @input="clearError('name')" />
              <span class="help-text">Used in alert payloads and email subjects.</span>
              <span v-if="errors.name" class="field-error">{{ errors.name }}</span>
            </div>

            <div class="field">
              <label class="label" for="retention-days">Retention Days</label>
              <input id="retention-days" class="input" :class="{ invalid: errors.retention }" v-model.number="retentionDays" type="number" min="1" max="3650" @input="clearError('retention')" />
              <span class="help-text">How long check history is kept.</span>
              <span v-if="errors.retention" class="field-error">{{ errors.retention }}</span>
            </div>

            <div class="field">
              <label class="label" for="alert-cooldown">Alert Cooldown (sec)</label>
              <input id="alert-cooldown" class="input" :class="{ invalid: errors.cooldown }" v-model.number="cooldownSec" type="number" min="60" max="86400" @input="clearError('cooldown')" />
              <span class="help-text">Minimum time between repeat alerts.</span>
              <span v-if="errors.cooldown" class="field-error">{{ errors.cooldown }}</span>
            </div>

            <div class="field field-full">
              <label class="label" for="cert-threshold">Certificate Expiry Threshold (days)</label>
              <input id="cert-threshold" class="input" :class="{ invalid: errors.certThreshold }" v-model.number="certThresholdDays" type="number" min="1" max="365" @input="clearError('certThreshold')" />
              <span class="help-text">Default threshold for certificate expiry alerts. Can be overridden per monitor.</span>
              <span v-if="errors.certThreshold" class="field-error">{{ errors.certThreshold }}</span>
            </div>

            <div class="switch-row field-full">
              <div class="switch-text">
                <span class="switch-label">Treat 4xx responses as DOWN</span>
                <span class="switch-help">When off, 4xx (blocked) status codes count as up.</span>
              </div>
              <label class="toggle">
                <input type="checkbox" v-model="treat4xx" />
                <span class="toggle-slider"></span>
              </label>
            </div>
          </div>
        </section>

        <section v-if="isCentral" class="settings-card">
          <div class="card-head">
            <span class="card-icon cluster"><span class="i-mdi-server-network" /></span>
            <div class="card-head-text">
              <h2 class="card-title">Cluster</h2>
              <p class="card-desc">Consensus behaviour, applied only while this node runs as central.</p>
            </div>
          </div>

          <div class="card-body">
            <div class="field">
              <label class="label" for="consensus-min-nodes">Consensus Min Nodes</label>
              <input id="consensus-min-nodes" class="input" :class="{ invalid: errors.consensusMinNodes }" v-model.number="consensusMinNodes" type="number" min="1" max="100" @input="clearError('consensusMinNodes')" />
              <span class="help-text">Minimum live nodes required before consensus is evaluated.</span>
              <span v-if="errors.consensusMinNodes" class="field-error">{{ errors.consensusMinNodes }}</span>
            </div>

            <div class="field">
              <label class="label" for="consensus-quorum">Consensus Quorum (%)</label>
              <input id="consensus-quorum" class="input" :class="{ invalid: errors.consensusQuorumPct }" v-model.number="consensusQuorumPct" type="number" min="1" max="100" @input="clearError('consensusQuorumPct')" />
              <span class="help-text">Share of live nodes that must agree.</span>
              <span v-if="errors.consensusQuorumPct" class="field-error">{{ errors.consensusQuorumPct }}</span>
            </div>

            <div class="field field-full">
              <label class="label" for="node-liveness">Node Liveness (sec)</label>
              <input id="node-liveness" class="input" :class="{ invalid: errors.nodeLiveness }" v-model.number="nodeLivenessSec" type="number" min="30" max="3600" @input="clearError('nodeLiveness')" />
              <span class="help-text">How long without contact before a node is considered dead and excluded from consensus.</span>
              <span v-if="errors.nodeLiveness" class="field-error">{{ errors.nodeLiveness }}</span>
            </div>

            <div class="switch-row field-full">
              <div class="switch-text">
                <span class="switch-label">Checker no-contact alert</span>
                <span class="switch-help">Alert when an active checker has not contacted this node for its per-node alert window.</span>
              </div>
              <label class="toggle">
                <input type="checkbox" v-model="checkerStaleAlert" />
                <span class="toggle-slider"></span>
              </label>
            </div>

            <div class="field field-full">
              <label class="label" for="checker-stale-channel">Alert Channel</label>
              <select id="checker-stale-channel" class="input" v-model.number="checkerStaleChannelId" :disabled="enabledChannels.length === 0">
                <option :value="0" disabled>Select channel</option>
                <option v-for="ch in enabledChannels" :key="ch.id" :value="ch.id">{{ ch.name }}</option>
              </select>
              <span class="help-text">{{ enabledChannels.length === 0 ? 'No notification channels found.' : 'Where the checker no-contact alert is sent.' }}</span>
            </div>
          </div>
        </section>

        <section class="settings-card">
          <div class="card-head">
            <span class="card-icon status-page"><span class="i-mdi-web-box" /></span>
            <div class="card-head-text">
              <h2 class="card-title">Status Pages</h2>
              <p class="card-desc">Defaults applied to newly created public pages.</p>
            </div>
          </div>

          <div class="card-body">
            <div class="field field-full">
              <label class="label" for="slug-style">Slug Style</label>
              <select id="slug-style" class="input" v-model="statusPageSlugStyle">
                <option value="name_random">Name + Random (us-api-x7q2)</option>
                <option value="random">Random Only (x7q2m)</option>
              </select>
              <span class="help-text">How slugs are generated for new status pages. Slugs are immutable once created.</span>
            </div>

            <div class="field">
              <label class="label" for="slug-random-length">Random Length</label>
              <input id="slug-random-length" class="input" :class="{ invalid: errors.slugRandomLength }" v-model.number="statusPageRandomLength" type="number" min="3" max="10" @input="clearError('slugRandomLength')" />
              <span class="help-text">Length of the random suffix.</span>
              <span v-if="errors.slugRandomLength" class="field-error">{{ errors.slugRandomLength }}</span>
            </div>

            <div class="field">
              <label class="label" for="slug-name-max">Name Max Length</label>
              <input id="slug-name-max" class="input" :class="{ invalid: errors.slugNameMaxLength }" v-model.number="statusPageNameMaxLength" type="number" min="5" max="50" @input="clearError('slugNameMaxLength')" />
              <span class="help-text">Max characters for the name prefix.</span>
              <span v-if="errors.slugNameMaxLength" class="field-error">{{ errors.slugNameMaxLength }}</span>
            </div>

            <div class="field field-full">
              <span class="label">Theme</span>
              <div class="segmented">
                <button type="button" class="seg-btn" :class="{ active: statusPageTheme === 'light' }" @click="statusPageTheme = 'light'">
                  <span class="i-mdi-weather-sunny" />
                  Light
                </button>
                <button type="button" class="seg-btn" :class="{ active: statusPageTheme === 'dark' }" @click="statusPageTheme = 'dark'">
                  <span class="i-mdi-weather-night" />
                  Dark
                </button>
              </div>
              <span class="help-text">Default theme for all public status pages.</span>
            </div>
          </div>
        </section>
      </div>
    </div>
  </form>
</template>

<script setup lang="ts">
defineOptions({ layout: 'default' })

import { ref, reactive, computed, onMounted } from 'vue'
import { api, type Settings } from '~lib/api'
import { nodeRole, showNotification, setInstanceName, instanceName as currentInstanceName } from '~stores/app'
import { useChannelStore } from '~stores/channels'
import { isNonEmpty } from '~lib/validators'

// state
const instanceName = ref('')
const retentionDays = ref(90)
const cooldownSec = ref(300)
const certThresholdDays = ref(14)
const treat4xx = ref(false)
const nodeLivenessSec = ref(90)
const consensusMinNodes = ref(2)
const consensusQuorumPct = ref(51)
const statusPageSlugStyle = ref('name_random')
const statusPageRandomLength = ref(5)
const statusPageNameMaxLength = ref(20)
const statusPageTheme = ref('light')
const checkerStaleAlert = ref(false)
const checkerStaleChannelId = ref(0)
const channelStore = useChannelStore()
const loading = ref(true)
const saving = ref(false)
const errors = reactive<Record<string, string>>({})

// last values applied from the server, used to detect and discard edits
const lastLoaded = ref<Settings | null>(null)
const baseline = ref('')

// derived
const isCentral = computed(() => nodeRole.value === 'central')
const enabledChannels = computed(() => channelStore.channels.filter(c => c.enabled === 1))

function snapshot(): string {
  return JSON.stringify([
    instanceName.value,
    Number(retentionDays.value),
    Number(cooldownSec.value),
    Number(certThresholdDays.value),
    treat4xx.value,
    Number(nodeLivenessSec.value),
    Number(consensusMinNodes.value),
    Number(consensusQuorumPct.value),
    statusPageSlugStyle.value,
    Number(statusPageRandomLength.value),
    Number(statusPageNameMaxLength.value),
    statusPageTheme.value,
    checkerStaleAlert.value,
    Number(checkerStaleChannelId.value),
  ])
}

const isDirty = computed(() => baseline.value !== snapshot())

// helpers
function clearError(field: string) {
  delete errors[field]
}

function checkRange(field: string, value: number, min: number, max: number, label: string) {
  if (!Number.isInteger(value) || value < min || value > max) {
    errors[field] = `${label} must be between ${min} and ${max}`
  }
}

function validate(): boolean {
  Object.keys(errors).forEach(k => delete errors[k])

  if (!isNonEmpty(instanceName.value)) errors.name = 'Instance name is required'
  else if (instanceName.value.length > 100) errors.name = 'Instance name must be at most 100 characters'

  checkRange('retention', Number(retentionDays.value), 1, 3650, 'Retention days')
  checkRange('cooldown', Number(cooldownSec.value), 60, 86400, 'Alert cooldown')
  checkRange('certThreshold', Number(certThresholdDays.value), 1, 365, 'Certificate threshold')
  checkRange('slugRandomLength', Number(statusPageRandomLength.value), 3, 10, 'Random length')
  checkRange('slugNameMaxLength', Number(statusPageNameMaxLength.value), 5, 50, 'Name max length')

  if (isCentral.value) {
    checkRange('consensusMinNodes', Number(consensusMinNodes.value), 1, 100, 'Consensus min nodes')
    checkRange('consensusQuorumPct', Number(consensusQuorumPct.value), 1, 100, 'Consensus quorum')
    checkRange('nodeLiveness', Number(nodeLivenessSec.value), 30, 3600, 'Node liveness')
  }

  return Object.keys(errors).length === 0
}

// lifecycle
function applySettings(s: Settings) {
  instanceName.value = s.instance_name || 'UPTYME'
  retentionDays.value = parseInt(s.retention_days) || 90
  cooldownSec.value = parseInt(s.alert_cooldown_sec) || 300
  certThresholdDays.value = parseInt(s.cert_threshold_days) || 14
  treat4xx.value = s.treat_4xx_as_down === '1'
  nodeLivenessSec.value = parseInt(s.node_liveness_sec) || 90
  consensusMinNodes.value = parseInt(s.consensus_min_nodes) || 2
  consensusQuorumPct.value = parseInt(s.consensus_quorum_pct) || 51
  statusPageSlugStyle.value = s.status_page_slug_style || 'name_random'
  statusPageRandomLength.value = parseInt(s.status_page_random_length) || 5
  statusPageNameMaxLength.value = parseInt(s.status_page_name_max_length) || 20
  statusPageTheme.value = s.status_page_theme || 'light'
  checkerStaleAlert.value = s.checker_stale_alert === '1'
  checkerStaleChannelId.value = parseInt(s.checker_stale_channel_id) || 0
}

async function loadSettings() {
  loading.value = true
  try {
    const s = await api.getSettings()
    lastLoaded.value = s
    applySettings(s)
    baseline.value = snapshot()
  } catch (e: any) {
    console.error('Failed to load settings:', e.message)
  } finally {
    loading.value = false
  }
}

function discard() {
  if (lastLoaded.value) applySettings(lastLoaded.value)
  Object.keys(errors).forEach(k => delete errors[k])
}

async function saveSettings() {
  if (!validate()) {
    showNotification('Please fix the highlighted fields', 'error')
    return
  }

  const data: Record<string, string> = {
    instance_name: instanceName.value,
    retention_days: String(retentionDays.value),
    alert_cooldown_sec: String(cooldownSec.value),
    cert_threshold_days: String(certThresholdDays.value),
    treat_4xx_as_down: treat4xx.value ? '1' : '0',
    status_page_slug_style: statusPageSlugStyle.value,
    status_page_random_length: String(statusPageRandomLength.value),
    status_page_name_max_length: String(statusPageNameMaxLength.value),
    status_page_theme: statusPageTheme.value,
  }

  if (isCentral.value) {
    data.consensus_min_nodes = String(consensusMinNodes.value)
    data.consensus_quorum_pct = String(consensusQuorumPct.value)
    data.node_liveness_sec = String(nodeLivenessSec.value)
    data.checker_stale_alert = checkerStaleAlert.value ? '1' : '0'
    data.checker_stale_channel_id = String(checkerStaleChannelId.value)
  }

  saving.value = true
  try {
    await api.updateSettings(data)
    lastLoaded.value = { ...lastLoaded.value, ...data }
    baseline.value = snapshot()
    setInstanceName(instanceName.value)
    showNotification('Settings saved', 'success')
  } catch (e: any) {
    showNotification(e.message || 'Failed to save settings', 'error')
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  loadSettings()
  if (isCentral.value) channelStore.load()
})
</script>

<style scoped>
.settings-page {
  @apply flex-1 flex flex-col overflow-hidden;
}

.topbar-actions {
  @apply flex items-center gap-3;
}

.dirty-badge {
  @apply inline-flex items-center gap-1 text-[11px] font-medium px-2.5 py-1 rounded-full text-[var(--blocked)];
  background: color-mix(in srgb, var(--blocked) 12%, transparent);
}

.dirty-badge .i-mdi-circle-medium {
  @apply text-[8px];
}

.settings-wrap {
  @apply max-w-[880px] mx-auto flex flex-col gap-4;
}

.settings-card {
  @apply bg-[var(--surface)] border border-[var(--border)] rounded-xl overflow-hidden;
}

.card-head {
  @apply flex items-start gap-3 px-6 py-5 border-b border-[var(--border)];
}

.card-icon {
  @apply flex-shrink-0 w-9 h-9 rounded-lg flex items-center justify-center text-lg;
  background: color-mix(in srgb, var(--accent) 12%, transparent);
  color: var(--accent);

  &.cluster {
    background: color-mix(in srgb, var(--up) 12%, transparent);
    color: var(--up);
  }

  &.status-page {
    background: color-mix(in srgb, var(--blocked) 12%, transparent);
    color: var(--blocked);
  }
}

.card-head-text {
  @apply min-w-0;
}

.card-title {
  @apply text-[15px] font-semibold leading-tight;
}

.card-desc {
  @apply text-xs text-[var(--text-muted)] mt-1;
}

.card-body {
  @apply grid grid-cols-1 md:grid-cols-2 gap-x-5 gap-y-5 px-6 py-5;
}

.field {
  @apply mb-0;
}

.field-full {
  @apply md:col-span-2;
}

.help-text {
  @apply block text-[11px] text-[var(--text-muted)] mt-1.5 leading-relaxed;
}

.switch-row {
  @apply flex items-center justify-between gap-4 rounded-lg border border-[var(--border)] px-4 py-3;
  background: var(--elevated);
}

.switch-text {
  @apply min-w-0;
}

.switch-label {
  @apply block text-sm font-medium text-[var(--text)];
}

.switch-help {
  @apply block text-[11px] text-[var(--text-muted)] mt-0.5;
}

.segmented {
  @apply inline-flex gap-1 p-1 rounded-lg border border-[var(--border)] w-fit;
  background: var(--input);
}

.seg-btn {
  @apply inline-flex items-center gap-2 px-4 py-1.5 rounded-md text-[13px] border-none cursor-pointer transition-all duration-150;
  background: transparent;
  color: var(--text-secondary);

  &:hover {
    color: var(--text);
  }

  &.active {
    color: var(--accent);
    background: color-mix(in srgb, var(--accent) 12%, transparent);
  }
}

@media (max-width: 600px) {
  .topbar {
    @apply flex-wrap gap-y-3 px-4;
  }

  .card-head,
  .card-body {
    @apply px-4;
  }

  .dirty-badge {
    @apply hidden;
  }
}
</style>
