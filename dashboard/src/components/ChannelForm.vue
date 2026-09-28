<template>
  <div class="modal-overlay">
    <div class="modal">
      <div class="modal-header">
        <h2 class="modal-title">{{ isEdit ? 'Edit Channel' : 'Add Channel' }}</h2>
        <button class="close-btn" @click="$emit('close')">&times;</button>
      </div>

      <form class="modal-body" @submit.prevent="save">
        <div class="field">
          <label class="label">Name</label>
          <input class="input" :class="{ invalid: errors.name }" v-model="form.name" placeholder="My Channel" @input="clearError('name')" @blur="validateField('name')" />
          <span v-if="errors.name" class="field-error">{{ errors.name }}</span>
        </div>

        <div class="field">
          <label class="label">Type</label>
          <select class="input" :class="{ invalid: errors.type }" v-model="form.type" @change="clearError('type')" @blur="validateField('type')">
            <option value="" disabled>Select type</option>
            <option value="webhook">Webhook</option>
            <option value="discord">Discord</option>
            <option value="slack">Slack</option>
            <option value="ntfy">NTFY</option>
            <option value="email">Email</option>
          </select>
          <span v-if="errors.type" class="field-error">{{ errors.type }}</span>
        </div>

        <div v-if="form.type" class="config-fields">
          <template v-if="form.type === 'webhook' || form.type === 'discord' || form.type === 'slack'">
            <div class="field">
              <label class="label">Webhook URL</label>
              <input class="input" :class="{ invalid: errors.url }" v-model="cfg.url" placeholder="https://hooks.example.com/..." @input="clearError('url')" @blur="validateField('url')" />
              <span v-if="errors.url" class="field-error">{{ errors.url }}</span>
            </div>
          </template>

          <template v-if="form.type === 'ntfy'">
            <div class="field">
              <label class="label">Server URL</label>
              <input class="input" :class="{ invalid: errors.url }" v-model="cfg.url" placeholder="https://ntfy.sh" @input="clearError('url')" @blur="validateField('url')" />
              <span v-if="errors.url" class="field-error">{{ errors.url }}</span>
            </div>
            <div class="field">
              <label class="label">Topic</label>
              <input class="input" :class="{ invalid: errors.topic }" v-model="cfg.topic" placeholder="my-alerts" @input="clearError('topic')" @blur="validateField('topic')" />
              <span v-if="errors.topic" class="field-error">{{ errors.topic }}</span>
            </div>
            <div class="field">
              <label class="label">Token (optional)</label>
              <input class="input" v-model="cfg.token" placeholder="tk_..." />
            </div>
          </template>

          <template v-if="form.type === 'email'">
            <div class="field">
              <label class="label">Provider</label>
              <select class="input" v-model="cfg.provider" disabled>
                <option value="sendgrid">SendGrid</option>
              </select>
            </div>
            <div class="field">
              <label class="label">API Key</label>
              <input class="input" :class="{ invalid: errors.api_key }" v-model="cfg.api_key" type="password" placeholder="SG.xxxxx" @input="clearError('api_key')" @blur="validateField('api_key')" />
              <span v-if="errors.api_key" class="field-error">{{ errors.api_key }}</span>
            </div>
            <div class="field-row">
              <div class="field flex-1">
                <label class="label">From</label>
                <input class="input" :class="{ invalid: errors.from }" v-model="cfg.from" type="email" placeholder="alerts@example.com" @input="clearError('from')" @blur="validateField('from')" />
                <span v-if="errors.from" class="field-error">{{ errors.from }}</span>
              </div>
              <div class="field flex-1">
                <label class="label">To</label>
                <input class="input" :class="{ invalid: errors.to }" v-model="cfg.to" type="email" placeholder="you@example.com" @input="clearError('to')" @blur="validateField('to')" />
                <span v-if="errors.to" class="field-error">{{ errors.to }}</span>
              </div>
            </div>
          </template>
        </div>

        <div class="field">
          <label class="checkbox-label">
            <input type="checkbox" v-model="form.enabled" :true-value="1" :false-value="0" />
            Enabled
          </label>
        </div>

        <div class="modal-actions">
          <button type="button" class="btn-ghost" @click="$emit('close')">Cancel</button>
          <button type="submit" class="btn-primary" :disabled="saving">
            {{ saving ? 'Saving...' : isEdit ? 'Save Changes' : 'Add Channel' }}
          </button>
        </div>

        <div v-if="saveError" class="save-error">{{ saveError }}</div>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, watch } from 'vue'
