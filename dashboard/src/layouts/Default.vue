<template>
  <div class="app">
    <aside class="sidebar">
      <div class="logo">
        <span class="logo-icon">&#9670;</span>
        <span class="logo-text">PULSE</span>
        <span v-if="nodeRole !== 'standalone'" class="role-badge" :class="nodeRole">
          {{ nodeRole }}
        </span>
      </div>
      <nav class="nav">
        <RouterLink class="nav-btn" active-class="active" to="/" exact>
          <span class="i-mdi-monitor-dashboard nav-icon" />
          Monitors
        </RouterLink>
        <RouterLink class="nav-btn" active-class="active" to="/notifications" v-if="nodeRole !== 'checker'">
          <span class="i-mdi-bell-ring-outline nav-icon" />
          Notifications
        </RouterLink>
        <RouterLink class="nav-btn" active-class="active" to="/nodes" v-if="nodeRole === 'central'">
          <span class="i-mdi-server nav-icon" />
          Nodes
        </RouterLink>
        <RouterLink class="nav-btn" active-class="active" to="/settings" v-if="nodeRole !== 'checker'">
          <span class="i-mdi-cog-outline nav-icon" />
          Settings
        </RouterLink>
      </nav>
      <div class="sidebar-footer">
        <button class="theme-toggle" @click="toggleTheme" :title="isDark ? 'Switch to light mode' : 'Switch to dark mode'">
          <span class="i-mdi-weather-sunny" :class="{ active: !isDark }" />
          <span class="toggle-track">
            <span class="toggle-thumb" :class="{ dark: isDark }" />
          </span>
          <span class="i-mdi-weather-night" :class="{ active: isDark }" />
        </button>
      </div>
    </aside>

    <main class="main">
      <slot />
    </main>

    <transition name="toast">
      <div v-if="notification" class="toast" :class="notification.type" @click="clearNotification">
        <span class="toast-icon" :class="iconClass" />
        {{ notification.message }}
      </div>
    </transition>

    <nav class="mobile-nav">
      <RouterLink class="mobile-nav-btn" active-class="active" to="/" exact>
        <span class="i-mdi-monitor-dashboard mobile-nav-icon" />
        <span>Monitors</span>
      </RouterLink>
      <RouterLink class="mobile-nav-btn" active-class="active" to="/notifications" v-if="nodeRole !== 'checker'">
          <span class="i-mdi-bell-ring-outline mobile-nav-icon" />
          <span>Alerts</span>
        </RouterLink>
        <RouterLink class="mobile-nav-btn" active-class="active" to="/nodes" v-if="nodeRole === 'central'">
          <span class="i-mdi-server mobile-nav-icon" />
          <span>Nodes</span>
        </RouterLink>
        <RouterLink class="mobile-nav-btn" active-class="active" to="/settings" v-if="nodeRole !== 'checker'">
          <span class="i-mdi-cog-outline mobile-nav-icon" />
          <span>Settings</span>
        </RouterLink>
      <button class="mobile-nav-btn" @click="toggleTheme" :title="isDark ? 'Switch to light mode' : 'Switch to dark mode'">
        <span :class="isDark ? 'i-mdi-weather-sunny' : 'i-mdi-weather-night'" class="mobile-nav-icon" />
        <span>Theme</span>
      </button>
    </nav>
  </div>

  <AuthModal v-if="showAuthModal" />
</template>

<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { ref, computed, onMounted } from 'vue'
import { notification, clearNotification, nodeRole } from '~stores/app'
import { showAuthModal } from '~stores/auth'
import AuthModal from '~com/AuthModal.vue'

const isDark = ref(true)

const iconClass = computed(() => {
  if (!notification.value) return ''
  switch (notification.value.type) {
    case 'success': return 'i-mdi-check-circle'
    case 'error': return 'i-mdi-alert-circle'
    case 'warning': return 'i-mdi-alert'
    default: return 'i-mdi-information'
  }
})

function applyTheme(dark: boolean) {
  isDark.value = dark
  document.documentElement.classList.toggle('light', !dark)
  localStorage.setItem('pulse-theme', dark ? 'dark' : 'light')
}

function toggleTheme() {
  applyTheme(!isDark.value)
}

