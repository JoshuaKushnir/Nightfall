# Nightfall CI Setup Guide

This guide covers setting up the Roblox Open Cloud CI system for Nightfall.

## 🚀 GitHub Repository Configuration

Before the first run, add these settings in GitHub (**Settings** → **Secrets and variables** → **Actions**):

### 🔑 Repository Secrets
| Secret Name | Description | Required Scopes |
|---|---|---|
| `RBLX_OC_API_KEY` | Open Cloud API Key | `luau-execution-sessions:write` |

### 📊 Repository Variables
| Variable Name | Description |
|---|---|
| `RBLX_UNIVERSE_ID` | Your Roblox Universe ID |
| `RBLX_PLACE_ID` | Your Roblox Place ID |

## 📁 System Architecture

- `ci/run_tests.lua`: The Luau test runner sent to Roblox for execution.
- `ci/poll_task.py`: Python script that submits the runner, polls for completion, and exits with 0 or 1.
- `.github/workflows/ci.yml`: GitHub Actions workflow that triggers on push/PR.

## 🛠️ Usage

### Adding a Test
Drop any `*.test.lua` file into `tests/unit/`. The runner picks it up automatically based on the mapping in `default.project.json`.

### Skipping a Test Case
Rename the file to `*.test.lua.skip` to skip an entire file.

### Local Execution (Manual)
If you have the environment variables set locally:
```bash
env RBLX_OC_API_KEY="..." RBLX_UNIVERSE_ID="..." RBLX_PLACE_ID="..." python3 ci/poll_task.py
```

## 📐 Project-Specific Configuration
The `default.project.json` file maps the `tests/` folder to `game.ServerScriptService.tests`. 

The source of truth for the test folder location is `findTestsFolder()` in `ci/run_tests.lua`.
