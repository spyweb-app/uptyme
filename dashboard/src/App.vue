<template>
  <RouterView />
</template>

<script setup lang="ts">
import { computed, onMounted, watch } from 'vue'
import { RouterView, useRoute } from 'vue-router'
import { loadAppData } from '~stores/app'

const route = useRoute()
const isPublicStatus = computed(() => route.path.startsWith('/status/'))

watch(() => route.path, () => { if (!isPublicStatus.value) loadAppData() })

onMounted(() => { if (!isPublicStatus.value) loadAppData() })
</script>
