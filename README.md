# Claude Code Status Line

Status line for Claude Code that displays quota usage in real time.

## Example

```
🔋 ~6h 45m · 27% ♻️1h 25m · 16% ♻️3d 12h · 🧠 45k/200k (22%)
```

## Components

| Component | Description |
|-----------|-------------|
| `🔋`/`🪫` | Battery indicator (on pace / too fast) |
| `~6h 45m` | Estimated time until 100% usage at current pace |
| `27%` | Usage percentage in 5-hour window (colored) |
| `♻️1h 25m` | Time until 5-hour window reset |
| `16%` | Usage percentage in 7-day window |
| `♻️3d 12h` | Time remaining until 7-day window reset |
| `🧠 45k/200k (22%)` | Context window usage (current/max tokens and percentage) |
| `⬆️ update available` | Local clone is behind its tracked branch |
| `✅ updated` | Auto-update applied the latest version |

## Battery Indicator

| Emoji | Meaning |
|-------|---------|
| 🔋 | On pace or slower — you'll make it |
| 🪫 | Faster than sustainable — may run out |

## Percentage Colors

The 5-hour percentage is colored based on pace:

- **Green**: On pace or below
- **Yellow**: Up to 30% faster
- **Orange**: Between 30% and 60% faster
- **Red**: More than 60% faster

## Understanding Pace

The script compares your actual usage against the "ideal" uniform consumption rate. If you have a 5-hour window and consume evenly, you'd use 20% per hour.

**Pace deviation** measures how far ahead or behind you are:

```
deviation = (usage% - time%) / time% × 100
```

### Examples

| Time elapsed | Usage | Deviation | Meaning |
|--------------|-------|-----------|---------|
| 50% (2.5h) | 50% | 0% | Perfect pace |
| 50% (2.5h) | 75% | +50% | Using 50% faster than ideal |
| 50% (2.5h) | 25% | -50% | Using 50% slower than ideal |
| 20% (1h) | 40% | +100% | Using twice as fast |

A positive deviation means you're consuming faster than sustainable. A negative deviation means you have room to spare.

## Dependencies

- `jq` - For JSON parsing
- `curl` - For API calls
- `security` - To get Claude Code token (included in macOS)

## Installation

1. Make sure you have `jq` installed:
   ```bash
   brew install jq
   ```

2. Add to `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/path/to/statusline.sh"
     }
   }
   ```

## Choosing Segments

By default the status line shows all four segments. You can choose which ones
to display, and in what order, with the `CLAUDE_STATUSLINE_SEGMENTS` environment
variable (comma-separated). Set it in your shell config (`~/.zshrc`,
`~/.bashrc`, `~/.config/fish/config.fish`, etc.).

| Segment | Output | Description |
|---------|--------|-------------|
| `pace` | `🔋 ~6h 45m` | Battery indicator + estimated autonomy |
| `five_hour` | `27% ♻️1h 25m` | 5-hour window usage and reset |
| `seven_day` | `16% ♻️3d 12h` | 7-day window usage and reset |
| `context` | `🧠 45k/200k (22%)` | Context window usage |

```bash
# Everything (default)
export CLAUDE_STATUSLINE_SEGMENTS="pace,five_hour,seven_day,context"

# Just the current 5-hour usage
export CLAUDE_STATUSLINE_SEGMENTS="five_hour"

# Pace plus what's consumed so far
export CLAUDE_STATUSLINE_SEGMENTS="pace,five_hour"

# Just the context window
export CLAUDE_STATUSLINE_SEGMENTS="context"
```

Unknown or empty segments are ignored.

## Update Check

If the script is inside a git repository, it fetches the remote in the
background (at most once a day) and shows `⬆️ update available` when your branch
is behind.
It only fetches — pulling is up to you (`git pull`). Skipped without a git
repository or an upstream branch.

To update automatically, set `CLAUDE_STATUSLINE_AUTO_UPDATE=1` in your shell
config. Once a fetch has revealed a new version, it resets the clone to the
remote (`git reset --hard @{u}`, instant) and shows `✅ updated`. This discards
any local changes to the clone — only enable it if you use the repository purely
to run the status line.

## Error States

When the script can't fetch usage data, it shows a gray message with the context window info still visible:

| Error | Message | Cause |
|-------|---------|-------|
| No session | `⚠️ No session` | No OAuth token found in Keychain |
| Rate limited | `⚠️ API rate limited` | API returned an error or rate limit |
| Other | `⚠️ Error API` | Unexpected API error |

## How It Works

1. Gets the OAuth token from Claude Code via macOS Keychain
2. Calls the Anthropic API to get usage data
3. Caches the response to avoid excessive calls
4. Calculates pace deviation by comparing usage% vs elapsed time%
5. Displays formatted information with ANSI colors

## License

MIT
