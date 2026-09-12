<template>
  <RouterView />
</template>

<script setup lang="ts">
import { computed, onMounted, watch } from 'vue'
import { RouterView, useRoute } from 'vue-router'
import { loadNodeRole } from '~stores/app'
import { keyVersion } from '~stores/auth'

const route = useRoute()
const isPublicStatus = computed(() => route.path.startsWith('/status/'))

watch(keyVersion, () => { if (!isPublicStatus.value) loadNodeRole() })
watch(() => route.path, () => { if (!isPublicStatus.value) loadNodeRole() })

onMounted(() => { if (!isPublicStatus.value) loadNodeRole() })
</script>
