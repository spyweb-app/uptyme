import { ref } from 'vue'

function getStoredKey(): string {
  try { return localStorage.getItem('spyweb_api_key') || '' } catch { return '' }
}

export const apiKey = ref(getStoredKey())
export const showAuthModal = ref(false)

export function setApiKey(key: string | null) {
  if (key === null) {
    apiKey.value = ''
    try { localStorage.removeItem('spyweb_api_key') } catch {}
    showAuthModal.value = true
    return
  }
  apiKey.value = key
  try { localStorage.setItem('spyweb_api_key', key) } catch {}
  window.location.reload()
}
