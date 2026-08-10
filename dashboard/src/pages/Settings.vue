<template>
  <header class="topbar">
    <h1 class="title">
      <span class="i-mdi-cog-outline text-[var(--accent)] mr-2" />
      Settings
    </h1>
  </header>

  <div class="content">
    <div class="settings-card">
      <div class="field">
        <label class="label">Instance Name</label>
        <input class="input" :class="{ invalid: errors.name }" v-model="instanceName" placeholder="PULSE" @input="clearError('name')" />
        <span class="help-text">Used in alert payloads and email subjects.</span>
        <span v-if="errors.name" class="field-error">{{ errors.name }}</span>
      </div>

      <div class="field-row">
        <div class="field flex-1">
          <label class="label">Retention Days</label>
          <input class="input" :class="{ invalid: errors.retention }" v-model.number="retentionDays" type="number" min="1" @input="clearError('retention')" />
          <span v-if="errors.retention" class="field-error">{{ errors.retention }}</span>
        </div>
        <div class="field flex-1">
          <label class="label">Alert Cooldown (sec)</label>
          <input class="input" :class="{ invalid: errors.cooldown }" v-model.number="cooldownSec" type="number" min="0" @input="clearError('cooldown')" />
          <span v-if="errors.cooldown" class="field-error">{{ errors.cooldown }}</span>
        </div>
      </div>

      <div class="field">
        <label class="label">Certificate Expiry Threshold (days)</label>
        <input class="input" v-model.number="certThresholdDays" type="number" min="1" max="365" />
        <span class="help-text">Default threshold for certificate expiry alerts. Can be overridden per monitor.</span>
      </div>

      <div class="field">
        <label class="checkbox-label">
          <input type="checkbox" v-model="treat4xx" />
          <span class="i-mdi-shield-alert" />
          Treat 4xx responses as DOWN
        </label>
        <span class="help-text">When enabled, 4xx (blocked) status codes count as down. Default is to treat 4xx as up (blocked).</span>
      </div>

      <button class="btn-primary mt-4" @click="saveSettings">Save</button>
    </div>

    <div v-if="nodeRole === 'central'" class="settings-card mt-4">
      <h2 class="card-title">Cluster</h2>
      <div class="field-row">
        <div class="field flex-1">
          <label class="label">Consensus Min Nodes</label>
          <input class="input" v-model.number="consensusMinNodes" type="number" min="1" />
          <span class="help-text">Minimum live nodes required before consensus is evaluated.</span>
        </div>
        <div class="field flex-1">
          <label class="label">Consensus Quorum (%)</label>
          <input class="input" v-model.number="consensusQuorumPct" type="number" min="1" max="100" />
          <span class="help-text">Percentage of live nodes that must agree.</span>
        </div>
      </div>
      <div class="field">
        <label class="label">Node Liveness (sec)</label>
        <input class="input" v-model.number="nodeLivenessSec" type="number" min="10" />
        <span class="help-text">How long without contact before a node is considered dead and excluded from consensus.</span>
      </div>
      <button class="btn-primary mt-4" @click="saveSettings">Save</button>
    </div>

  </div>
</template>

<script setup lang="ts">
defineOptions({ layout: 'default' })

import { ref, reactive, onMounted, watch } from 'vue'
import { api } from '~lib/api'
import { keyVersion } from '~stores/auth'
import { nodeRole, showNotification } from '~stores/app'
import { isNonEmpty } from '~lib/validators'

const instanceName = ref('')
const retentionDays = ref(90)
const cooldownSec = ref(300)
const certThresholdDays = ref(14)
const treat4xx = ref(false)
const nodeLivenessSec = ref(90)
const consensusMinNodes = ref(2)
const consensusQuorumPct = ref(51)

const errors = reactive<Record<string, string>>({})

function clearError(field: string) {
  delete errors[field]
}

watch(keyVersion, () => {
  loadSettings()
})

async function loadSettings() {
  try {
    const s = await api.getSettings()
    instanceName.value = s.instance_name || 'PULSE'
    retentionDays.value = parseInt(s.retention_days) || 90
    cooldownSec.value = parseInt(s.alert_cooldown_sec) || 300
    certThresholdDays.value = parseInt(s.cert_threshold_days) || 14
    treat4xx.value = s.treat_4xx_as_down === '1'
    nodeLivenessSec.value = parseInt(s.node_liveness_sec) || 90
    consensusMinNodes.value = parseInt(s.consensus_min_nodes) || 2
    consensusQuorumPct.value = parseInt(s.consensus_quorum_pct) || 51
  } catch (e: any) {
    console.error('Failed to load settings:', e.message)
  }
}

function validate(): boolean {
  Object.keys(errors).forEach(k => delete errors[k])

  if (!isNonEmpty(instanceName.value)) errors.name = 'Instance name is required'

  const days = Number(retentionDays.value)
  if (!Number.isInteger(days) || days < 1) errors.retention = 'Must be at least 1'

  const cooldown = Number(cooldownSec.value)
  if (!Number.isInteger(cooldown) || cooldown < 0) errors.cooldown = 'Must be 0 or more'

  return Object.keys(errors).length === 0
}

async function saveSettings() {
  if (!validate()) return

  const data: Record<string, string> = {
    instance_name: instanceName.value,
    retention_days: String(retentionDays.value),
    alert_cooldown_sec: String(cooldownSec.value),
    cert_threshold_days: String(certThresholdDays.value),
    treat_4xx_as_down: treat4xx.value ? '1' : '0',
  }

  if (nodeRole.value === 'central') {
    data.consensus_min_nodes = String(consensusMinNodes.value)
    data.consensus_quorum_pct = String(consensusQuorumPct.value)
    data.node_liveness_sec = String(nodeLivenessSec.value)
  }

  try {
    await api.updateSettings(data)
    showNotification('Settings saved', 'success')
  } catch (e: any) {
    showNotification(e.message || 'Failed to save settings', 'error')
  }
}

onMounted(() => {
  loadSettings()
})
</script>

<style scoped>
.settings-card {
  @apply bg-[var(--surface)] border border-[var(--border)] rounded-xl p-6 max-w-[480px];
}

.card-title {
  @apply text-base font-semibold mb-4;
}

.help-text {
  @apply text-xs text-[var(--text-muted)] mt-1.5;
}

</style>
