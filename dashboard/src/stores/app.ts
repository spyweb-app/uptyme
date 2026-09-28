import { ref } from 'vue'
import { api } from '~lib/api'

export const nodeRole = ref<'standalone' | 'central' | 'checker'>('standalone')

export const instanceName = ref('UPTYME')

export function setInstanceName(name?: string) {
  instanceName.value = name || 'UPTYME'
}

export async function loadAppData() {
  try {
    const s = await api.getSettings()
    nodeRole.value = (s.role as any) || 'standalone'
    setInstanceName(s.instance_name)
    document.title = `${instanceName.value} - Website Uptime Monitoring`
  } catch {
    nodeRole.value = 'standalone'
  }
}

export const connected = ref(true)

export interface Toast {
  message: string
  type: 'success' | 'error' | 'warning' | 'info'
}

export const notification = ref<Toast | null>(null)

export function showNotification(msg: string, type: Toast['type'] = 'info') {
  notification.value = { message: msg, type }
  setTimeout(() => { notification.value = null }, 4000)
}

export function clearNotification() {
  notification.value = null
}
