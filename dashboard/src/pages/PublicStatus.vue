<template>
  <main class="public-status">
    <div class="public-status-inner">
      <header class="public-header">
        <div class="brand"><span class="brand-mark">◆</span> PULSE</div>
        <button class="refresh" :disabled="loading" @click="load">
          <span class="i-mdi-refresh" :class="{ spinning: loading }" />
          Refresh
        </button>
      </header>

      <div v-if="loading" class="state-card">
        <span class="i-mdi-loading spinning state-icon" />
        <p>Loading status...</p>
      </div>

      <div v-else-if="error" class="state-card">
        <span class="i-mdi-alert-circle-outline state-icon error-icon" />
        <h1>Status page unavailable</h1>
        <p>{{ error }}</p>
      </div>

      <template v-else-if="page">
        <section class="page-heading">
          <p class="eyebrow">SYSTEM STATUS</p>
          <h1>{{ page.name }}</h1>
          <p v-if="page.description" class="description">
            {{ page.description }}
          </p>
        </section>

        <section class="overall-card" :class="'status-' + page.status">
          <span class="status-icon" :class="statusIcon(page.status)" />
          <div>
            <h2>{{ statusLabel(page.status) }}</h2>
            <p>
              {{
                isGroup(page)
                  ? overallMessage(page.status)
                  : monitorMessage(page.status)
              }}
            </p>
          </div>
        </section>

        <template v-if="isGroup(page)">
          <section class="summary-grid">
            <div class="summary-item">
              <strong>{{ page.monitor_count }}</strong
              ><span>Monitors</span>
            </div>
            <div class="summary-item">
              <strong class="text-up">{{ page.operational_count }}</strong
              ><span>Operational</span>
            </div>
            <div class="summary-item">
              <strong class="text-down">{{ page.down_count }}</strong
              ><span>Down</span>
            </div>
            <div class="summary-item">
              <strong class="text-blocked">{{ page.blocked_count }}</strong
              ><span>Blocked</span>
            </div>
          </section>

          <section class="section">
            <h2 class="section-title">Monitors</h2>
            <div v-if="page.monitors.length" class="monitor-list">
              <div v-for="monitor in page.monitors" :key="monitor.monitor_id || monitor.name" class="monitor-entry">
                <component
                  :is="monitor.slug ? 'a' : 'div'"
                  :href="monitor.slug ? '/status/' + encodeSlug(monitor.slug) : undefined"
                  class="monitor-row"
                >
                  <span class="monitor-light" :class="'light-' + monitor.status" />
                  <span class="monitor-name">{{ monitor.name }}</span>
                  <span class="monitor-time">{{ checkedAt(monitor.last_checked_at) }}</span>
                  <span class="monitor-status" :class="'text-' + monitor.status">{{ statusLabel(monitor.status) }}</span>
                  <span v-if="monitor.slug" class="i-mdi-chevron-right row-arrow" />
                </component>
                <div v-if="monitor.summary?.length" class="monitor-chart">
                  <ReportBar
                    :monitorId="monitor.monitor_id!"
                    :pageSlug="page.slug"
                    :initialData="monitor.summary"
                  />
                </div>
              </div>
            </div>
            <p v-else class="muted">
              No monitors are currently assigned to this group.
            </p>
          </section>
        </template>

        <template v-if="mp">
          <section class="summary-grid">
            <div class="summary-item">
              <strong :class="uptimeClass(mp?.uptime_24h)"
                >{{ mp?.uptime_24h ?? "-" }}%</strong
              >
              <span>24h Uptime</span>
            </div>
            <div class="summary-item">
              <strong :class="uptimeClass(mp?.uptime_7d)"
                >{{ mp?.uptime_7d ?? "-" }}%</strong
              >
              <span>7d Uptime</span>
            </div>
            <div class="summary-item">
              <strong :class="uptimeClass(mp?.uptime_30d)"
                >{{ mp?.uptime_30d ?? "-" }}%</strong
              >
              <span>30d Uptime</span>
            </div>
            <div class="summary-item">
              <strong><ResponseTime :ms="todayAvgMs != null ? Math.round(todayAvgMs) : null" /></strong>
              <span>Avg Response (Today)</span>
            </div>
          </section>

          <div v-if="mp?.summary?.length" class="charts-section">
            <ReportBar
              :monitorId="mp.monitor_id!"
              :pageSlug="mp.slug"
              :initialData="mp.summary"
            />
          </div>

          <div v-if="mp?.summary?.length" class="charts-section">
            <ReportChart
              :monitorId="mp.monitor_id!"
              :pageSlug="mp.slug"
              :initialData="mp.summary"
            />
          </div>
        </template>

        <section class="section">
          <div class="section-header">
            <h2 class="section-title">Incidents</h2>
            <span v-if="incidentTotalPages > 1" class="panel-pagination">
              <button
                class="page-btn"
                :disabled="incidentsPage <= 1"
                @click="incidentsPage--"
              >
                <span class="i-mdi-chevron-left" />
              </button>
              <span class="page-info"
                >{{ incidentsPage }}/{{ incidentTotalPages }}</span
              >
              <button
                class="page-btn"
                :disabled="incidentsPage >= incidentTotalPages"
                @click="incidentsPage++"
              >
                <span class="i-mdi-chevron-right" />
              </button>
            </span>
          </div>
          <div v-if="currentIncidents.length" class="incident-list">
            <div
              v-for="incident in paginatedIncidents"
              :key="incident.monitor_id + '-' + incident.started_at"
              class="incident-row"
            >
              <span
                class="i-mdi-alert-circle incident-icon"
                :class="incident.status === 'DOWN' ? 'is-down' : 'is-up'"
              />
              <div>
                <strong>
                  <template v-if="isGroup(page)"
                    >{{ incident.name }} -
                  </template>
                  {{
                    incident.status === "DOWN"
                      ? "Outage detected"
                      : "Outage resolved"
                  }}
                </strong>
                <span v-if="incident.status === 'DOWN'"
                  >Down since {{ formatDateTime(incident.started_at) }}</span
                >
                <span v-else
                  >Down from {{ formatDateTime(incident.started_at) }} to
                  {{ formatDateTime(incident.resolved_at) }}</span
                >
              </div>
            </div>
          </div>
          <div v-else class="no-incidents">No incidents to report</div>
        </section>

        <p class="powered">Powered by PULSE</p>
      </template>
    </div>
  </main>
