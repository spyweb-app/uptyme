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
        @click="store.selectedNodeId = n.id"
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

import { ref, onMounted, watch } from 'vue'
import { type ClusterNode } from '~lib/api'
import { nodeRole, showNotification } from '~stores/app'
import { keyVersion } from '~stores/auth'
import { useNodeStore } from '~stores/nodes'
import { formatRelative, formatDate } from '~lib/dates'
import NodeForm from '~com/NodeForm.vue'
import NodeDetail from '~com/NodeDetail.vue'

const store = useNodeStore()
const showForm = ref(false)

watch(keyVersion, () => { store.load() })

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
  background: rgba(251, 191, 36, 0.1);
  color: rgb(251, 191, 36);
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
