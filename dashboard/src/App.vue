<template>
  <RouterView />
</template>

<script setup lang="ts">
import { onMounted, watch } from 'vue'
import { RouterView } from 'vue-router'
import { loadNodeRole } from '~stores/app'
import { keyVersion } from '~stores/auth'

watch(keyVersion, () => { loadNodeRole() })

onMounted(() => { loadNodeRole() })
</script>