onMounted(() => {
  const stored = localStorage.getItem('pulse-theme')
  if (stored) {
    applyTheme(stored === 'dark')
  } else {
    applyTheme(window.matchMedia('(prefers-color-scheme: dark)').matches)
  }
})
</script>

<style>
.app {
  @apply flex h-screen;
}

.sidebar {
  @apply w-[220px] bg-[var(--surface)] border-r border-[var(--border)] flex flex-col shrink-0;
}

.logo {
  @apply flex items-center gap-[10px] p-5 border-b border-[var(--border)];
}

.role-badge {
  @apply ml-auto text-[10px] uppercase tracking-wide px-2 py-0.5 rounded-full font-medium border;
}

.role-badge.checker {
  @apply text-[var(--accent)];
  border-color: color-mix(in srgb, var(--accent) 40%, transparent);
  background: color-mix(in srgb, var(--accent) 12%, transparent);
}

.role-badge.central {
  @apply text-[var(--up)];
  border-color: color-mix(in srgb, var(--up) 40%, transparent);
  background: color-mix(in srgb, var(--up) 12%, transparent);
}

.logo-icon {
  @apply text-[20px] text-[var(--accent)];
}

.logo-text {
  @apply text-lg font-bold tracking-[-0.5px];
}

.nav {
  @apply p-3 flex flex-col gap-1 flex-1;
}

.nav-btn {
  @apply flex items-center gap-[10px] px-3 py-[10px] border-none bg-transparent text-[var(--text-secondary)] text-sm rounded-lg cursor-pointer transition-all duration-150 text-left w-full no-underline;

  &:hover, &.active { @apply bg-[var(--hover)] text-[var(--text)]; }
  &.active { @apply font-medium; }
}

.nav-icon { @apply text-base w-5 text-center; }

.sidebar-footer {
  @apply px-5 py-4 border-t border-[var(--border)] flex items-center justify-center;
}

.theme-toggle {
  @apply flex items-center gap-[6px] border-none bg-transparent cursor-pointer p-1 rounded-lg transition-all duration-150;

  &:hover { @apply bg-[var(--hover)]; }

  & .i-mdi-weather-sunny, & .i-mdi-weather-night {
    @apply text-sm text-[var(--text-muted)] transition-colors duration-150;

    &.active { @apply text-[var(--text)]; }
  }
}

.toggle-track {
  @apply w-8 h-[14px] rounded-full relative transition-colors duration-150;
  background: var(--border-hover);
}

.toggle-thumb {
  @apply w-3 h-3 rounded-full absolute top-[1px] left-[1px] transition-all duration-150;
  background: var(--text-muted);

  &.dark { transform: translateX(14px); background: var(--accent); }
}

.main {
  @apply flex-1 flex flex-col overflow-hidden;
}

.toast {
  @apply fixed top-4 left-1/2 -translate-x-1/2 flex items-center gap-2 px-5 py-3 rounded-xl text-[13px] cursor-pointer z-[100] shadow-lg border;

  &.success {
    background: color-mix(in srgb, var(--up) 18%, var(--surface));
    border-color: color-mix(in srgb, var(--up) 50%, var(--surface));
    color: var(--up);
  }

  &.error {
    background: color-mix(in srgb, var(--down) 18%, var(--surface));
    border-color: color-mix(in srgb, var(--down) 50%, var(--surface));
    color: var(--down);
  }

  &.warning {
    background: color-mix(in srgb, #eab308 18%, var(--surface));
    border-color: color-mix(in srgb, #eab308 50%, var(--surface));
    color: #eab308;
  }

  &.info {
    background: color-mix(in srgb, var(--accent) 18%, var(--surface));
    border-color: color-mix(in srgb, var(--accent) 50%, var(--surface));
    color: var(--accent);
  }
}

.toast-icon {
  @apply text-base shrink-0;
}

.toast-enter-active {
  transition: all 0.25s ease-out;
}

.toast-leave-active {
  transition: all 0.2s ease-in;
}

.toast-enter-from {
  opacity: 0;
  transform: translate(-50%, -12px);
}

.toast-leave-to {
  opacity: 0;
  transform: translate(-50%, -12px);
}
</style>
