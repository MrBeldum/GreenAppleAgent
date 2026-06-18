---
name: parameter-fuzzing
description: Discover hidden parameters, test values, and identify input handling anomalies
origin: GreenAppleAgent
---

# Parameter Fuzzing

## When to Activate

- Endpoint needs parameter testing or hidden/debug parameter discovery
- IDOR, access control, or logic bug testing via parameter manipulation
- API accepts unknown parameters

## Tools

`run_tool ffuf` (primary), `run_tool curl` (verification), `run_tool arjun` (dedicated param discovery, if available)

## Autonomous wordlist guardrail

Always search for and use host wordlists first. Standard Parrot/Kali paths
include `/usr/share/seclists/Discovery/Web-Content/burp-parameter-names.txt`,
`/usr/share/wordlists/dirb/common.txt`, and others. Pass exact known host
wordlist paths directly to `run_tool ffuf`. Only build a small workspace-local
wordlist under `$DIR/scans/` as a fallback when no suitable host wordlist exists.
Never make up tiny wordlists from scratch when a real corpus is on the host. Do
not recursively glob broad host wordlist directories just to discover candidate
files, and never write outputs outside `$DIR`.

```bash
PARAM_WORDLIST="$DIR/scans/param-wordlist.txt"
cat > "$PARAM_WORDLIST" <<'EOF'
id
user
userId
accountId
orderId
debug
test
admin
role
redirect
returnUrl
next
callback
token
csrf
apiKey
query
search
limit
offset
sort
filter
EOF
```

## Methodology

### 1. Establish Baseline
```bash
run_tool curl -s -o /dev/null -w "Code: %{http_code}, Size: %{size_download}" https://TARGET/endpoint
```
Record baseline response size for `-fs` filter.

### 2. GET Parameter Discovery
```bash
run_tool ffuf -u "https://TARGET/endpoint?FUZZ=test" \
  -w "$PARAM_WORDLIST" -fs BASELINE_SIZE
# Or with auto-calibration: -ac
```

### 3. POST Parameter Discovery
```bash
# URL-encoded
run_tool ffuf -u "https://TARGET/endpoint" -X POST -d "FUZZ=test" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -w "$PARAM_WORDLIST" -fs BASELINE_SIZE
# JSON
run_tool ffuf -u "https://TARGET/endpoint" -X POST -d '{"FUZZ":"test"}' \
  -H "Content-Type: application/json" \
  -w "$PARAM_WORDLIST" -fs BASELINE_SIZE
```

### 4. Value Fuzzing
```bash
run_tool ffuf -u "https://TARGET/endpoint?id=FUZZ" -w <(seq 1 1000) -fs BASELINE_SIZE  # IDOR
printf '%s\n' "'" '"' '<' '>' '../' '{{7*7}}' '${7*7}' 'true' 'false' 'null' > "$DIR/scans/value-fuzz.txt"
run_tool ffuf -u "https://TARGET/endpoint?param=FUZZ" -w "$DIR/scans/value-fuzz.txt" -fs BASELINE_SIZE
# Boolean/toggle: test true,false,1,0,yes,no,null via loop
# Role values: admin,root,user,guest,superadmin via loop
```

### 5. Header Fuzzing
```bash
run_tool ffuf -u "https://TARGET/endpoint" -H "FUZZ: test" \
  -w "$PARAM_WORDLIST" -fs BASELINE_SIZE
# Common bypass headers:
for header in "X-Forwarded-For: 127.0.0.1" "X-Real-IP: 127.0.0.1" "X-Original-URL: /admin" \
  "X-Debug: true" "X-Debug-Mode: 1" "X-Forwarded-Host: localhost"; do
  run_tool curl -s -o /dev/null -w "%{http_code} %{size_download}" -H "$header" "https://TARGET/endpoint"
done
```

### 6. Cookie Fuzzing
```bash
run_tool ffuf -u "https://TARGET/endpoint" -b "FUZZ=test" \
  -w "$PARAM_WORDLIST" -fs BASELINE_SIZE
```

### 7. Multi-Parameter / Clusterbomb
```bash
run_tool ffuf -u "https://TARGET/endpoint?W1=W2" -w params.txt:W1 -w values.txt:W2 \
  -mode clusterbomb -fs BASELINE_SIZE
```

### 8. Arjun
```bash
run_tool arjun -u "https://TARGET/endpoint" -m GET    # or POST, JSON
run_tool arjun -u "https://TARGET/endpoint" -w custom_params.txt
```

### 9. Verification
```bash
run_tool curl -sv "https://TARGET/endpoint?discovered_param=test" 2>&1
diff <(run_tool curl -s "https://TARGET/endpoint") <(run_tool curl -s "https://TARGET/endpoint?param=value")
```
