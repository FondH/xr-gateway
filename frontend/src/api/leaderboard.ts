import { apiClient } from './client'

export type LeaderboardPeriod = 'day' | 'week'
export type LeaderboardMetric = 'tokens' | 'requests'

export interface LeaderboardSettings {
  enabled: boolean
  title: string
  period: LeaderboardPeriod
  metric: LeaderboardMetric
  limit: number
  minimum_tokens: number
  minimum_requests: number
  include_user_ids: number[]
  exclude_user_ids: number[]
  show_platform_breakdown: boolean
}

export interface PublicLeaderboardConfig extends Pick<LeaderboardSettings, 'enabled' | 'title' | 'period' | 'metric' | 'limit' | 'show_platform_breakdown'> {}

export interface PublicLeaderboardItem {
  rank: number
  display_name: string
  is_me: boolean
  requests: number
  tokens: number
  openai_requests?: number
  openai_tokens?: number
  claude_requests?: number
  claude_tokens?: number
}

export interface PublicLeaderboardResponse {
  config: PublicLeaderboardConfig
  items: PublicLeaderboardItem[]
  my_rank: PublicLeaderboardItem | null
  start_date: string
  end_date: string
}

export async function getPublicLeaderboard(): Promise<PublicLeaderboardResponse> {
  const { data } = await apiClient.get<PublicLeaderboardResponse>('/usage/leaderboard')
  return data
}

export async function getLeaderboardSettings(): Promise<LeaderboardSettings> {
  const { data } = await apiClient.get<LeaderboardSettings>('/admin/user-ranking/config')
  return data
}

export async function updateLeaderboardSettings(settings: LeaderboardSettings): Promise<LeaderboardSettings> {
  const { data } = await apiClient.put<LeaderboardSettings>('/admin/user-ranking/config', settings)
  return data
}
