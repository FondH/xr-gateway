//go:build unit

package service

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/Wei-Shaw/sub2api/internal/config"
	"github.com/stretchr/testify/require"
)

type leaderboardSettingsRepoStub struct {
	values map[string]string
}

func (s *leaderboardSettingsRepoStub) Get(ctx context.Context, key string) (*Setting, error) {
	panic("unexpected Get call")
}

func (s *leaderboardSettingsRepoStub) GetValue(ctx context.Context, key string) (string, error) {
	return s.values[key], nil
}

func (s *leaderboardSettingsRepoStub) Set(ctx context.Context, key, value string) error {
	if s.values == nil {
		s.values = map[string]string{}
	}
	s.values[key] = value
	return nil
}

func (s *leaderboardSettingsRepoStub) GetMultiple(ctx context.Context, keys []string) (map[string]string, error) {
	panic("unexpected GetMultiple call")
}

func (s *leaderboardSettingsRepoStub) SetMultiple(ctx context.Context, settings map[string]string) error {
	panic("unexpected SetMultiple call")
}

func (s *leaderboardSettingsRepoStub) GetAll(ctx context.Context) (map[string]string, error) {
	panic("unexpected GetAll call")
}

func (s *leaderboardSettingsRepoStub) Delete(ctx context.Context, key string) error {
	panic("unexpected Delete call")
}

func TestUserLeaderboardSettingsDefaultsAndNormalization(t *testing.T) {
	svc := NewSettingService(&leaderboardSettingsRepoStub{values: map[string]string{}}, &config.Config{})

	settings, err := svc.GetUserLeaderboardSettings(context.Background())
	require.NoError(t, err)
	require.False(t, settings.Enabled)
	require.Equal(t, "Token 排行", settings.Title)
	require.Equal(t, "week", settings.Period)
	require.Equal(t, "tokens", settings.Metric)
	require.Equal(t, 20, settings.Limit)

	updated, err := svc.SetUserLeaderboardSettings(context.Background(), UserLeaderboardSettings{
		Enabled: true, Title: "  本周贡献榜  ", Period: "day", Metric: "requests", Limit: 12,
		IncludeUserIDs: []int64{7, 7, 0, -3, 12}, ExcludeUserIDs: []int64{4, 4, 0},
	})
	require.NoError(t, err)
	require.Equal(t, "本周贡献榜", updated.Title)
	require.Equal(t, []int64{7, 12}, updated.IncludeUserIDs)
	require.Equal(t, []int64{4}, updated.ExcludeUserIDs)

	var stored UserLeaderboardSettings
	require.NoError(t, json.Unmarshal([]byte(svc.settingRepo.(*leaderboardSettingsRepoStub).values[SettingKeyUserLeaderboard]), &stored))
	require.Equal(t, updated, stored)
}

func TestUserLeaderboardSettingsMigratesPreviousDefaultTitle(t *testing.T) {
	stored, err := json.Marshal(UserLeaderboardSettings{Title: "使用排行榜", Period: "week", Metric: "tokens", Limit: 20})
	require.NoError(t, err)

	svc := NewSettingService(&leaderboardSettingsRepoStub{values: map[string]string{SettingKeyUserLeaderboard: string(stored)}}, &config.Config{})
	settings, err := svc.GetUserLeaderboardSettings(context.Background())
	require.NoError(t, err)
	require.Equal(t, "Token 排行", settings.Title)
}

func TestUserLeaderboardSettingsRejectInvalidControls(t *testing.T) {
	for name, settings := range map[string]UserLeaderboardSettings{
		"invalid period":   {Period: "month"},
		"invalid metric":   {Metric: "cost"},
		"invalid limit":    {Limit: 51},
		"negative minimum": {MinimumTokens: -1},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := normalizeUserLeaderboardSettings(settings)
			require.Error(t, err)
		})
	}
}