</template>

<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref, computed, watch } from "vue";
import { useRoute } from "vue-router";
import {
  getPublicStatus,
  type PublicGroupPage,
  type PublicMonitorPage,
  type PublicStatusPage,
} from "~lib/publicApi";
import ReportChart from "~com/ReportChart.vue";
import ReportBar from "~com/ReportBar.vue";
import ResponseTime from "~com/ResponseTime.vue";

// state
const route = useRoute();
const page = ref<PublicStatusPage | null>(null);
const loading = ref(true);
const error = ref("");
const PAGE_SIZE = 5;
const incidentsPage = ref(1);

// computed
const mp = computed(() => (isMonitor(page.value!) ? (page.value as PublicMonitorPage) : null));

const todayAvgMs = computed(() => {
  if (!mp.value?.summary?.length) return null;
  const today = new Date().toISOString().slice(0, 10);
  const todayEntry = mp.value.summary.find((s) => s.period === today);
  return todayEntry?.avg_response_ms ?? null;
});

const currentIncidents = computed(() => {
  if (isGroup(page.value))
    return (page.value as PublicGroupPage).incidents ?? [];
  return (mp.value as any)?.incidents ?? [];
});

const incidentTotalPages = computed(() =>
  Math.max(1, Math.ceil(currentIncidents.value.length / PAGE_SIZE)),
);

const paginatedIncidents = computed(() => {
  const start = (incidentsPage.value - 1) * PAGE_SIZE;
  return currentIncidents.value.slice(start, start + PAGE_SIZE);
});

// guards
function isGroup(value: PublicStatusPage): value is PublicGroupPage {
  return "monitors" in value;
}

function isMonitor(value: PublicStatusPage): value is PublicMonitorPage {
  return "monitor_id" in value;
}

// helpers
function applyTheme(theme: string | undefined) {
  document.documentElement.classList.toggle("light", theme !== "dark");
}

