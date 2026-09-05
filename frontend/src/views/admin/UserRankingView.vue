<template>
  <AppLayout>
    <div class="space-y-6">
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-gray-900 dark:text-white">{{ t('nav.userRanking') }}</h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">{{ t('admin.ranking.subtitle') }}: {{ periodLabel }}</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <div class="inline-flex rounded-md border border-gray-200 bg-white p-1 dark:border-dark-700 dark:bg-dark-800">
            <button v-for="option in periods" :key="option.value" type="button" class="rounded px-3 py-1.5 text-sm" :class="period === option.value ? 'bg-primary-600 text-white' : 'text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-dark-700'" @click="selectPeriod(option.value)">{{ t(option.label) }}</button>
          </div>
          <DateRangePicker v-if="period === 'custom'" v-model:start-date="startDate" v-model:end-date="endDate" @change="loadRanking" />
        </div>
      </div>

      <section class="card p-4 sm:p-5">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div><h2 class="text-sm font-semibold text-gray-900 dark:text-white">用户端展示控制</h2><p class="mt-1 text-xs text-gray-500 dark:text-gray-400">关闭后用户无法查看排行榜；管理员统计不受影响。</p></div>
          <div class="flex items-center gap-3"><span class="text-sm font-medium" :class="settings.enabled ? 'text-green-700 dark:text-green-300' : 'text-gray-500'">{{ settings.enabled ? '已开启' : '已关闭' }}</span><Toggle v-model="settings.enabled" /></div>
        </div>
        <div class="mt-5 grid grid-cols-1 gap-4 border-t border-gray-100 pt-5 dark:border-dark-700 md:grid-cols-2 xl:grid-cols-4">
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">页面标题<input v-model.trim="settings.title" class="input mt-1" maxlength="60" /></label>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">统计周期<select v-model="settings.period" class="input mt-1"><option value="day">当日</option><option value="week">最近 7 天</option></select></label>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">排行指标<select v-model="settings.metric" class="input mt-1"><option value="tokens">Token</option><option value="requests">请求数</option></select></label>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">展示名额<input v-model.number="settings.limit" type="number" min="3" max="50" class="input mt-1" /></label>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">最低 Token<input v-model.number="settings.minimum_tokens" type="number" min="0" class="input mt-1" /></label>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">最低请求数<input v-model.number="settings.minimum_requests" type="number" min="0" class="input mt-1" /></label>
          <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
            <span>仅展示指定用户</span>
            <p class="mt-1 text-xs font-normal text-gray-500 dark:text-gray-400">留空表示所有用户</p>
            <OpenAIFastPolicyUserSelector v-model="settings.include_user_ids" class="mt-2" />
          </div>
          <div class="text-sm font-medium text-gray-700 dark:text-gray-300">
            <span>排除用户</span>
            <p class="mt-1 text-xs font-normal text-gray-500 dark:text-gray-400">搜索并选择不参与排行榜的用户</p>
            <OpenAIFastPolicyUserSelector v-model="settings.exclude_user_ids" class="mt-2" />
          </div>
        </div>
        <div class="mt-4 flex flex-wrap items-center justify-between gap-3"><label class="flex items-center gap-3 text-sm text-gray-700 dark:text-gray-300"><Toggle v-model="settings.show_platform_breakdown" />展示 OpenAI / Claude 分布</label><button class="btn btn-primary" :disabled="settingsSaving" @click="saveSettings">{{ settingsSaving ? '保存中...' : '保存用户端设置' }}</button></div>
      </section>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div class="card p-4"><p class="text-sm text-gray-500 dark:text-gray-400">{{ t('admin.dashboard.requests') }}</p><p class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">{{ formatNumber(totalRequests) }}</p></div>
        <div class="card p-4"><p class="text-sm text-gray-500 dark:text-gray-400">{{ t('admin.dashboard.tokens') }}</p><p class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">{{ formatNumber(totalTokens) }}</p></div>
        <div class="card p-4"><p class="text-sm text-gray-500 dark:text-gray-400">{{ t('admin.dashboard.actual') }}</p><p class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">${{ totalActualCost.toFixed(4) }}</p></div>
      </div>

      <div class="card overflow-hidden">
        <div v-if="loading" class="flex h-64 items-center justify-center"><LoadingSpinner /></div>
        <div v-else-if="ranking.length === 0" class="flex h-64 items-center justify-center text-sm text-gray-500 dark:text-gray-400">{{ t('admin.dashboard.noDataAvailable') }}</div>
        <div v-else class="overflow-x-auto">
          <table class="w-full min-w-[860px] text-sm">
            <thead class="border-b border-gray-200 bg-gray-50 text-left text-xs text-gray-500 dark:border-dark-700 dark:bg-dark-800 dark:text-gray-400"><tr><th class="px-4 py-3">#</th><th class="px-4 py-3">{{ t('nav.users') }}</th><th class="px-4 py-3 text-right">{{ t('admin.dashboard.requests') }}</th><th class="px-4 py-3 text-right">{{ t('admin.dashboard.tokens') }}</th><th class="px-4 py-3">{{ t('admin.ranking.openai') }}</th><th class="px-4 py-3">{{ t('admin.ranking.claude') }}</th><th class="px-4 py-3 text-right">{{ t('admin.dashboard.actual') }}</th></tr></thead>
            <tbody class="divide-y divide-gray-100 dark:divide-dark-700">
              <tr v-for="(item, index) in ranking" :key="item.user_id" class="text-gray-700 dark:text-gray-200">
                <td class="px-4 py-3 font-medium">{{ index + 1 }}</td>
                <td class="px-4 py-3"><div class="font-medium">{{ displayName(item) }}</div><div v-if="item.email" class="text-xs text-gray-500 dark:text-gray-400">{{ item.email }}</div></td>
                <td class="px-4 py-3 text-right">{{ formatNumber(item.requests) }}</td><td class="px-4 py-3 text-right">{{ formatNumber(item.tokens) }}</td>
                <td class="px-4 py-3"><div class="flex items-center gap-2"><div class="h-2 w-20 overflow-hidden rounded bg-gray-200 dark:bg-dark-700"><div class="h-full bg-emerald-500" :style="{ width: platformPercent(item.openai_tokens, item.tokens) + '%' }" /></div><span class="text-xs">{{ formatNumber(item.openai_tokens) }}</span></div></td>
                <td class="px-4 py-3"><div class="flex items-center gap-2"><div class="h-2 w-20 overflow-hidden rounded bg-gray-200 dark:bg-dark-700"><div class="h-full bg-orange-500" :style="{ width: platformPercent(item.claude_tokens, item.tokens) + '%' }" /></div><span class="text-xs">{{ formatNumber(item.claude_tokens) }}</span></div></td>
                <td class="px-4 py-3 text-right font-medium">${{ item.actual_cost.toFixed(4) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { adminAPI } from '@/api/admin'
import { getLeaderboardSettings, updateLeaderboardSettings, type LeaderboardSettings } from '@/api/leaderboard'
import type { UserSpendingRankingItem } from '@/types'
import AppLayout from '@/components/layout/AppLayout.vue'
import DateRangePicker from '@/components/common/DateRangePicker.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import Toggle from '@/components/common/Toggle.vue'
import OpenAIFastPolicyUserSelector from '@/views/admin/settings/OpenAIFastPolicyUserSelector.vue'

type Period = 'day' | 'week' | 'custom'
const { t } = useI18n()
const period = ref<Period>('day')
const ranking = ref<UserSpendingRankingItem[]>([])
const totalRequests = ref(0)
const totalTokens = ref(0)
const totalActualCost = ref(0)
const loading = ref(false)
const settingsSaving = ref(false)
const settings = ref<LeaderboardSettings>({ enabled: false, title: '使用排行榜', period: 'week', metric: 'tokens', limit: 20, minimum_tokens: 0, minimum_requests: 0, include_user_ids: [], exclude_user_ids: [], show_platform_breakdown: true })
const today = new Date()
const isoDate = (date: Date) => date.toISOString().slice(0, 10)
const startDate = ref(isoDate(today))
const endDate = ref(isoDate(today))
const periods = computed(() => [{ value: 'day' as const, label: 'admin.ranking.day' }, { value: 'week' as const, label: 'admin.ranking.week' }, { value: 'custom' as const, label: 'admin.ranking.custom' }])
const periodLabel = computed(() => `${startDate.value} - ${endDate.value}`)

function setRange(value: Period) {
  const end = new Date()
  const start = new Date(end)
  if (value === 'week') start.setDate(end.getDate() - 6)
  startDate.value = isoDate(start)
  endDate.value = isoDate(end)
}
async function selectPeriod(value: Period) { period.value = value; if (value !== 'custom') setRange(value); await loadRanking() }
async function loadRanking() {
  loading.value = true
  try {
    const response = await adminAPI.dashboard.getUserSpendingRanking({ start_date: startDate.value, end_date: endDate.value, limit: 50 })
    ranking.value = response.ranking ?? []; totalRequests.value = response.total_requests ?? 0; totalTokens.value = response.total_tokens ?? 0; totalActualCost.value = response.total_actual_cost ?? 0
  } catch (error) { console.error('Failed to load user ranking:', error); ranking.value = [] } finally { loading.value = false }
}
async function loadSettings() { try { settings.value = await getLeaderboardSettings() } catch (error) { console.error('Failed to load leaderboard settings:', error) } }
async function saveSettings() { settingsSaving.value = true; try { settings.value = await updateLeaderboardSettings({ ...settings.value }) } catch (error) { console.error('Failed to save leaderboard settings:', error) } finally { settingsSaving.value = false } }
function formatNumber(value: number) { return new Intl.NumberFormat().format(value) }
function displayName(item: UserSpendingRankingItem) { return item.username || item.email || `#${item.user_id}` }
function platformPercent(tokens: number, total: number) { return total > 0 ? Math.min(100, Math.round(tokens / total * 100)) : 0 }
onMounted(() => { setRange('day'); void loadRanking(); void loadSettings() })
</script>
