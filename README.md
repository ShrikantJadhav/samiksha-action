# Samiksha Evidence Review

A GitHub Action that runs [`samiksha`](https://github.com/ShrikantJadhav/samiksha) on a pull request and writes an evidence-backed verdict to the job summary and, optionally, as a PR comment.

Samiksha is the interpretive layer above [`blast`](https://github.com/ShrikantJadhav/blast): it runs a deterministic scan first, then three narrow passes — intent vs. diff, weakened checks, and capabilities/data — audits any dismissals, and consolidates a verdict. Blast is a hard floor: a critical finding or score ≥ 75 forces `UNSOUND`; a high finding or score ≥ 50 forces at least `CONCERNS`. The model can be more severe, never less.

**Advisory by default.** It never fails the job unless you set `fail-on-verdict`, and it never auto-merges anything.

## Quick start (advisory)

```yaml
name: Samiksha review

on:
  pull_request:

permissions:
  contents: read
  pull-requests: write # only needed when comment: true

jobs:
  samiksha:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: ShrikantJadhav/samiksha-action@v1
        with:
          base: origin/${{ github.event.pull_request.base.ref }}
          model: gpt-4o-mini
          intent: ${{ github.event.pull_request.title }}
          comment: "true"
        env:
          SAMIKSHA_API_KEY: ${{ secrets.SAMIKSHA_API_KEY }}
```

`fetch-depth: 0` matters: Samiksha and Blast need the base ref to build the diff.

## Inputs

| Input | Default | Description |
|---|---|---|
| `base` | `origin/main` | Git ref to diff against. |
| `model` | `""` | Model id. Falls back to `SAMIKSHA_MODEL` / `OPENAI_MODEL`. |
| `base-url` | `""` | OpenAI-compatible base URL. Falls back to `SAMIKSHA_BASE_URL` / `OPENAI_BASE_URL`. |
| `api-key` | `""` | API key. Falls back to `SAMIKSHA_API_KEY` / `OPENAI_API_KEY`. |
| `intent` | PR title | What the change claims to do. |
| `fail-on-verdict` | `""` | Fail at this verdict or worse: `SOUND`, `CONCERNS`, `UNSOUND`. Empty = advisory. |
| `comment` | `false` | Post the full review as a PR comment. |
| `token` | `${{ github.token }}` | Token used for comments. |
| `allow-run` | `false` | Let the agent execute shell commands. **Off by default.** |
| `pass-steps` | `3` | Tool rounds per specialist pass. |
| `single-agent` | `false` | Use the old single-loop reviewer for A/B tests. |
| `show-passes` | `false` | Print each specialist report to stderr. |
| `version` | `latest` | Go version query for the Samiksha CLI. |
| `blast-version` | `latest` | Go version query for the Blast CLI. |

### Turning it into a gate

Set a verdict floor, then mark the `Samiksha review / samiksha` check as required in branch protection:

```yaml
- uses: ShrikantJadhav/samiksha-action@v1
  with:
    model: gpt-4o-mini
    fail-on-verdict: UNSOUND # or CONCERNS for a stricter gate
```

Ranking is `SOUND < CONCERNS < UNSOUND`. `NO_CHANGES` and `UNKNOWN` never fail an unset floor; with a floor set, `UNKNOWN` fails so a broken model call cannot silently pass.

## Outputs

| Output | Example | Description |
|---|---|---|
| `verdict` | `UNSOUND` | `SOUND`, `CONCERNS`, `UNSOUND`, `NO_CHANGES`, or `UNKNOWN`. |
| `review-path` | `/home/runner/work/_temp/samiksha-review.md` | Raw Markdown review on the runner. |
| `failed` | `false` | Whether the verdict met `fail-on-verdict`. |

## Local / self-hosted models

The CLI talks to any OpenAI-compatible chat-completions endpoint. For a self-hosted runner with Ollama:

```yaml
- uses: ShrikantJadhav/samiksha-action@v1
  with:
    model: qwen2.5:7b
    base-url: http://localhost:11434/v1
    intent: ${{ github.event.pull_request.title }}
```

There is no API key for Ollama. GitHub-hosted runners do not have Ollama by default; use a self-hosted runner or an endpoint your runner can reach.

## Tools and safety

- `blast_scan`, `read_file`, and `search` are read-only and always available.
- `allow-run: false` is the default. Only turn it on if you want the reviewer to run existing commands/tests in the checkout.
- The reviewer writes a review. It does not commit, push, approve, merge, or edit code.
- Treat model output as advisory until you have measured false positives on your own PR traffic.

## Recommended rollout

1. Run both `blast-action` and this action with advisory settings for 1–2 weeks.
2. Compare the verdicts with what humans actually flagged.
3. Turn on the deterministic Blast gate first.
4. Add `fail-on-verdict: UNSOUND` for Samiksha once the signal is trusted.

## Local smoke test

With Go 1.23+, Ollama running, and a patch to review:

```sh
GOBIN=/tmp/samiksha-bin go install github.com/ShrikantJadhav/blast/cmd/blast@latest
GOBIN=/tmp/samiksha-bin go install github.com/ShrikantJadhav/samiksha/cmd/samiksha@latest
PATH="/tmp/samiksha-bin:$PATH" \
  INPUT_MODEL=qwen2.5:7b \
  INPUT_BASE_URL=http://localhost:11434/v1 \
  BASE=HEAD~1 \
  BLAST_BIN=/tmp/samiksha-bin/blast \
  PR_TITLE="fix session lookup" \
  FAIL_ON="" DO_COMMENT=false \
  RUNNER_TEMP=/tmp \
  GITHUB_OUTPUT=/tmp/output.txt \
  GITHUB_STEP_SUMMARY=/tmp/summary.md \
  bash scripts/review.sh
```

## License

MIT.