function statusLabel(status: PublicStatusPage["status"]) {
  return {
    operational: "Operational",
    blocked: "Blocked",
    down: "Major outage",
    unknown: "Unknown",
  }[status];
}

function statusIcon(status: PublicStatusPage["status"]) {
  return {
    operational: "i-mdi-check-circle",
    blocked: "i-mdi-alert-circle",
    down: "i-mdi-close-circle",
    unknown: "i-mdi-help-circle",
  }[status];
}

function overallMessage(status: PublicStatusPage["status"]) {
  return {
    operational: "All systems are operating normally.",
    blocked: "Some requests are being blocked.",
    down: "We are investigating an active outage.",
    unknown: "Status information is currently unavailable.",
  }[status];
}

function monitorMessage(status: PublicStatusPage["status"]) {
  return {
    operational: "This service is operating normally.",
    blocked: "This service is experiencing blocked requests.",
    down: "We are investigating an active outage.",
    unknown: "Status information is currently unavailable.",
  }[status];
}

function checkedAt(timestamp: number | null | undefined) {
  return timestamp
    ? new Date(timestamp * 1000).toLocaleString()
    : "No check recorded";
}

function encodeSlug(slug: string) {
  return globalThis.encodeURIComponent(slug);
}

function formatDateTime(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleString();
}

function uptimeClass(uptime: number | null | undefined): string {
  if (uptime == null) return "";
  if (uptime >= 99) return "text-up";
  if (uptime >= 95) return "text-blocked";
  return "text-down";
}

// lifecycle
async function load() {
  loading.value = true;
  error.value = "";
  incidentsPage.value = 1;

  try {
    page.value = await getPublicStatus(String(route.params.slug || ""));
    applyTheme(page.value?.theme);
  } catch (err) {
    page.value = null;
    error.value =
      err instanceof Error ? err.message : "Unable to load status page";
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  load();
});

watch(() => route.params.slug, load);

watch(
  () => page.value?.theme,
  (t) => applyTheme(t),
);

onBeforeUnmount(() => {
  document.documentElement.classList.remove("light");
});
</script>

<style scoped>
.public-status {
  min-height: 100vh;
  background: var(--base);
  color: var(--text);
}

.public-status-inner {
  width: min(760px, calc(100% - 32px));
  margin: 0 auto;
  padding-top: 28px;
  padding-bottom: 48px;
}

.public-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--border);
  padding-bottom: 20px;
}

.brand {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.16em;
  color: var(--text-secondary);
}

.brand-mark {
  color: var(--accent);
  margin-right: 8px;
}

.refresh {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--text-secondary);
  background: transparent;
  cursor: pointer;
  border: none;

  &:hover {
    color: var(--text);
  }
}

.page-heading {
  padding-top: 32px;
  padding-bottom: 24px;

  h1 {
    font-size: 22px;
    letter-spacing: -0.02em;
  }
}

.eyebrow {
  font-size: 11px;
  letter-spacing: 0.14em;
  font-weight: 700;
  color: var(--text-muted);
  margin-bottom: 10px;
}

.description {
  color: var(--text-secondary);
  margin-top: 12px;
  line-height: 1.6;
}

.overall-card {
  display: flex;
  align-items: center;
  gap: 18px;
  padding: 24px;
  border: 1px solid;
  border-radius: 14px;

  h2 {
    font-size: 15px;
    color: var(--text);
  }

  p {
    font-size: 14px;
    color: var(--text-secondary);
    margin-top: 4px;
  }

  &.status-operational {
    color: var(--up);
    background: color-mix(in srgb, var(--up) 8%, var(--surface));
    border-color: color-mix(in srgb, var(--up) 25%, var(--border));
  }

  &.status-blocked {
    color: var(--blocked);
    background: color-mix(in srgb, var(--blocked) 8%, var(--surface));
    border-color: color-mix(in srgb, var(--blocked) 25%, var(--border));
  }

  &.status-down {
    color: var(--down);
    background: color-mix(in srgb, var(--down) 8%, var(--surface));
    border-color: color-mix(in srgb, var(--down) 25%, var(--border));
  }

  &.status-unknown {
    color: var(--paused);
    background: color-mix(in srgb, var(--paused) 8%, var(--surface));
    border-color: color-mix(in srgb, var(--paused) 25%, var(--border));
  }
}

