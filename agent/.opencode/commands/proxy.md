# Command: Proxy Control

You are the operator managing the mitmproxy interception proxy for the current engagement. The user's arguments specify the action: `start` or `stop`.

## Step 1: Locate Active Engagement

Find the active engagement via `resolve_engagement_dir`:

```bash
source scripts/lib/engagement.sh
ENG_DIR=$(resolve_engagement_dir "$(pwd)")
echo "Engagement: $ENG_DIR"
```

If no engagement directory exists, inform the user to run `/engage` first and stop.

## Step 2: Parse Action

Read the user's arguments appended below this template. Expect one of:
- `start` — launch the local mitmproxy process
- `stop` — terminate the local mitmproxy process

If no action is provided, default to `start`.

## Action: Start

```bash
source scripts/lib/container.sh
export ENGAGEMENT_DIR="$ENG_DIR"
start_proxy
```

This starts local `mitmdump` with the engagement directory configured so `proxy_addon.py`
can write to `cases.db` and `auth.json`.

Tell the user: "Proxy listening on port 8080. Configure browser proxy: http://127.0.0.1:8080"

## Action: Stop

```bash
source scripts/lib/container.sh
stop_proxy
```

This stops the local mitmproxy process for the active engagement.

## User Arguments

The action and any additional options from the user follows:
