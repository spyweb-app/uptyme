<template>
  <div class="modal-overlay" @click.self="$emit('cancel')">
    <div class="modal" style="max-width: 400px">
      <div class="modal-header">
        <h2 class="modal-title">{{ title }}</h2>
      </div>
      <div class="modal-body">
        <p class="confirm-message">{{ message }}</p>
        <div class="modal-actions">
          <button class="btn-ghost" @click="$emit('cancel')">Cancel</button>
          <button class="btn-danger" @click="$emit('confirm')">{{ confirmText }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const _props = withDefaults(defineProps<{
  title: string
  message: string
  confirmText?: string
}>(), {
  confirmText: 'Delete',
})

defineEmits<{
  confirm: []
  cancel: []
}>()
</script>

<style scoped>
.confirm-message {
  @apply text-[var(--text-secondary)] text-sm leading-normal;
}
</style>