.status-icon {
  font-size: 20px;
}

.summary-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  margin: 20px 0;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--surface);
}

.summary-item {
  padding: 16px;
  text-align: center;
  border-right: 1px solid var(--border);

  &:last-child {
    border-right: none;
  }

  strong {
    display: block;
    font-size: 20px;
  }

  > span {
    display: block;
    font-size: 12px;
    color: var(--text-muted);
    margin-top: 4px;
  }
}

.text-up,
.text-operational {
  color: var(--up);
}

.text-down {
  color: var(--down);
}

.text-blocked {
  color: var(--blocked);
}

.text-unknown {
  color: var(--paused);
}

.section {
  margin-top: 32px;
}

.section-title {
  font-size: 16px;
  margin-bottom: 12px;
}

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;

  .section-title {
    margin-bottom: 0;
  }
}

.panel-pagination {
  display: flex;
  align-items: center;
  gap: 6px;
}

.page-btn {
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--border);
  background: var(--input);
  color: var(--text);
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.15s;

  &:hover:not(:disabled) {
    border-color: var(--border-hover);
    background: var(--hover);
  }

  &:disabled {
    opacity: 0.4;
    cursor: default;
  }
}

.page-info {
  font-size: 12px;
  color: var(--text-muted);
  font-variant-numeric: tabular-nums;
}

.charts-section {
  margin-bottom: 24px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 16px;
}

.no-incidents {
  font-size: 13px;
  color: var(--text-muted);
  padding: 16px 0;
  text-align: center;
}

.monitor-list,
.incident-list {
  border: 1px solid var(--border);
  border-radius: 12px;
  overflow: hidden;
  background: var(--surface);
}

.monitor-entry {
  border-bottom: 1px solid var(--border);

  &:last-child {
    border-bottom: none;
  }
}

.monitor-row {
  display: flex;
  align-items: center;
  gap: 12px;
  min-height: 60px;
  padding: 12px 16px;
  color: var(--text);
  text-decoration: none;

  &:hover {
    background: var(--hover);
  }
}

.monitor-chart {
  padding: 0 16px 16px;
}

.monitor-light {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}

.light-operational {
  background: var(--up);
}

.light-down {
  background: var(--down);
}

.light-blocked {
  background: var(--blocked);
}

.light-unknown {
  background: var(--paused);
}

.monitor-name {
  flex: 1;
  font-weight: 500;
}

.monitor-time {
  font-size: 12px;
  color: var(--text-muted);
}

.monitor-status {
  font-size: 12px;
  font-weight: 600;
}

.row-arrow {
  color: var(--text-muted);
}

.muted {
  font-size: 13px;
  color: var(--text-muted);
}

.incident-row {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 16px;
  border-bottom: 1px solid var(--border);

  &:last-child {
    border-bottom: none;
  }

  strong {
    display: block;
  }

  span:not(.incident-icon) {
    display: block;
    font-size: 12px;
    color: var(--text-secondary);
    margin-top: 2px;
  }
}

.incident-icon {
  font-size: 14px;

  &.is-down {
    color: var(--down);
  }

  &.is-up {
    color: var(--up);
  }
}

.powered {
  text-align: center;
  font-size: 11px;
  letter-spacing: 0.1em;
  color: var(--text-muted);
  margin-top: 44px;
}

.state-card {
  text-align: center;
  padding: 112px 20px;
  color: var(--text-secondary);

  h1 {
    font-size: 18px;
    color: var(--text);
    margin: 16px 0 8px;
  }
}

.state-icon {
  font-size: 28px;
  color: var(--text-muted);
}

.error-icon {
  color: var(--down);
}

.spinning {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

@media (max-width: 600px) {
  .public-status-inner {
    width: calc(100% - 24px);
    padding-top: 16px;
  }

  .page-heading {
    padding-top: 24px;
  }

  .summary-item {
    padding: 14px 6px;
  }

  .monitor-time {
    display: none;
  }

  .monitor-row {
    padding: 12px;
  }
}
</style>
