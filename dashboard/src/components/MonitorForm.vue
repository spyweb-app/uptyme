<template>
  <div class="modal-overlay">
    <div class="modal">
      <div class="modal-header">
        <h2 class="modal-title">{{ isEdit ? 'Edit Monitor' : 'Add Monitor' }}</h2>
        <button class="close-btn" @click="$emit('close')">&times;</button>
      </div>

      <form class="modal-body" @submit.prevent="save">
        <div class="field">
          <label class="label">Name</label>
          <input class="input" :class="{ invalid: errors.name }" v-model="form.name" placeholder="My Website" @input="clearError('name')" @blur="validateField('name')" />
          <span v-if="errors.name" class="field-error">{{ errors.name }}</span>
        </div>

        <div class="field">
          <label class="label">URL</label>
          <input class="input" :class="{ invalid: errors.url }" v-model="form.url" placeholder="https://example.com" @input="onUrlInput" @blur="validateField('url')" />
          <span v-if="errors.url" class="field-error">{{ errors.url }}</span>
        </div>

        <div v-if="showCertOption" class="field">
          <label class="checkbox-label">
            <input type="checkbox" v-model="form.check_cert" :true-value="1" :false-value="0" />
            <span class="i-mdi-certificate" />
            Check certificate
          </label>
          <span class="field-hint">Probe TLS certificate expiry. Alerts when certificate expires within threshold.</span>
        </div>

        <div v-if="form.check_cert === 1" class="field">
          <label class="label">Cert threshold (days)</label>
          <input class="input" v-model.number="form.cert_threshold_days" type="number" min="1" max="365" />
          <span class="field-hint">Alert when certificate expires within this many days.</span>
        </div>

        <div class="advanced-toggle" @click="showAdvanced = !showAdvanced">
          <span class="advanced-arrow" :class="{ open: showAdvanced }">&#9654;</span>
          Advanced
        </div>

        <div v-if="showAdvanced" class="advanced-section">
          <div class="field-row triple">
            <div class="field flex-1">
              <label class="label">Method</label>
              <select class="input" v-model="form.method">
                <option>GET</option>
                <option>HEAD</option>
                <option>POST</option>
              </select>
            </div>
            <div class="field flex-1">
              <label class="label">Interval (s)</label>
              <input class="input" :class="{ invalid: errors.interval_sec }" v-model.number="form.interval_sec" type="number" min="10" @input="clearError('interval_sec')" @blur="validateField('interval_sec')" />
              <span v-if="errors.interval_sec" class="field-error">{{ errors.interval_sec }}</span>
            </div>
            <div class="field flex-1">
              <label class="label">Timeout (ms)</label>
              <input class="input" :class="{ invalid: errors.timeout_ms }" v-model.number="form.timeout_ms" type="number" min="1000" @input="clearError('timeout_ms')" @blur="validateField('timeout_ms')" />
              <span v-if="errors.timeout_ms" class="field-error">{{ errors.timeout_ms }}</span>
            </div>
          </div>

          <div class="field">
            <label class="label">
              <span class="i-mdi-text-search" />
              Content Check
            </label>
            <input class="input" v-model="form.check_value" placeholder='e.g. &lt;body, class="price", Welcome' />
            <span class="field-hint">Optional. Fetches with GET when set. Marked DOWN if text not found in page body.</span>
          </div>

          <div v-if="!headless" class="field">
            <label class="checkbox-label">
              <input type="checkbox" v-model="form.desktop_notify" :true-value="1" :false-value="0" />
              <span class="i-mdi-bell-ring" />
              Desktop notifications
            </label>
          </div>

          <div v-if="channels.length" class="field">
            <label class="label">
              <span class="i-mdi-bell-ring-outline" />
              Channel Notifications
            </label>
            <div class="channel-checkboxes">
              <label v-for="ch in channels" :key="ch.id" class="channel-checkbox">
                <input type="checkbox" :value="ch.id" v-model="selectedChannelIds" />
                <span v-if="ch.type === 'webhook'" class="i-mdi-webhook" />
                <span v-else-if="ch.type === 'discord'" class="i-mdi-discord text-[#5865f2]" />
                <span v-else-if="ch.type === 'slack'" class="i-mdi-slack text-[#e01e5a]" />
                <span v-else-if="ch.type === 'ntfy'" class="i-mdi-bell-ring text-[#22c55e]" />
                <span v-else-if="ch.type === 'email'" class="i-mdi-email-outline text-[var(--up)]" />
                {{ ch.name }}
              </label>
            </div>
          </div>
        </div>

        <div class="modal-actions">
          <button type="button" class="btn-ghost" @click="$emit('close')">Cancel</button>
          <button type="submit" class="btn-primary" :disabled="saving">
            {{ saving ? 'Saving...' : isEdit ? 'Save Changes' : 'Add Monitor' }}
          </button>
        </div>

        <div v-if="saveError" class="save-error">{{ saveError }}</div>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { api, type Monitor, type NotificationChannel } from '~lib/api'
