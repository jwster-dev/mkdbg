#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
VERSION_OUT="${TMP_DIR}/version.out"
DOCTOR_OUT="${TMP_DIR}/doctor.out"
LIST_OUT="${TMP_DIR}/list.out"
TARGET_LIST_OUT="${TMP_DIR}/target_list.out"
ATTACH_OUT="${TMP_DIR}/attach.out"
ATTACH_ERR="${TMP_DIR}/attach.err"
RUN_OUT="${TMP_DIR}/run.out"
WATCH_OUT="${TMP_DIR}/watch.out"
CAPTURE_DRY_OUT="${TMP_DIR}/capture_dry.out"
CAPTURE_JSON_OUT="${TMP_DIR}/capture.json"
CAPTURE_STDOUT="${TMP_DIR}/capture.stdout"
PROBE_HALT_OUT="${TMP_DIR}/probe_halt.out"
PROBE_FLASH_OUT="${TMP_DIR}/probe_flash.out"
PROBE_READ32_OUT="${TMP_DIR}/probe_read32.out"
PROBE_WRITE32_OUT="${TMP_DIR}/probe_write32.out"
BIN_DIR="${TMP_DIR}/bin"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

python3 -m py_compile "${ROOT_DIR}/tools/mkdbg"
python3 "${ROOT_DIR}/tools/mkdbg" --version > "${VERSION_OUT}"
python3 - "${VERSION_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "mkdbg 0.1.0" not in text:
    raise SystemExit(f"missing version output: {text!r}")
PY

mkdir -p "${BIN_DIR}"
cat > "${BIN_DIR}/openocd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${BIN_DIR}/arm-none-eabi-gdb" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${BIN_DIR}/openocd" "${BIN_DIR}/arm-none-eabi-gdb"

pushd "${TMP_DIR}" >/dev/null
mkdir -p build tools
: > build/MicroKernel_MPU.elf
: > tools/openocd.cfg

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" init \
  --name microkernel \
  --port /dev/ttyACM0 >/dev/null

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" doctor --target microkernel > "${DOCTOR_OUT}"
python3 - "${DOCTOR_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "[mkdbg] ok      config: ",
    "[mkdbg] ok      root: ",
    "[mkdbg] ok      repo: microkernel",
    "[mkdbg] ok      port: /dev/ttyACM0",
    "[mkdbg] ok      build_cmd: bash",
    "[mkdbg] ok      flash_cmd: bash",
    "[mkdbg] ok      hil_cmd: bash",
    "[mkdbg] ok      snapshot_cmd: python3",
    "[mkdbg] ok      elf_path: ",
    "[mkdbg] ok      openocd_cfg: ",
    "[mkdbg] ok      openocd: openocd",
    "[mkdbg] ok      gdb: arm-none-eabi-gdb",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected doctor output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" attach \
  --target microkernel \
  --dry-run \
  --break main \
  --command continue \
  --command bt \
  --batch > "${ATTACH_OUT}"
python3 - "${ATTACH_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "[mkdbg] cwd=",
    "[mkdbg] openocd=openocd -f ",
    "[mkdbg] gdb=arm-none-eabi-gdb ",
    "MicroKernel_MPU.elf",
    "-batch",
    "-ex 'break main'",
    "-ex continue",
    "-ex bt",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected attach output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" target add tahoe \
  --path . \
  --attach-cmd "gdb build/tahoe.elf" >/dev/null
if PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" attach tahoe --dry-run --break main > /dev/null 2> "${ATTACH_ERR}"; then
  echo "mkdbg_host_tests: expected attach_cmd override to reject scripted flags" >&2
  exit 1
fi

