#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container.sh"

ENG_DIR="${1:?usage: htb_service_enum.sh <engagement_dir> <target_ip> <port/protocol>}"
TARGET="${2:?usage: htb_service_enum.sh <engagement_dir> <target_ip> <port/protocol>}"
PORT_PROTO="${3:?}"

mkdir -p "$ENG_DIR/scans" "$ENG_DIR/downloads"

port="${PORT_PROTO%%/*}"
service_name=$(echo "$PORT_PROTO" | grep -oP '\d+/\w+/\K.+')

echo "--- Enumerating $TARGET:$PORT_PROTO ---"

case "$PORT_PROTO" in
  */tcp/ssh|*/tcp/SSH)
    nmap -Pn -sV --script ssh-auth-methods,ssh2-enum-algos,ssh-hostkey -p "$port" \
      -oN "$ENG_DIR/scans/ssh_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/http|*/tcp/https|*/tcp/http-proxy|*/tcp/HTTP*|*/tcp/HTTPS*)
    scheme="http"
    echo "$PORT_PROTO" | grep -q "https" && scheme="https"
    "$SCRIPT_DIR/htb_web_enum.sh" "$ENG_DIR" "$TARGET" "$port" "$scheme" &
    ;;
  */tcp/ftp|*/tcp/FTP)
    nmap -Pn -sV --script ftp-anon,ftp-bounce,ftp-libopie,ftp-proftpd-backdoor,ftp-vsftpd-backdoor,ftp-vuln-cve2010-4221 -p "$port" \
      -oN "$ENG_DIR/scans/ftp_${port}_enum.txt" "$TARGET"
    curl -s "ftp://$TARGET:$port/" --max-time 10 > "$ENG_DIR/scans/ftp_${port}_listing.txt" 2>&1 || true
    ;;
  */tcp/smb|*/tcp/netbios-ssn|*/tcp/microsoft-ds)
    nmap -Pn -sV --script smb-os-discovery,smb-protocols,smb-security-mode,smb2-security-mode,smb-enum-shares,smb-enum-users -p "$port" \
      -oN "$ENG_DIR/scans/smb_${port}_enum.txt" "$TARGET"
    smbclient -L "//$TARGET/" -N -p "$port" > "$ENG_DIR/scans/smbclient_shares_${port}.txt" 2>&1 || true
    enum4linux-ng -A "$TARGET" -oJ "$ENG_DIR/scans/enum4linux_${port}.json" 2>&1 > "$ENG_DIR/scans/enum4linux_${port}.txt" || true
    ;;
  */tcp/ldap|*/tcp/ldaps)
    ldapsearch -x -H "ldap://$TARGET:$port" -s base -b "" \
      defaultNamingContext dnsHostName rootDomainNamingContext \
      > "$ENG_DIR/scans/ldap_${port}_rootdse.txt" 2>&1 || true
    ;;
  */tcp/msrpc|*/tcp/wsman|*/tcp/WinRM)
    nmap -Pn -sV --script msrpc-enum -p "$port" -oN "$ENG_DIR/scans/msrpc_${port}.txt" "$TARGET"
    ;;
  */tcp/mysql|*/tcp/mssql|*/tcp/postgresql|*/tcp/oracle)
    nmap -Pn -sV --script "${port%%/*}"-* -p "$port" -oN "$ENG_DIR/scans/db_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/ms-sql*|*/tcp/MSSQL*)
    nmap -Pn -sV --script ms-sql-* -p "$port" -oN "$ENG_DIR/scans/mssql_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/rdp|*/tcp/ms-wbt-server)
    nmap -Pn -sV --script rdp-ntlm-info -p "$port" -oN "$ENG_DIR/scans/rdp_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/kerberos|*/tcp/kerberos-sec)
    nmap -Pn -sV --script krb5-enum-users -p "$port" -oN "$ENG_DIR/scans/krb5_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/domain|*/tcp/dns|*/tcp/DNS)
    dig @"$TARGET" -p "$port" +short . AXFR > "$ENG_DIR/scans/dns_axfr_${port}.txt" 2>&1 || true
    ;;
  */tcp/rpcbind|*/tcp/nfs|*/tcp/nlockmgr)
    showmount -e "$TARGET" > "$ENG_DIR/scans/showmount_${port}.txt" 2>&1 || true
    ;;
  */tcp/vnc|*/tcp/VNC)
    nmap -Pn -sV --script vnc-info,realvnc-auth-bypass -p "$port" -oN "$ENG_DIR/scans/vnc_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/telnet|*/tcp/TELNET)
    nmap -Pn -sV --script telnet-encryption,telnet-ntlm-info -p "$port" -oN "$ENG_DIR/scans/telnet_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/pop3|*/tcp/imap|*/tcp/smtp|*/tcp/submission)
    nmap -Pn -sV --script "${port%%/*}"-* -p "$port" -oN "$ENG_DIR/scans/mail_${port}_enum.txt" "$TARGET"
    ;;
  */tcp/redis|*/tcp/mongod|*/tcp/memcache)
    nmap -Pn -sV --script "${port%%/*}"-info -p "$port" -oN "$ENG_DIR/scans/nosql_${port}_enum.txt" "$TARGET"
    ;;
  */udp/*)
    nmap -Pn -sU -sV --script default -p "$port" -oN "$ENG_DIR/scans/udp_${port}_enum.txt" "$TARGET"
    ;;
  *)
    nmap -Pn -sV -sC -p "$port" -oN "$ENG_DIR/scans/service_${port}_enum.txt" "$TARGET"
    ;;
esac

"$SCRIPT_DIR/htb_state.py" set "$ENG_DIR" services_enumerated \
  --append "$PORT_PROTO" 2>/dev/null || true

echo "  Done enumerating $PORT_PROTO"
