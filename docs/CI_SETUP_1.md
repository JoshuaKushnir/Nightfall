# CI/CD Setup — Roblox Open Cloud Luau Execution

Tests run headlessly against your live place on every push to `main` and every
pull request. No Studio required.

---

## How it works

```
git push
  └─▶ GitHub Actions (.github/workflows/ci.yml)
        └─▶ python3 ci/poll_task.py
              ├─ POSTs ci/run_tests.lua to Roblox Open Cloud API
              ├─ Roblox spins up a server, loads the place, runs the script
              ├─ Polls until COMPLETE (up to 5 min)
              └─ Exits 0 (pass) or 1 (fail) → GitHub marks PR green/red
```

---

## One-time setup

### 1. Create an Open Cloud API key

1. Go to [create.roblox.com/credentials](https://create.roblox.com/credentials)
2. Create a new API key
3. Under **Access Permissions**, add the **Engine API** permission with scope `luau-execution-sessions:write` for your experience
4. Copy the key

### 2. Add GitHub secrets & variables

In your repo: **Settings → Secrets and variables → Actions**

| Type     | Name                  | Value                          |
|----------|-----------------------|--------------------------------|
| Secret   | `RBLX_OC_API_KEY`     | Your API key from step 1       |
| Variable | `RBLX_UNIVERSE_ID`    | Your experience's universe ID  |
| Variable | `RBLX_PLACE_ID`       | The place ID to test against   |
| Variable | `RBLX_PLACE_VERSION`  | *(optional)* pin to a version  |

### 3. Place the CI files

```
your-repo/
├── ci/
│   ├── run_tests.lua     ← Luau runner (sent to Roblox)
│   └── poll_task.py      ← Python poller
└── .github/
    └── workflows/
        └── ci.yml
```

### 4. Check your Rojo sync target

Open `ci/run_tests.lua` and find the `findTestsFolder()` function near the top.
Make sure the candidates list matches where Rojo syncs `tests/unit/` in your
`default.project.json`. The default assumption is `ServerScriptService.tests.unit`.

---

## Running locally

```bash
export RBLX_OC_API_KEY="your-key-here"
export RBLX_UNIVERSE_ID="12345678"
export RBLX_PLACE_ID="98765432"

python3 ci/poll_task.py
```

All CLI flags mirror the env vars if you prefer:

```bash
python3 ci/poll_task.py \
  --api-key      path/to/key.txt \
  --universe     12345678 \
  --place        98765432 \
  --script-file  ci/run_tests.lua \
  --log-file     /tmp/task_logs.txt
```

---

## Adding a new test

1. Create `tests/unit/MyFeature.test.lua` using either supported format:

**Format A — table return (preferred for new tests):**
```lua
return {
    name = "MyFeature Tests",
    tests = {
        {
            name = "does the thing",
            fn = function()
                assert(1 + 1 == 2, "math broke")
            end,
        },
        {
            name = "skip this for now",
            skip = true,      -- ← set skip = true to opt out without deleting
            fn = function() end,
        },
    },
}
```

**Format B — self-executing (compatible with existing AshExpression-style files):**
```lua
-- just print results and error on failure — runner wraps in pcall automatically
local ok = doSomething()
assert(ok, "it failed")
```

2. That's it. No changes to `ci.yml`, `poll_task.py`, or `run_tests.lua` needed.

---

## Skipping a whole file

Rename the file from `Foo.test.lua` to `Foo.test.lua.skip`.
The runner will log it as skipped and move on.

---

## Rotating the API key

1. Generate a new key on [create.roblox.com/credentials](https://create.roblox.com/credentials)
2. Update `RBLX_OC_API_KEY` in **Settings → Secrets → Actions**
3. Revoke the old key
4. No code changes needed

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Could not locate tests/unit folder` | Check `findTestsFolder()` in `run_tests.lua` matches your Rojo sync path |
| `HTTP 403` from API | API key missing `luau-execution-sessions:write` scope for the correct experience |
| Task stuck in `PROCESSING` > 5 min | Roblox server-side timeout; check for infinite loops in tests |
| Tests pass locally in Studio but fail in CI | A module requires a service that behaves differently headlessly — add a stub |
| `RBLX_PLACE_VERSION` not set, tests run against stale code | Uncomment the Rojo publish step in `ci.yml` to auto-publish before testing |

---

## Using a different Luau script

`poll_task.py` is not tied to `run_tests.lua`. You can point it at any script:

```bash
RBLX_SCRIPT_FILE=ci/my_other_script.lua python3 ci/poll_task.py
```

Or in the workflow, change the `--script-file` flag. This makes the tooling
reusable for any headless Roblox automation, not just tests.
