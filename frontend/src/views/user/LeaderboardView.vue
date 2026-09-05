<template>
  <AppLayout>
    <div class="mx-auto max-w-6xl space-y-5">
      <div class="relative overflow-hidden border border-blue-100 bg-white px-5 py-6 dark:border-blue-900/40 dark:bg-dark-900 sm:px-7">
        <div class="absolute inset-y-0 left-0 w-1 bg-primary-600" />
        <div class="relative flex flex-wrap items-start justify-between gap-4">
          <div>
            <p class="text-sm font-medium text-primary-700 dark:text-primary-300">{{ periodText }}</p>
            <h1 class="mt-1 text-2xl font-semibold text-gray-900 dark:text-white">{{ data?.config.title || t('nav.leaderboard') }}</h1>
            <p class="mt-2 text-sm text-gray-600 dark:text-gray-300">{{ dateRange }}</p>
          </div>
          <button class="btn btn-secondary" :disabled="loading" aria-label="刷新排行榜" title="刷新排行榜" @click="load"><Icon name="refresh" size="sm" :class="loading ? 'animate-spin' : ''" /></button>
        </div>
      </div>

      <div v-if="disabled" class="card p-10 text-center"><Icon name="trophy" size="lg" class="mx-auto text-gray-400" /><p class="mt-4 text-base font-medium text-gray-900 dark:text-white">排行榜暂未开放</p><p class="mt-1 text-sm text-gray-500 dark:text-gray-400">管理员开启后即可查看本周期排名。</p></div>
      <template v-else>
        <div v-if="loading" class="card flex h-64 items-center justify-center"><LoadingSpinner /></div>
        <template v-else-if="data">
          <section v-if="data.items.length >= 3" class="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <article v-for="item in podium" :key="item.rank" class="border bg-white p-4 dark:border-dark-700 dark:bg-dark-900" :class="item.rank === 1 ? 'border-amber-300 dark:border-amber-600' : 'border-gray-200'">
              <div class="flex items-center justify-between"><span class="text-xs font-semibold text-gray-500">TOP {{ item.rank }}</span><span class="text-xs font-medium text-primary-700 dark:text-primary-300">{{ metricValue(item) }}</span></div>
              <p class="mt-6 text-lg font-semibold text-gray-900 dark:text-white">{{ item.display_name }}</p>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">{{ metricLabel }}</p>
            </article>
          </section>

          <section v-if="data.my_rank" class="border border-primary-200 bg-primary-50 px-4 py-3 dark:border-primary-900/50 dark:bg-primary-950/30"><div class="flex flex-wrap items-center justify-between gap-3"><div><p class="text-xs font-medium text-primary-700 dark:text-primary-300">我的位置</p><p class="mt-0.5 text-lg font-semibold text-gray-900 dark:text-white">第 {{ data.my_rank.rank }} 名</p></div><div class="text-right"><p class="text-sm font-medium text-gray-900 dark:text-white">{{ metricValue(data.my_rank) }}</p><p class="text-xs text-gray-500 dark:text-gray-400">{{ metricLabel }}</p></div></div></section>

          <section class="card overflow-hidden"><div class="border-b border-gray-200 px-4 py-3 dark:border-dark-700"><h2 class="text-sm font-semibold text-gray-900 dark:text-white">完整排名</h2></div><div class="divide-y divide-gray-100 dark:divide-dark-700"><div v-for="item in data.items" :key="item.rank" class="grid grid-cols-[48px_1fr_auto] items-center gap-3 px-4 py-3" :class="item.is_me ? 'bg-primary-50/70 dark:bg-primary-950/20' : ''"><span class="text-sm font-semibold text-gray-500 dark:text-gray-400">{{ item.rank }}</span><div><p class="font-medium text-gray-900 dark:text-white">{{ item.display_name }}</p><p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">{{ formatNumber(item.requests) }} 请求 · {{ formatNumber(item.tokens) }} Token</p><div v-if="data.config.show_platform_breakdown" class="mt-2 flex gap-3 text-xs"><span>OpenAI {{ platformPercent(item.openai_tokens, item.tokens) }}%</span><span>Claude {{ platformPercent(item.claude_tokens, item.tokens) }}%</span></div></div><p class="text-right text-sm font-semibold text-gray-900 dark:text-white">{{ metricValue(item) }}</p></div></div></section>
        </template>
      </template>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { getPublicLeaderboard, type PublicLeaderboardItem, type PublicLeaderboardResponse } from '@/api/leaderboard'
import AppLayout from '@/components/layout/AppLayout.vue'
import Icon from '@/components/icons/Icon.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const { t } = useI18n(); const data = ref<PublicLeaderboardResponse | null>(null); const loading = ref(false); const disabled = ref(false)
const podium = computed(() => data.value?.items.filter(item => item.rank <= 3) ?? [])
const periodText = computed(() => data.value?.config.period === 'day' ? '今日排名' : '本周排名')
const dateRange = computed(() => data.value ? `${data.value.start_date} - ${data.value.end_date}` : '')
const metricLabel = computed(() => data.value?.config.metric === 'requests' ? '请求数' : 'Token')
async function load() { loading.value = true; disabled.value = false; try { data.value = await getPublicLeaderboard() } catch (error: any) { if (error?.response?.status === 403) disabled.value = true; else console.error('Failed to load leaderboard:', error) } finally { loading.value = false } }
function formatNumber(value: number) { return new Intl.NumberFormat().format(value) }
function metricValue(item: PublicLeaderboardItem) { return formatNumber(data.value?.config.metric === 'requests' ? item.requests : item.tokens) }
function platformPercent(value = 0, total: number) { return total > 0 ? Math.round(value / total * 100) : 0 }
onMounted(() => { void load() })
</script>
