<template>
  <Teleport to="body">
    <div class="modal-overlay" @click.self="close">
      <div class="auth-modal">
        <span class="auth-icon">&#128274;</span>
        <h3 class="auth-title">Authentication Required</h3>
        <p class="auth-desc">Please enter your API key to continue.</p>

        <div class="input-wrap">
          <input
            ref="inputRef"
            v-model="inputKey"
            :type="showKey ? 'text' : 'password'"
            class="input"
            placeholder="Enter API Key"
            @input="error = ''"
            @keyup.enter="submit"
          />
          <button
            type="button"
            class="eye-btn"
            :title="showKey ? 'Hide API key' : 'Show API key'"
            @click="showKey = !showKey"
          >
            <span :class="showKey ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" />
          </button>
        </div>

        <p v-if="error" class="auth-error">{{ error }}</p>

        <button class="auth-btn" :disabled="pending" @click="submit">
          {{ pending ? 'Verifying…' : 'Unlock Dashboard' }}
        </button>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { setApiKey, apiKey, showAuthModal } from '~stores/auth'
import { api } from '~lib/api'

const inputKey = ref('')
const inputRef = ref<HTMLInputElement | null>(null)
const error = ref('')
const pending = ref(false)
const showKey = ref(false)

onMounted(() => {
  inputRef.value?.focus()
})

async function submit() {
  if (!inputKey.value || pending.value) return
  pending.value = true
  error.value = ''
  try {
    if (await api.verifyKey(inputKey.value)) {
      setApiKey(inputKey.value)
    } else {
      error.value = 'Invalid API key'
    }
  } catch {
    error.value = "Couldn't reach server"
  } finally {
    pending.value = false
  }
}

function close() {
  if (apiKey.value) showAuthModal.value = false
}
</script>

<style scoped>
.auth-modal {
  @apply bg-[var(--surface)] rounded-xl border border-[var(--border)] p-6 text-center;
  max-width: 400px;
  width: 100%;
  margin: 0 auto;
}

.auth-icon {
  @apply text-[48px] block mb-4;
  color: var(--accent);
}

.auth-title {
  @apply text-xl font-bold mb-2;
}

.auth-desc {
  @apply text-sm text-[var(--text-muted)] mb-5;
}

.input-wrap {
  @apply relative mb-3;
}

.input-wrap .input {
  @apply pr-10;
}

.eye-btn {
  @apply absolute right-1 top-1/2 -translate-y-1/2 flex items-center justify-center border-none bg-transparent cursor-pointer p-1.5 rounded-md transition-colors;
  color: var(--text-muted);
}

.eye-btn:hover {
  color: var(--text);
}

.auth-error {
  @apply text-sm mb-4 text-center;
  color: var(--down);
}

.auth-btn {
  @apply w-full rounded-lg py-3 px-4 font-semibold cursor-pointer transition-all duration-150;
  background: var(--accent);
  color: #fff;
  border: none;
}
.auth-btn:hover {
  background: var(--accent-hover);
}
.auth-btn:disabled {
  @apply opacity-60 cursor-wait;
}
</style>
