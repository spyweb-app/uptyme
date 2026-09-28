<template>
  <header class="topbar">
    <h1 class="title">
      <span class="i-mdi-server text-[var(--accent)] mr-2" />
      Nodes
    </h1>
    <button v-if="nodeRole === 'central'" class="btn-primary" @click="showForm = true">
      <span class="i-mdi-plus mr-1" />
      Add Node
    </button>
  </header>

  <div class="content">
    <div v-if="nodeRole !== 'central'" class="readonly-notice">
      <span class="i-mdi-information-outline text-lg" />
      <span>Node registry is only available on the central node.</span>
    </div>

    <div v-if="store.nodes.length === 0" class="empty">
      <span class="i-mdi-server-off text-5xl text-[var(--text-muted)] opacity-30" />
      <p>No nodes registered yet.</p>
      <p class="text-sm text-[var(--text-muted)]">Add a checker node to start reporting.</p>
    </div>
    <div v-else class="node-list">
      <div
        v-for="n in store.nodes"
        :key="n.id"
        class="node-row"
        @click="openNode(n)"
      >
        <label class="toggle" @click.stop>
          <input type="checkbox" :checked="n.active === 1" @change="toggleNode(n)" />
          <span class="toggle-slider"></span>
        </label>
        <div class="node-info">
          <span class="node-name">{{ n.name }}</span>
          <span class="node-id">{{ n.local_name || 'ID: ' + n.id }}</span>
        </div>
        <div class="node-details">
          <input
            v-if="activeNode?.id === n.id"
            class="node-alert node-alert-input"
            v-model.number="alertValue"
            type="number"
            min="0"
            max="10080"
            @click.stop
            @keydown.enter="saveAlert"
            @keydown.esc="activeNode = null; alertValue = null"
            @blur="saveAlert"
          />
          <span
            v-else
            class="node-alert"
            :class="{ 'node-alert-off': (n.stale_alert_minutes ?? 0) === 0 }"
            :title="'Silent alert: click to edit. 0 = never.'"
            @click.stop="editAlert(n)"
          >
            {{ (n.stale_alert_minutes ?? 0) === 0 ? 'alert off' : 'alert ' + (n.stale_alert_minutes ?? 0) + 'm' }}
          </span>
          <span class="node-seen">{{ n.last_seen_at ? formatRelative(n.last_seen_at) : 'Never seen' }}</span>
          <span :class="n.active === 1 ? 'status-active' : 'status-inactive'">
            {{ n.active === 1 ? 'Active' : 'Inactive' }}
          </span>
          <span class="node-created">{{ formatDate(n.created_at) }}</span>
        </div>
      </div>
    </div>
  </div>

  <NodeForm
    v-if="showForm"
    @close="showForm = false"
  />

  <NodeDetail
    v-if="store.selectedNodeId"
    @close="store.selectedNodeId = null"
  />
</template>

<script setup lang="ts">
defineOptions({ layout: 'default' })

import { ref, onMounted } from 'vue'
import { type ClusterNode } from '~lib/api'
import { nodeRole, showNotification } from '~stores/app'
import { useNodeStore } from '~stores/nodes'
import { formatRelative, formatDate } from '~lib/dates'
import NodeForm from '~com/NodeForm.vue'
import NodeDetail from '~com/NodeDetail.vue'

const store = useNodeStore()
const showForm = ref(false)

const activeNode = ref<ClusterNode | null>(null)
const alertValue = ref<number | null>(null)

function editAlert(n: ClusterNode) {
  activeNode.value = n
  alertValue.value = n.stale_alert_minutes ?? 0
}

async function saveAlert() {
  if (!activeNode.value) return
  const v = Number(alertValue.value)
  const n = activeNode.value
  if (Number.isInteger(v) && v >= 0 && v <= 10080) {
    try {
      await store.updateNode(n.id, { stale_alert_minutes: v })
      n.stale_alert_minutes = v
    } catch (e: any) {
      showNotification(e.message || 'Failed to save alert', 'error')
      store.load()
    }
  }
  activeNode.value = null
  setTimeout(() => {
    if (!activeNode.value) alertValue.value = null
  }, 150)
}

function openNode(n: ClusterNode) {
  if (activeNode.value === null && alertValue.value === null) {
    store.selectedNodeId = n.id
    return
  }
  saveAlert()
}

async function toggleNode(n: ClusterNode) {
  try {
    await store.toggleActive(n)
    showNotification(n.active === 0 ? 'Node deactivated' : 'Node activated', 'success')
  } catch (e: any) {
    showNotification(e.message, 'error')
    store.load()
  }
}

onMounted(() => {
  store.load()
})
</script>

<style scoped>
.readonly-notice {
  @apply flex items-center gap-2 px-4 py-3 mb-4 rounded-lg text-sm;
  background: color-mix(in srgb, var(--blocked) 10%, transparent);
  color: var(--blocked);
}

.empty {
  @apply flex flex-col items-center justify-center h-[30vh] text-[var(--text-muted)] gap-3;
}

.node-list {
  @apply flex flex-col gap-2;
}

.node-row {
  @apply flex items-center bg-[var(--surface)] border border-[var(--border)] rounded-xl px-5 py-4 gap-3 cursor-pointer transition-colors duration-150;

  &:hover { @apply bg-[var(--hover)]; }
}

.node-info {
  @apply flex flex-col min-w-0 flex-1;
}

.node-name {
  @apply text-sm font-medium;
}

.node-id {
  @apply text-xs text-[var(--text-muted)] mt-0.5;
}

.node-details {
  @apply flex items-center gap-3 shrink-0;
}

.node-seen {
  @apply text-xs text-[var(--text-muted)] tabular-nums;
}

.node-alert {
  @apply text-xs font-medium uppercase tracking-wide px-2 py-1 rounded-md border border-[var(--border)] text-[var(--text-muted)] tabular-nums shrink-0;
}

.node-alert-off {
  @apply opacity-60;
}

.node-alert-input {
  @apply cursor-text;
  appearance: textfield;
  -moz-appearance: textfield;
  background: transparent;
  color: var(--text);
  border-color: var(--accent);
  width: 5.5rem;

  &::-webkit-outer-spin-button,
  &::-webkit-inner-spin-button {
    -webkit-appearance: none;
    margin: 0;
  }

  &:focus {
    @apply outline-none;
    box-shadow: 0 0 0 1px var(--accent);
  }
}

.node-created {
  @apply text-xs text-[var(--text-muted)];
}

.status-active {
  @apply text-[var(--up)] font-medium text-xs;
}

.status-inactive {
  @apply text-[var(--text-muted)] text-xs;
}


</style>