import { useMonitorStore } from '~stores/monitors'
import { isValidURL, isNonEmpty } from '~lib/validators'

const props = defineProps<{
  monitor?: Monitor | null
}>()

const emit = defineEmits<{
  close: []
  saved: []
}>()

const store = useMonitorStore()
const isEdit = !!props.monitor
const saving = ref(false)
const saveError = ref('')
const headless = ref(false)
const showCertOption = ref(isEdit && (props.monitor?.url || '').startsWith('https://'))

const showAdvanced = ref(isEdit && (
  (props.monitor?.method && props.monitor.method !== 'HEAD') ||
  props.monitor?.interval_sec !== 300 ||
  props.monitor?.timeout_ms !== 10000 ||
  !!props.monitor?.check_value ||
  !!props.monitor?.desktop_notify ||
  !!props.monitor?.check_cert
))

const errors = reactive<Record<string, string>>({})

function clearError(field: string) {
  delete errors[field]
}

const rules: Record<string, { test: (v: any) => boolean; message: string }> = {
  name: { test: (v: string) => isNonEmpty(v), message: 'Name is required' },
  url: { test: (v: string) => isValidURL(v), message: 'Enter a valid URL (https://...)' },
  interval_sec: { test: (v: number) => { const n = Number(v); return n >= 10 && n <= 86400 }, message: 'Must be between 10 and 86400' },
  timeout_ms: { test: (v: number) => { const n = Number(v); return n >= 1000 && n <= 60000 }, message: 'Must be between 1000 and 60000' },
}

function validateField(field: string) {
  const rule = rules[field]
  if (rule && !rule.test((form as any)[field])) errors[field] = rule.message
  else delete errors[field]
}

function onUrlInput() {
  clearError('url')
  const isHttps = form.url.startsWith('https://')
  showCertOption.value = isHttps
  if (!isHttps) {
    form.check_cert = 0
  }
}

const channels = ref<NotificationChannel[]>([])
const selectedChannelIds = ref<number[]>([])

const form = reactive({
  name: props.monitor?.name || '',
  url: props.monitor?.url || '',
  method: props.monitor?.method || 'HEAD',
  interval_sec: props.monitor?.interval_sec || 300,
  timeout_ms: props.monitor?.timeout_ms || 10000,
  check_value: props.monitor?.check_value || '',
  desktop_notify: props.monitor?.desktop_notify ?? 0,
  check_cert: props.monitor?.check_cert ?? 0,
  cert_threshold_days: props.monitor?.cert_threshold_days || 14,
})

async function loadChannels() {
  try {
    channels.value = await api.listChannels()
    if (isEdit && props.monitor) {
      selectedChannelIds.value = await api.getMonitorChannels(props.monitor.id)
    }
  } catch (e: any) {
    console.error('Failed to load channels:', e.message)
  }
}

function validate() {
  Object.keys(rules).forEach(validateField)
  return Object.keys(errors).length === 0
}

async function save() {
  if (!validate()) return
  saving.value = true
  saveError.value = ''
  try {
    if (isEdit && props.monitor) {
      await store.update(props.monitor.id, form)
      await store.setChannels(props.monitor.id, selectedChannelIds.value)
    } else {
      const mon = await store.create(form)
      if (selectedChannelIds.value.length) {
        await store.setChannels(mon.id, selectedChannelIds.value)
      }
    }
    emit('saved')
  } catch (e: any) {
    saveError.value = e.message
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  loadChannels()
  try {
    const health = await api.getHealth()
    headless.value = health.headless
  } catch (e) {
    console.error('Failed to fetch health:', e)
  }
})
</script>

<style scoped>
.advanced-toggle {
  @apply flex items-center gap-2 text-[13px] text-[var(--text-muted)] cursor-pointer select-none py-2 mb-1;
  transition: color 0.15s;

  &:hover { @apply text-[var(--text)]; }
}

.advanced-arrow {
  @apply text-[10px] transition-transform duration-150;

  &.open { transform: rotate(90deg); }
}

.advanced-section {
  @apply p-4 mb-4 rounded-lg;
  background: rgba(255,255,255,0.02);
  border: 1px solid var(--border);
}

.channel-checkboxes {
  @apply flex flex-wrap gap-3 mt-1;
}

.channel-checkbox {
  @apply flex items-center gap-1.5 text-[13px] text-[var(--text-secondary)] cursor-pointer select-none;

  & input { @apply accent-[var(--accent)]; }
}


</style>