import { type NotificationChannel } from '~lib/api'
import { useChannelStore } from '~stores/channels'
import { isValidURL, isValidEmail, isNonEmpty } from '~lib/validators'

const props = defineProps<{
  channel?: NotificationChannel | null
}>()

const emit = defineEmits<{
  close: []
  saved: []
}>()

const channelStore = useChannelStore()
const isEdit = !!props.channel
const saving = ref(false)
const saveError = ref('')

const errors = reactive<Record<string, string>>({})

function clearError(field: string) {
  delete errors[field]
}

const rules: Record<string, { test: () => boolean; message: string }> = {
  name: { test: () => isNonEmpty(form.name), message: 'Name is required' },
  type: { test: () => !!form.type, message: 'Select a channel type' },
  url: {
    test: () => {
      if (form.type === 'webhook' || form.type === 'discord' || form.type === 'slack' || form.type === 'ntfy') {
        return isValidURL(cfg.url)
      }
      return true
    },
    message: 'Enter a valid URL (https://...)',
  },
  topic: {
    test: () => form.type !== 'ntfy' || isNonEmpty(cfg.topic),
    message: 'Topic is required',
  },
  api_key: {
    test: () => form.type !== 'email' || isNonEmpty(cfg.api_key),
    message: 'API key is required',
  },
  from: {
    test: () => form.type !== 'email' || isValidEmail(cfg.from),
    message: 'Enter a valid email address',
  },
  to: {
    test: () => form.type !== 'email' || isValidEmail(cfg.to),
    message: 'Enter a valid email address',
  },
}

function validateField(field: string) {
  const rule = rules[field]
  if (rule && !rule.test()) errors[field] = rule.message
  else delete errors[field]
}

let parsedConfig: Record<string, any> = {}
try {
  parsedConfig = props.channel?.config ? JSON.parse(props.channel.config) : {}
} catch (e) {
  console.error('Failed to parse channel config:', e)
}

const form = reactive({
  name: props.channel?.name || '',
  type: props.channel?.type || '',
  enabled: props.channel?.enabled ?? 1,
})

const cfg = reactive<Record<string, any>>({ ...parsedConfig })
if (form.type === 'email' && !cfg.provider) cfg.provider = 'sendgrid'

watch(() => form.type, () => {
  Object.keys(errors).forEach(k => delete errors[k])
  if (!isEdit) {
    Object.keys(cfg).forEach(k => delete cfg[k])
    if (form.type === 'email') cfg.provider = 'sendgrid'
  }
})

function validate() {
  Object.keys(rules).forEach(validateField)
  return Object.keys(errors).length === 0
}

async function save() {
  if (!validate()) return
  saving.value = true
  saveError.value = ''
  try {
    if (form.type === 'email' && !cfg.provider) cfg.provider = 'sendgrid'
    const data = {
      name: form.name,
      type: form.type,
      config: JSON.stringify(cfg),
      enabled: form.enabled,
    }
    if (isEdit && props.channel) {
      await channelStore.update(props.channel.id, data)
    } else {
      await channelStore.create(data)
    }
    emit('saved')
  } catch (e: any) {
    saveError.value = e.message
  } finally {
    saving.value = false
  }
}
</script>

<style scoped>
.config-fields {
  @apply p-4 mb-4 rounded-lg;
  background: rgba(255,255,255,0.02);
  border: 1px solid var(--border);
}


</style>
