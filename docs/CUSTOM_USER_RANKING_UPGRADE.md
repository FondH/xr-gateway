# User Ranking Customization Upgrade Guide

The user ranking page and user-menu controls are deliberately implemented as one small customization on top of the upstream project. They do not add database tables or migrations, and extend the existing `GET /api/v1/admin/dashboard/users-ranking` response without removing or renaming any existing fields. The administrator keeps the complete internal ranking, while authenticated users receive a privacy-safe ranking with masked names and no email, user ID, or cost fields.

## Keep it separate

Commit this feature on a dedicated branch before taking an upstream update:

```powershell
git switch -c user-ranking-custom
git add .gitignore backend/update_sub2api.bat backend/internal/handler/usage_handler.go backend/internal/pkg/usagestats/usage_log_types.go backend/internal/repository/usage_log_repo_trend.go backend/internal/repository/usage_log_repo_request_type_test.go backend/internal/server/routes/admin.go backend/internal/server/routes/user.go backend/internal/service/leaderboard_settings.go backend/internal/service/leaderboard_settings_test.go backend/internal/service/usage_service.go frontend/src/api/admin/settings.ts frontend/src/api/leaderboard.ts frontend/src/components/charts/ModelDistributionChart.vue frontend/src/components/layout/AppSidebar.vue frontend/src/i18n/locales/en/admin/overview.ts frontend/src/i18n/locales/en/common.ts frontend/src/i18n/locales/zh/admin/overview.ts frontend/src/i18n/locales/zh/common.ts frontend/src/router/index.ts frontend/src/stores/app.ts frontend/src/types/index.ts frontend/src/utils/featureFlags.ts frontend/src/views/admin/SettingsView.vue frontend/src/views/admin/UserRankingView.vue frontend/src/views/user/LeaderboardView.vue docs/CUSTOM_USER_RANKING_UPGRADE.md
git commit -m "feat: add user leaderboard customization"
```

Do not include local runtime files such as `backend/logs/`, `backend/run_sub2api.bat`, or `lzc/` in this commit. Include `backend/update_sub2api.bat`: it is the part that automatically rebases this customization during future official upgrades.

## Update from upstream

The supplied `backend/update_sub2api.bat` detects the current branch. On `user-ranking-custom` it fetches the official source and automatically runs the rebase before rebuilding; on `main` it performs a fast-forward-only update. Use the script for ordinary upgrades.

If you need to perform the update manually, rebase the custom branch onto the official source:

```powershell
git fetch origin
git switch user-ranking-custom
git rebase origin/main
```

If Git reports a conflict, resolve only the affected integration point, then continue:

```powershell
git add <resolved-file>
git rebase --continue
```

The standalone page (`frontend/src/views/admin/UserRankingView.vue`) should normally apply without conflict. Upstream changes are most likely to touch the route, sidebar, translation, or ranking repository files.

## Verification after every upgrade

```powershell
cd backend
go test ./internal/repository ./internal/handler/admin
cd ../frontend
pnpm typecheck
pnpm build
```

The administrator endpoint remains private. The user endpoint is `GET /api/v1/usage/leaderboard`, available only after the administrator enables the feature. Each user-facing row includes total usage together with OpenAI and Claude/Anthropic request and token counts for the selected date range, but never includes email, user ID, or cost.
