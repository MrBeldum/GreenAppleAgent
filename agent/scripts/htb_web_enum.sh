#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container.sh"

ENG_DIR="${1:?usage: htb_web_enum.sh <engagement_dir> <target_ip> <port> <scheme>}"
TARGET="${2:?}"
PORT="${3:?}"
SCHEME="${4:-http}"
BASE="${SCHEME}://${TARGET}:${PORT}"

mkdir -p "$ENG_DIR/scans" "$ENG_DIR/downloads"

echo "=== WEB ENUM: $BASE ==="

echo "--- Headers ---"
sudo -n -E curl -sI "$BASE" --max-time 15 > "$ENG_DIR/downloads/headers_${PORT}.txt" 2>&1 || true
cat "$ENG_DIR/downloads/headers_${PORT}.txt" 2>/dev/null || echo "(no response)"

echo "--- Raw HTML ---"
sudo -n -E curl -sL "$BASE" --max-time 20 -o "$ENG_DIR/downloads/root_${PORT}.html" 2>&1 || true
if [[ -f "$ENG_DIR/downloads/root_${PORT}.html" ]]; then
  SIZE=$(wc -c < "$ENG_DIR/downloads/root_${PORT}.html")
  echo "  Downloaded: $SIZE bytes"
else
  echo "  Download failed"
fi

echo "--- Technology Fingerprint ---"
whatweb "$BASE" > "$ENG_DIR/scans/whatweb_${PORT}.txt" 2>&1 || echo "(whatweb skipped)"

echo "--- HTML Deep Inspection ---"
if [[ -f "$ENG_DIR/downloads/root_${PORT}.html" ]]; then
  python3 -c "
import re, sys, json
try:
    with open('$ENG_DIR/downloads/root_${PORT}.html', 'r', errors='ignore') as f:
        html = f.read()
except Exception as e:
    sys.stderr.write(f'Read error: {e}\n')
    sys.exit(0)

out = {'size': len(html), 'findings': {}}

comments = re.findall(r'<!--(.*?)-->', html, re.DOTALL)
out['findings']['html_comments'] = [c.strip()[:300] for c in comments if c.strip()][:20]

scripts = re.findall(r'<script[^>]*src=[\"\']([^\"\']+)[\"\']', html, re.I)
out['findings']['script_srcs'] = list(set(scripts))[:30]

styles = re.findall(r'<link[^>]*href=[\"\']([^\"\']+)[\"\']', html, re.I)
out['findings']['css_links'] = list(set(styles))[:30]

hidden = re.findall(r'<input[^>]*type=[\"\']hidden[\"\'][^>]*>', html, re.I)
out['findings']['hidden_inputs'] = hidden[:15]

next_data = re.search(r'<script[^>]*id=[\"\']__NEXT_DATA__[\"\'][^>]*>(.*?)</script>', html, re.DOTALL)
if next_data:
    out['findings']['__NEXT_DATA___present'] = True
    try:
        nd = json.loads(next_data.group(1))
        out['findings']['__NEXT_DATA___keys'] = list(nd.keys())[:20] if isinstance(nd, dict) else str(type(nd))
    except:
        out['findings']['__NEXT_DATA___parse_error'] = True

inline_scripts = re.findall(r'<script[^>]*>(.*?)</script>', html, re.DOTALL)
inline_text = '\n'.join(s for s in inline_scripts if s.strip() and 'src=' not in s)[:5000]
out['findings']['inline_script_preview'] = inline_text[:2000] if inline_text else ''

