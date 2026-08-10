import { ref, reactive } from 'vue'
import { api, type ClusterNode } from '~lib/api'

const nodes = ref<ClusterNode[]>([])
const selectedNodeId = ref<number | null>(null)
const loading = ref(false)

export function useNodeStore() {
  async function load() {
    loading.value = true
    try {
      nodes.value = await api.listNodes()
    } catch {
      // silence
    } finally {
      loading.value = false
    }
  }

  async function create(data: { name: string; role?: string }) {
    const result = await api.createNode(data)
    nodes.value.push(result.node)
    return result
  }

  async function remove(id: number) {
    await api.deleteNode(id)
    nodes.value = nodes.value.filter(n => n.id !== id)
    if (selectedNodeId.value === id) selectedNodeId.value = null
  }

  async function toggleActive(n: ClusterNode) {
    if (n.active === 1) {
      await api.deactivateNode(n.id)
      n.active = 0
    } else {
      await api.activateNode(n.id)
      n.active = 1
    }
  }

  async function updateNode(id: number, data: Partial<ClusterNode>) {
    const updated = await api.updateNode(id, data)
    const n = nodes.value.find(n => n.id === id)
    if (n) Object.assign(n, updated)
  }

  async function resetNodeToken(id: number) {
    const result = await api.resetNodeToken(id)
    const n = nodes.value.find(n => n.id === id)
    if (n && result.node) Object.assign(n, result.node)
    return result.token
  }

  return reactive({ nodes, selectedNodeId, loading, load, create, remove, toggleActive, updateNode, resetNodeToken })
}
