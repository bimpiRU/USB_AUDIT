#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURE="${SCRIPT_DIR}/fixtures/nmap_sample.txt"

echo "[*] Testing linux_audit.sh with sample Nmap log..."

# Run analyzer and capture output
output=$(cat "${FIXTURE}" | bash "${PROJECT_DIR}/linux_audit.sh")

# Check key expected strings
checks=(
    "Верифицирован активный сетевой узел: 172.22.64.1"
    "Верифицирован активный сетевой узел: 192.168.1.1"
    "Верифицирован активный сетевой узел: 10.0.0.5"
    "SMB (Port 445)"
    "RDP (Port 3389)"
    "веб-интерфейс (Port 80)"
    "ГИБРИДНЫЙ АУДИТ ЗАВЕРШЕН"
)

failed=0
for item in "${checks[@]}"; do
    if echo "${output}" | grep -qF "${item}"; then
        echo "[PASS] Found: ${item}"
    else
        echo "[FAIL] Missing: ${item}"
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    echo "[-] Some tests failed."
    exit 1
fi

echo "[+] All linux_audit.sh tests passed."
