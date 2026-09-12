<template>
  <div class="search-select" ref="containerRef">
    <div class="search-select-input" :class="{ focused: showDropdown, 'has-value': hasValue }">
      <!-- Multi mode: tags -->
      <VueDraggable v-if="isMulti && selectedArray.length" v-model="selectedCopy" item-key="_uid" :animation="200" handle=".drag-handle" class="search-select-tags" @end="onDragEnd">
        <div v-for="element in selectedCopy" :key="element._uid" class="search-select-tag">
          <span class="i-mdi-drag-horizontal drag-handle" />
          {{ element[labelKey] }}
          <button type="button" class="tag-remove" @click.stop="remove(element)" aria-label="Remove">&times;</button>
        </div>
      </VueDraggable>

      <!-- Single mode: selected value display -->
      <div v-if="isSingle && selectedSingle && !editingSingle" class="search-select-display" @click="startEdit">
        <span class="search-select-display-text">{{ selectedSingle[labelKey] }}</span>
        <button type="button" class="clear-btn" @click.stop="clearSingle" aria-label="Clear">&times;</button>
      </div>

      <div class="search-select-input-row">
        <span class="i-mdi-magnify search-select-icon" />
        <input
          ref="inputRef"
          class="search-select-field-input"
          v-model="searchQuery"
          :placeholder="inputPlaceholder"
          :disabled="disabled"
          :readonly="isSingle && selectedSingle != null && !editingSingle"
          @focus="onFocus"
          @input="onInput"
        />
      </div>
    </div>

    <Teleport to="body">
      <div
        v-if="showDropdown && items.length"
        ref="dropdownRef"
        class="search-select-dropdown"
        :style="dropdownStyle"
      >
        <!-- Multi mode: checkboxes -->
        <template v-if="isMulti">
          <label v-for="item in items" :key="item[itemKey]" class="search-select-option">
            <input type="checkbox" :checked="isSelected(item)" @change="toggle(item)" />
            <span class="search-select-option-label">{{ item[labelKey] }}</span>
            <span v-if="sublabelKey" class="search-select-option-sublabel">{{ item[sublabelKey] }}</span>
          </label>
        </template>

        <!-- Single mode: plain list -->
        <template v-else>
          <div
            v-for="item in items"
            :key="item[itemKey]"
            class="search-select-option"
            :class="{ active: isSelected(item) }"
            @click="selectSingle(item)"
          >
            <span class="search-select-option-label">{{ item[labelKey] }}</span>
            <span v-if="sublabelKey" class="search-select-option-sublabel">{{ item[sublabelKey] }}</span>
          </div>
        </template>
      </div>

      <div
        v-else-if="showDropdown && searchQuery && !loading && !items.length"
        class="search-select-dropdown empty"
        :style="dropdownStyle"
      >
        <span class="i-mdi-magnify" />
        <span>No results for "{{ searchQuery }}"</span>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
import { ref, nextTick, computed, onBeforeUnmount } from 'vue'
import { VueDraggable } from 'vue-draggable-plus'

const props = withDefaults(defineProps<{
  modelValue: any | any[]
  mode?: 'single' | 'multi'
  items: any[]
  loading?: boolean
  placeholder?: string
  labelKey?: string
  sublabelKey?: string
  itemKey?: string
  disabled?: boolean
}>(), {
  mode: 'single',
  loading: false,
  placeholder: 'Search...',
  labelKey: 'name',
  sublabelKey: '',
  itemKey: 'id',
  disabled: false,
})

const emit = defineEmits<{
  'update:modelValue': [value: any | any[]]
  'search': [query: string]
  'focus': []
}>()

const isMulti = computed(() => props.mode === 'multi')
const isSingle = computed(() => props.mode === 'single')

const searchQuery = ref('')
const showDropdown = ref(false)
const editingSingle = ref(false)
const containerRef = ref<HTMLDivElement | null>(null)
const inputRef = ref<HTMLInputElement | null>(null)
const dropdownRef = ref<HTMLDivElement | null>(null)
const dropdownStyle = ref<Record<string, string>>({})

// Single mode helpers
const selectedSingle = computed(() => {
  if (isMulti.value) return null
  return props.modelValue && typeof props.modelValue === 'object' ? props.modelValue : null
})

const hasValue = computed(() => {
  if (isMulti.value) return Array.isArray(props.modelValue) && props.modelValue.length > 0
  return selectedSingle.value != null
})

const inputPlaceholder = computed(() => {
  if (isMulti.value) {
    return Array.isArray(props.modelValue) && props.modelValue.length ? '' : props.placeholder
  }
  if (selectedSingle.value && !editingSingle.value) return ''
  return props.placeholder
})

// Multi mode helpers
const selectedArray = computed(() => {
  if (!isMulti.value) return []
  return Array.isArray(props.modelValue) ? props.modelValue : []
})

const selectedCopy = computed({
  get: () => selectedArray.value.map((item: any, i: number) => ({ ...item, _uid: i })),
  set: (val: any[]) => {
    emit('update:modelValue', val.map(({ _uid, ...rest }: any) => rest))
  }
})

function isSelected(item: any): boolean {
  if (isMulti.value) {
    return selectedArray.value.some((v: any) => v[props.itemKey] === item[props.itemKey])
  }
  return selectedSingle.value?.[props.itemKey] === item[props.itemKey]
}

