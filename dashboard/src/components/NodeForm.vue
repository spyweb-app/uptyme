<template>
  <div class="modal-overlay">
    <div class="modal">
      <template v-if="!token">
        <div class="modal-header">
          <h2 class="modal-title">Add Node</h2>
          <button class="close-btn" @click="$emit('close')">&times;</button>
        </div>

        <form class="modal-body" @submit.prevent="save">
          <div class="field">
            <label class="label">Name</label>
            <input class="input" :class="{ invalid: errors.name }" v-model="form.name" placeholder="checker-1" @input="clearError('name')" @blur="validateField('name')" />
            <span v-if="errors.name" class="field-error">{{ errors.name }}</span>
          </div>

          <div class="modal-actions">
            <button type="button" class="btn-ghost" @click="$emit('close')">Cancel</button>
            <button type="submit" class="btn-primary" :disabled="saving">
              {{ saving ? 'Creating...' : 'Add Node' }}
            </button>
          </div>

          <div v-if="saveError" class="save-error">{{ saveError }}</div>
        </form>
      </template>

      <template v-else>
        <div class="modal-header">
          <h2 class="modal-title">Node Created</h2>
          <button class="close-btn" @click="$emit('close')">&times;</button>
        </div>
        <div class="modal-body">
          <p class="token-desc">Copy this token now. It will not be shown again.</p>
          <div class="token-display" @click="copyToken">
            <code>{{ token }}</code>
            <span class="copy-hint" v-if="!copied">Click to copy</span>
            <span class="copy-hint copied" v-else>Copied!</span>
          </div>
          <button class="btn-primary w-full mt-4" @click="$emit('close')">Done</button>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { isNonEmpty } from '~lib/validators'
import { useNodeStore } from '~stores/nodes'

const emit = defineEmits<{
  close: []
  saved: []
}>()

const store = useNodeStore()
const saving = ref(false)
const saveError = ref('')
const token = ref('')
const copied = ref(false)

const errors = reactive<Record<string, string>>({})

function clearError(field: string) {
  delete errors[field]
}

const rules: Record<string, { test: () => boolean; message: string }> = {
  name: { test: () => isNonEmpty(form.name), message: 'Name is required' },
}

function validateField(field: string) {
  const rule = rules[field]
  if (rule && !rule.test()) errors[field] = rule.message
  else delete errors[field]
}

const form = reactive({
  name: '',
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
    const result = await store.create({ name: form.name })
    token.value = result.token
  } catch (e: any) {
    saveError.value = e.message
  } finally {
    saving.value = false
  }
}

async function copyToken() {
  try {
    await navigator.clipboard.writeText(token.value)
    copied.value = true
    setTimeout(() => { copied.value = false }, 2000)
  } catch {}
}
</script>

<style scoped>

</style>