python3 - "${ATTACH_ERR}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = "attach_cmd cannot be combined with --break, --command, or --batch"
if needle not in text:
    raise SystemExit(f"missing expected error text: {needle}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" target add demo \
  --path . \
  --preset generic \
  --build-cmd "echo build" \
  --flash-cmd "echo flash" \
  --default >/dev/null

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" repo list > "${LIST_OUT}"
python3 - "${LIST_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "* demo\tpreset=generic\tpath=",
    "  microkernel\tpreset=microkernel-mpu\tpath=",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected repo list output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" target use microkernel > /dev/null
PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" target list > "${TARGET_LIST_OUT}"
python3 - "${TARGET_LIST_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "* microkernel\tpreset=microkernel-mpu\tpath=",
    "  demo\tpreset=generic\tpath=",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected target list output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" run --target demo --dry-run -- echo smoke > "${RUN_OUT}"
python3 - "${RUN_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "[mkdbg] cwd=",
    "[mkdbg] cmd=echo smoke",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected run output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" target add rootfixture \
  --path "${ROOT_DIR}" \
  --preset microkernel-mpu >/dev/null
PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" watch --target rootfixture \
  --bundle-json tests/fixtures/triage/sample_bundle.json \
  --render-once \
  --width 100 \
  --height 32 > "${WATCH_OUT}"
python3 - "${WATCH_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "[mkdbg] cwd=",
    "[mkdbg] cmd=",
    "bringup_ui.py",
    "MicroKernel-MPU Bringup Console",
    "failure=early_resource_fault",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected watch output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" capture bundle --target microkernel \
  --dry-run > "${CAPTURE_DRY_OUT}"
python3 - "${CAPTURE_DRY_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "[mkdbg] cwd=",
    "[mkdbg] cmd=",
    "triage_bundle.py",
    "--port /dev/ttyACM0",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected capture dry-run output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" capture bundle --target rootfixture \
  --source-log tests/fixtures/triage/sample_snapshot.log \
  --output "${CAPTURE_JSON_OUT}" \
  --json > "${CAPTURE_STDOUT}"
python3 - "${CAPTURE_JSON_OUT}" "${CAPTURE_STDOUT}" <<'PY'
import json
import sys
from pathlib import Path

bundle = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
stdout_lines = [line for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if line.strip()]
json_lines = [line for line in stdout_lines if line.lstrip().startswith("{")]
if not json_lines:
    raise SystemExit("expected capture json summary line")
summary = json.loads(json_lines[-1])
if bundle.get("ok") is not True:
    raise SystemExit("expected capture bundle ok=true")
if summary.get("ok") is not True:
    raise SystemExit("expected capture summary ok=true")
if summary.get("bundle_path") != sys.argv[1]:
    raise SystemExit("bundle path mismatch")
if summary.get("fault_slices", 0) < 1:
    raise SystemExit("expected capture fault_slices >= 1")
if bundle.get("dependency", {}).get("target_driver") != "sensor":
    raise SystemExit("expected capture target driver sensor")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" probe halt --target microkernel --dry-run > "${PROBE_HALT_OUT}"
python3 - "${PROBE_HALT_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "[mkdbg] cwd=",
    "[mkdbg] cmd=openocd -f ",
    "reset halt; shutdown",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected probe halt output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" probe flash --target microkernel --dry-run > "${PROBE_FLASH_OUT}"
python3 - "${PROBE_FLASH_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "[mkdbg] cmd=openocd -f ",
    "program /",
    "MicroKernel_MPU.elf",
    "verify reset exit",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected probe flash output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" probe read32 --target microkernel --dry-run 0xE000ED28 > "${PROBE_READ32_OUT}"
python3 - "${PROBE_READ32_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "mdw 0xe000ed28",
    "shutdown",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected probe read32 output: {item}")
PY

PATH="${BIN_DIR}:${PATH}" python3 "${ROOT_DIR}/tools/mkdbg" probe write32 --target microkernel --dry-run 0xE000ED24 0x700 > "${PROBE_WRITE32_OUT}"
python3 - "${PROBE_WRITE32_OUT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
checks = [
    "mww 0xe000ed24 0x00000700",
    "shutdown",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"missing expected probe write32 output: {item}")
PY

INSTALL_DIR="${TMP_DIR}/install"
MKDBG_INSTALL_DIR="${INSTALL_DIR}" bash "${ROOT_DIR}/tools/install_mkdbg.sh" > /dev/null
test -x "${INSTALL_DIR}/mkdbg"

popd >/dev/null
echo "mkdbg_host_tests: OK"