base64_strings = re.findall(r'[\"\'][A-Za-z0-9+/=]{32,}[\"\']', html)
out['findings']['base64_candidates'] = [s.strip('\"\\'')[:80] for s in base64_strings[:20]]

data_attrs = re.findall(r'data-[a-z-]+=[\"\'][^\"\']+[\"\']', html, re.I)
out['findings']['data_attributes'] = list(set(data_attrs))[:30]

meta_refs = re.findall(r'<meta[^>]+content=[\"\'][^\"\']+[\"\']', html, re.I)
out['findings']['meta_tags'] = meta_refs[:15]

a_hrefs = re.findall(r'<a[^>]+href=[\"\']([^\"\']+)[\"\']', html, re.I)
out['findings']['hrefs'] = list(set(h for h in a_hrefs if not h.startswith('#') and not h.startswith('javascript:')))[:30]

form_actions = re.findall(r'<form[^>]+action=[\"\']([^\"\']+)[\"\']', html, re.I)
out['findings']['form_actions'] = list(set(form_actions))[:15]

with open('$ENG_DIR/scans/html_deep_${PORT}.json', 'w') as f:
    json.dump(out, f, indent=2)

print(f'Wrote html_deep_${PORT}.json with {sum(len(v) if isinstance(v, list) else 1 for v in out[\"findings\"].values())} findings')
" 2>/dev/null || true
fi

echo "--- Download JS/CSS files ---"
if [[ -f "$ENG_DIR/downloads/root_${PORT}.html" ]]; then
  python3 -c "
import re, os, subprocess, sys, urllib.parse
with open('$ENG_DIR/downloads/root_${PORT}.html', 'r', errors='ignore') as f:
    html = f.read()
urls = set()
for pat in [r'src=[\"\']([^\"\']+\.js)[\"\']', r'href=[\"\']([^\"\']+\.css)[\"\']']:
    for m in re.findall(pat, html, re.I):
        if not m.endswith(('.map',)):
            urls.add(m)
downloaded = 0
for url in list(urls)[:30]:
    if not url.startswith('http'):
        url = urllib.parse.urljoin('$BASE', url)
    fname = re.sub(r'[^a-zA-Z0-9_.-]', '_', url.split('/')[-1] or 'index')
    dest = f'$ENG_DIR/downloads/web_{fname}'
    try:
        subprocess.run(['sudo', '-n', '-E', 'curl', '-sL', '--max-time', '15', '-o', dest, url],
                       timeout=20, capture_output=True)
        if os.path.getsize(dest) > 100:
            downloaded += 1
    except: pass
print(f'Downloaded {downloaded} JS/CSS files')
" 2>/dev/null || true
fi

echo "--- Source Artifact Summaries ---"
for f in "$ENG_DIR"/downloads/web_*; do
  [[ -f "$f" ]] || continue
  "$SCRIPT_DIR/source_artifact_summary.py" "$f" --limit 30 2>/dev/null || true
done

echo "--- Directory Fuzzing ---"
ffuf -u "$BASE/FUZZ" \
  -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt \
  -ac -t 50 -timeout 10 \
  -o "$ENG_DIR/scans/ffuf_dirs_${PORT}.json" -of json 2>&1 || \
  ffuf -u "$BASE/FUZZ" \
    -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt \
    -ac -t 50 -timeout 10 \
    -o "$ENG_DIR/scans/ffuf_dirs_${PORT}.json" -of json 2>&1 || true

echo "--- Info-Disclosure Probe ---"
cat > "$ENG_DIR/scans/info_probe_wordlist_${PORT}.txt" <<'ENDPROBE'
metrics
actuator
actuator/health
actuator/env
env
.env
.git/config
debug
trace
elmah.axd
phpinfo.php
_debug
server-status
server-info
.well-known/security.txt
robots.txt
sitemap.xml
crossdomain.xml
.DS_Store
backup
config
admin
swagger.json
openapi.json
graphql
api-docs
health
info
version
status
ftp
uploads
api
ENDPROBE

ffuf -u "$BASE/FUZZ" \
  -w "$ENG_DIR/scans/info_probe_wordlist_${PORT}.txt" \
  -ac -t 25 -timeout 8 \
  -o "$ENG_DIR/scans/ffuf_infodisc_${PORT}.json" -of json 2>&1 || true

"$SCRIPT_DIR/htb_state.py" set "$ENG_DIR" source_analysis_done true 2>/dev/null || true

echo "=== WEB ENUM COMPLETE ==="
