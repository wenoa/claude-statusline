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

## Configuration

The script has configurable constants at the beginning of the file:

| Setting | Default | Description |
|---------|---------|-------------|
| Cache TTL | 60s | Seconds between API calls |
| Cache file | `/tmp/claude-usage-cache.json` | Path to cache file |
| Low usage threshold | 20% | Below this, always show green |
| Relaxed pace | -20% | Below this deviation, relaxed pace |
| Good pace | 0% | At or below, show 🔋 and green |
| Fast pace | 30% | At or below, show 🪫 and yellow |
| Critical pace | 60% | Above, show 🪫 and orange/red |
| Green zone | 7% | Last % of window shows green regardless |

## Dependencies

- `jq` - For JSON parsing
- `curl` - For API calls
- `security` - To get Claude Code token (included in macOS)

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