function toggle(item: any) {
  if (!isMulti.value) return
  const newValue = [...selectedArray.value]
  const index = newValue.findIndex((v: any) => v[props.itemKey] === item[props.itemKey])
  if (index >= 0) {
    newValue.splice(index, 1)
  } else {
    newValue.push(item)
  }
  emit('update:modelValue', newValue)
}

function remove(item: any) {
  if (!isMulti.value) return
  emit('update:modelValue', selectedArray.value.filter((v: any) => v[props.itemKey] !== item[props.itemKey]))
}

function selectSingle(item: any) {
  if (isMulti.value) return
  emit('update:modelValue', item)
  showDropdown.value = false
  editingSingle.value = false
  searchQuery.value = ''
}

function clearSingle() {
  if (isMulti.value) return
  emit('update:modelValue', null)
  searchQuery.value = ''
  editingSingle.value = false
  nextTick(() => inputRef.value?.focus())
}

function startEdit() {
  editingSingle.value = true
  searchQuery.value = ''
  nextTick(() => inputRef.value?.focus())
}

function onDragEnd() {
  // selectedCopy setter already emitted update:modelValue
}

function updateDropdownPosition() {
  if (!containerRef.value || !showDropdown.value) return
  const rect = containerRef.value.getBoundingClientRect()
  const spaceBelow = window.innerHeight - rect.bottom
  const dropdownMaxHeight = 240

  if (spaceBelow >= dropdownMaxHeight) {
    dropdownStyle.value = {
      position: 'fixed',
      left: `${rect.left}px`,
      top: `${rect.bottom + 4}px`,
      width: `${rect.width}px`,
    }
  } else {
    dropdownStyle.value = {
      position: 'fixed',
      left: `${rect.left}px`,
      bottom: `${window.innerHeight - rect.top + 4}px`,
      width: `${rect.width}px`,
    }
  }
}

function onFocus() {
  showDropdown.value = true
  if (isSingle.value) editingSingle.value = true
  nextTick(() => updateDropdownPosition())
  emit('focus')
  emit('search', searchQuery.value)
}

function onInput() {
  emit('search', searchQuery.value)
}

function onClickOutside(e: MouseEvent) {
  const target = e.target as Node
  if (containerRef.value?.contains(target)) return
  if (dropdownRef.value?.contains(target)) return
  showDropdown.value = false
  editingSingle.value = false
}

function onScroll() {
  if (showDropdown.value) {
    updateDropdownPosition()
  }
}

document.addEventListener('mousedown', onClickOutside)
window.addEventListener('scroll', onScroll, true)
onBeforeUnmount(() => {
  document.removeEventListener('mousedown', onClickOutside)
  window.removeEventListener('scroll', onScroll, true)
})
</script>

<style scoped>
.search-select {
  @apply relative w-full;
}

.search-select-input {
  @apply relative w-full flex flex-wrap items-center gap-2 rounded-lg border border-[var(--border)] bg-[var(--bg)] px-3 py-2;
  transition: border-color 0.15s;

  &.focused {
    @apply border-[var(--accent)];
  }
}

.search-select-input-row {
  @apply relative flex items-center flex-1 min-w-[7rem];

  .search-select-icon {
    @apply absolute left-0 top-1/2 -translate-y-1/2 text-[var(--text-muted)] z-10 pointer-events-none;
  }

  .search-select-field-input {
    @apply flex-1 pl-5 py-0 text-[var(--text)] placeholder-[var(--text-muted)] bg-transparent border-none outline-none focus:ring-0;

    &[readonly] {
      @apply cursor-pointer;
    }
  }
}

.search-select-display {
  @apply flex items-center gap-2 cursor-pointer;

  .search-select-display-text {
    @apply text-sm font-medium text-[var(--text)];
  }

  .clear-btn {
    @apply text-[var(--text-muted)] bg-transparent border-none cursor-pointer leading-none p-0;
    font-size: 15px;
    @apply hover:text-[var(--text)];
  }
}

.search-select-tags {
  @apply flex flex-wrap gap-1.5 items-center;
}

.search-select-tag {
  @apply inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium;
  background: color-mix(in srgb, var(--accent) 12%, transparent);
  color: var(--accent);

  .drag-handle {
    @apply cursor-grab text-[var(--text-muted)] select-none;
    @apply hover:text-[var(--text)] active:cursor-grabbing;
  }

  .tag-remove {
    @apply ml-0.5 text-current opacity-50 bg-transparent border-none cursor-pointer leading-none p-0;
    @apply hover:opacity-100;
    font-size: 13px;
  }
}
</style>

<style>
.search-select-dropdown {
  @apply fixed max-h-60 overflow-y-auto rounded-lg border border-[var(--border)] bg-[var(--surface)] z-[9999] shadow-lg;

  &.empty {
    @apply flex items-center justify-center gap-2 px-4 py-6 text-[var(--text-muted)];
  }
}

.search-select-option {
  @apply flex items-center gap-3 px-3 py-2 cursor-pointer;

  &:hover { @apply bg-[var(--hover)]; }
  &.active { @apply bg-[var(--hover)]; }
  input { @apply accent-[var(--accent)]; }
}

.search-select-option-label {
  @apply flex-1 text-sm font-medium truncate;
}

.search-select-option-sublabel {
  @apply text-xs text-[var(--text-muted)] truncate max-w-[200px];
}
</style>
