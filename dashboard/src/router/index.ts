import { createRouter, createWebHistory } from 'vue-router'
import { h } from 'vue'
import { nodeRole } from '~stores/app'

const layouts: Record<string, () => Promise<any>> = {
  default: () => import('~layouts/Default.vue'),
}

async function wrapPage(pageModule: any): Promise<any> {
  const page = pageModule.default
  const name = page.layout ?? 'default'

  if (name === null || name === 'none') return page

  const loader = layouts[name]
  if (!loader) {
    throw new Error(
      `Layout "${name}" not found. Available: ${Object.keys(layouts).join(', ')}`
    )
  }

  const mod = await loader()
  const layout = mod.default
  return { render: () => h(layout, null, { default: () => h(page) }) }
}

const routes = [
  {
    path: '/status/:slug',
    component: () => import('~pages/PublicStatus.vue'),
  },
  {
    path: '/',
    component: () => import('~pages/Dashboard.vue').then(wrapPage),
  },
  {
    path: '/monitors',
    component: () => import('~pages/Monitors.vue').then(wrapPage),
  },
  {
    path: '/settings',
    component: () => import('~pages/Settings.vue').then(wrapPage),
    meta: { checkerHidden: true },
  },
  {
    path: '/status-pages',
    component: () => import('~pages/StatusPages.vue').then(wrapPage),
    meta: { checkerHidden: true },
  },
  {
    path: '/notifications',
    component: () => import('~pages/Notifications.vue').then(wrapPage),
    meta: { checkerHidden: true },
  },
  {
    path: '/nodes',
    component: () => import('~pages/Nodes.vue').then(wrapPage),
    meta: { checkerHidden: true },
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach((to) => {
  if (nodeRole.value === 'checker' && to.meta?.checkerHidden) return '/'
  if (nodeRole.value === 'checker' && to.path === '/') return '/monitors'
})

router.onError((err) => {
  console.error('Router error:', err)
})

export default router
