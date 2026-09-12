<template>
  <span :class="msClass">{{ ms ?? '-' }}<template v-if="ms != null">ms</template></span>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  ms: number | null | undefined
}>()

const msClass = computed(() => {
  if (props.ms == null) return ''
  if (props.ms < 200) return 'text-up'
  if (props.ms < 500) return 'text-blocked'
  return 'text-down'
})
</script>
