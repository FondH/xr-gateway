package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

const SettingKeyUserLeaderboard = "user_leaderboard_settings"

// UserLeaderboardSettings controls the user-facing leaderboard without exposing
// billing data or user contact details.
type UserLeaderboardSettings struct {
	Enabled               bool    `json:"enabled"`
	Title                 string  `json:"title"`
	Period                string  `json:"period"`
	Metric                string  `json:"metric"`
	Limit                 int     `json:"limit"`
	MinimumTokens         int64   `json:"minimum_tokens"`
	MinimumRequests       int64   `json:"minimum_requests"`
	IncludeUserIDs        []int64 `json:"include_user_ids"`
	ExcludeUserIDs        []int64 `json:"exclude_user_ids"`
	ShowPlatformBreakdown bool    `json:"show_platform_breakdown"`
}

func defaultUserLeaderboardSettings() UserLeaderboardSettings {
	return UserLeaderboardSettings{
		Enabled: false, Title: "使用排行榜", Period: "week", Metric: "tokens", Limit: 20,
		ShowPlatformBreakdown: true, IncludeUserIDs: []int64{}, ExcludeUserIDs: []int64{},
	}
}

func (s *SettingService) GetUserLeaderboardSettings(ctx context.Context) (UserLeaderboardSettings, error) {
	settings := defaultUserLeaderboardSettings()
	raw, err := s.settingRepo.GetValue(ctx, SettingKeyUserLeaderboard)
	if err != nil || strings.TrimSpace(raw) == "" {
		return settings, nil
	}
	if err := json.Unmarshal([]byte(raw), &settings); err != nil {
		return UserLeaderboardSettings{}, fmt.Errorf("parse user leaderboard settings: %w", err)
	}
	return normalizeUserLeaderboardSettings(settings)
}

func (s *SettingService) SetUserLeaderboardSettings(ctx context.Context, settings UserLeaderboardSettings) (UserLeaderboardSettings, error) {
	normalized, err := normalizeUserLeaderboardSettings(settings)
	if err != nil {
		return UserLeaderboardSettings{}, err
	}
	raw, err := json.Marshal(normalized)
	if err != nil {
		return UserLeaderboardSettings{}, fmt.Errorf("marshal user leaderboard settings: %w", err)
	}
	if err := s.settingRepo.Set(ctx, SettingKeyUserLeaderboard, string(raw)); err != nil {
		return UserLeaderboardSettings{}, fmt.Errorf("save user leaderboard settings: %w", err)
	}
	return normalized, nil
}

func normalizeUserLeaderboardSettings(settings UserLeaderboardSettings) (UserLeaderboardSettings, error) {
	defaults := defaultUserLeaderboardSettings()
	settings.Title = strings.TrimSpace(settings.Title)
	if settings.Title == "" {
		settings.Title = defaults.Title
	}
	if len([]rune(settings.Title)) > 60 {
		return UserLeaderboardSettings{}, fmt.Errorf("leaderboard title must be 60 characters or less")
	}
	if settings.Period == "" {
		settings.Period = defaults.Period
	}
	if settings.Period != "day" && settings.Period != "week" {
		return UserLeaderboardSettings{}, fmt.Errorf("leaderboard period must be day or week")
	}
	if settings.Metric == "" {
		settings.Metric = defaults.Metric
	}
	if settings.Metric != "tokens" && settings.Metric != "requests" {
		return UserLeaderboardSettings{}, fmt.Errorf("leaderboard metric must be tokens or requests")
	}
	if settings.Limit == 0 {
		settings.Limit = defaults.Limit
	}
	if settings.Limit < 3 || settings.Limit > 50 {
		return UserLeaderboardSettings{}, fmt.Errorf("leaderboard limit must be between 3 and 50")
	}
	if settings.MinimumTokens < 0 || settings.MinimumRequests < 0 {
		return UserLeaderboardSettings{}, fmt.Errorf("leaderboard minimums cannot be negative")
	}
	settings.IncludeUserIDs = normalizeLeaderboardUserIDs(settings.IncludeUserIDs)
	settings.ExcludeUserIDs = normalizeLeaderboardUserIDs(settings.ExcludeUserIDs)
	return settings, nil
}

func normalizeLeaderboardUserIDs(values []int64) []int64 {
	seen := make(map[int64]struct{}, len(values))
	out := make([]int64, 0, len(values))
	for _, id := range values {
		if id > 0 {
			if _, ok := seen[id]; !ok {
				seen[id] = struct{}{}
				out = append(out, id)
			}
		}
	}
	return out
}
