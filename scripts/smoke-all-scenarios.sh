#!/bin/zsh
#
# Capture the fixed Phase 1 three-theme, fifteen-scenario harness matrix.
# Real runs own a fresh evidence tree and every process they observe.

set -euo pipefail
umask 077

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Open Island smoke runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root"

# ---------------------------------------------------------------------------
# Fixed contract
# ---------------------------------------------------------------------------
themes=(poured flightDeck halo)
scenarios=(closed sessionList approvalCard questionCard completionCard longCompletionCard diffApprovalCard codexApprovalCard multiQuestionCard subagentsCard subagentsExpanded completedInterrupted completedFailed usageMeters emptyState)
harness_executable="$repo_root/.build/arm64-apple-macosx/debug/OpenIslandApp"
production_app_executable="/Applications/Open Island.app/Contents/MacOS/OpenIslandApp"
approved_evidence_parent="$repo_root/shots/after"
fixed_staging_parent="/private/tmp"
script_executable="/usr/bin/script"
orca_executable="/usr/local/bin/orca"

dry_run=false

usage() {
    cat <<USAGE
Usage: smoke-all-scenarios.sh [--dry-run]

  --dry-run   List the fixed 45-cell serial plan. Performs no build, defaults
               access, process access, GUI launch, Orca call, or filesystem
               write.
  -h, --help  Show this help.

Real runs always execute exactly:
  themes:    poured, flightDeck, halo
  scenarios: closed, sessionList, approvalCard, questionCard, completionCard,
             longCompletionCard, diffApprovalCard, codexApprovalCard,
             multiQuestionCard, subagentsCard, subagentsExpanded,
             completedInterrupted, completedFailed, usageMeters, emptyState
  evidence:  a new unique directory under shots/after
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "smoke-all-scenarios.sh: unsupported argument '$1'; subsets and path overrides are not allowed" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [[ -n "${OPEN_ISLAND_HARNESS_THEMES:-}" ]]; then
    echo "smoke-all-scenarios.sh: OPEN_ISLAND_HARNESS_THEMES is not supported; the matrix is fixed" >&2
    exit 64
fi
if [[ -n "${OPEN_ISLAND_HARNESS_ARTIFACT_DIR:-}" ]]; then
    echo "smoke-all-scenarios.sh: OPEN_ISLAND_HARNESS_ARTIFACT_DIR is not supported; evidence location is fixed" >&2
    exit 64
fi

assert_fixed_matrix() {
    local expected_themes="poured flightDeck halo"
    local expected_scenarios="closed sessionList approvalCard questionCard completionCard longCompletionCard diffApprovalCard codexApprovalCard multiQuestionCard subagentsCard subagentsExpanded completedInterrupted completedFailed usageMeters emptyState"
    [[ "${themes[*]}" == "$expected_themes" && ${#themes[@]} -eq 3 ]] || return 1
    [[ "${scenarios[*]}" == "$expected_scenarios" && ${#scenarios[@]} -eq 15 ]] || return 1
}

assert_fixed_matrix || {
    echo "smoke-all-scenarios.sh: internal matrix contract is not exactly 3 x 15" >&2
    exit 70
}

print_plan() {
    local theme scenario cell_index=0
    echo "DRY-RUN: PLAN ONLY; no cells are executed and no state is accessed"
    echo "PLAN evidence parent: $approved_evidence_parent (not created)"
    for theme in "${themes[@]}"; do
        for scenario in "${scenarios[@]}"; do
            cell_index=$((cell_index + 1))
            printf 'PLAN %02d/45 theme=%s scenario=%s serial=true\n' \
                "$cell_index" "$theme" "$scenario"
        done
    done
    echo "DRY-RUN COMPLETE: 45 cells listed; 0 executed"
}

# Dry-run returns before any evidence, defaults, build, or process helper.
if [[ "$dry_run" == true ]]; then
    print_plan
    exit 0
fi

# ---------------------------------------------------------------------------
# Evidence safety
# ---------------------------------------------------------------------------
repo_root_identity=""
approved_evidence_parent_physical=""
approved_evidence_parent_identity=""
run_nonce=""
run_root=""
run_root_physical=""
run_root_identity=""
runner_manifest_identity=""
cell_nonce=""
cell_started_epoch=""
scenario_dir=""
scenario_dir_physical=""
scenario_dir_identity=""
cell_manifest_identity=""
staging_dir=""
staging_dir_physical=""
staging_dir_identity=""
staging_started_epoch=""
staging_parent_physical=""
staging_parent_identity=""

physical_directory() {
    (cd -P "$1" 2>/dev/null && pwd -P)
}

filesystem_identity() {
    /usr/bin/stat -f '%d:%i' "$1"
}

validate_directory_identity() {
    local path="$1" physical="$2" expected_identity="$3"
    [[ -d "$path" && ! -L "$path" ]] || return 1
    [[ "$(physical_directory "$path")" == "$physical" ]] || return 1
    [[ "$(filesystem_identity "$path")" == "$expected_identity" ]]
}

safe_mkdir_child() {
    local parent="$1" parent_identity="$2" child_name="$3"
    /usr/bin/python3 -c '
import os
import sys

parent, expected, name = sys.argv[1:]
if os.path.basename(name) != name or name in (".", ".."):
    raise SystemExit("unsafe directory basename")
expected_dev, expected_ino = map(int, expected.split(":"))
parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
parent_stat = os.fstat(parent_fd)
if (parent_stat.st_dev, parent_stat.st_ino) != (expected_dev, expected_ino):
    raise SystemExit("parent directory identity mismatch")
os.mkdir(name, mode=0o700, dir_fd=parent_fd)
child_fd = os.open(
    name,
    os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
    dir_fd=parent_fd,
)
child_stat = os.fstat(child_fd)
print(f"{child_stat.st_dev}:{child_stat.st_ino}")
' "$parent" "$parent_identity" "$child_name"
}

safe_write_content() {
    local mode="$1" directory="$2" directory_identity="$3"
    local filename="$4" expected_file_identity="$5" content="$6"
    local encoded
    encoded="$(printf '%s' "$content" | /usr/bin/base64)"
    /usr/bin/python3 -c '
import base64
import os
import sys

mode, directory, expected_dir, name, expected_file, encoded = sys.argv[1:]
if os.path.basename(name) != name or name in (".", ".."):
    raise SystemExit("unsafe output basename")
expected_dir_dev, expected_dir_ino = map(int, expected_dir.split(":"))
dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
dir_stat = os.fstat(dir_fd)
if (dir_stat.st_dev, dir_stat.st_ino) != (expected_dir_dev, expected_dir_ino):
    raise SystemExit("output directory identity mismatch")
if mode == "create":
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
elif mode == "append":
    flags = os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW
else:
    raise SystemExit("invalid writer mode")
fd = os.open(name, flags, 0o600, dir_fd=dir_fd)
file_stat = os.fstat(fd)
if mode == "append":
    expected_file_dev, expected_file_ino = map(int, expected_file.split(":"))
    if (file_stat.st_dev, file_stat.st_ino) != (
        expected_file_dev,
        expected_file_ino,
    ):
        raise SystemExit("output file identity mismatch")
data = base64.b64decode(encoded)
view = memoryview(data)
while view:
    written = os.write(fd, view)
    view = view[written:]
os.fsync(fd)
print(f"{file_stat.st_dev}:{file_stat.st_ino}")
' "$mode" "$directory" "$directory_identity" "$filename" \
        "$expected_file_identity" "$encoded"
}

safe_exec_new_output() {
    local directory="$1" directory_identity="$2" filename="$3"
    shift 3
    /usr/bin/python3 -c '
import os
import sys

directory, expected_dir, name, *command = sys.argv[1:]
if os.path.basename(name) != name or name in (".", ".."):
    raise SystemExit("unsafe output basename")
expected_dev, expected_ino = map(int, expected_dir.split(":"))
dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
dir_stat = os.fstat(dir_fd)
if (dir_stat.st_dev, dir_stat.st_ino) != (expected_dev, expected_ino):
    raise SystemExit("output directory identity mismatch")
fd = os.open(
    name,
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
    0o600,
    dir_fd=dir_fd,
)
os.dup2(fd, 1)
os.dup2(fd, 2)
os.close(fd)
os.close(dir_fd)
os.execv(command[0], command)
' "$directory" "$directory_identity" "$filename" "$@"
}

safe_exec_new_output_replace_process() {
    local directory="$1" directory_identity="$2" filename="$3"
    shift 3
    exec /usr/bin/python3 -c '
import os
import sys

directory, expected_dir, name, *command = sys.argv[1:]
if os.path.basename(name) != name or name in (".", ".."):
    raise SystemExit("unsafe output basename")
expected_dev, expected_ino = map(int, expected_dir.split(":"))
dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
dir_stat = os.fstat(dir_fd)
if (dir_stat.st_dev, dir_stat.st_ino) != (expected_dev, expected_ino):
    raise SystemExit("output directory identity mismatch")
fd = os.open(
    name,
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
    0o600,
    dir_fd=dir_fd,
)
os.dup2(fd, 1)
os.dup2(fd, 2)
os.close(fd)
os.close(dir_fd)
os.execv(command[0], command)
' "$directory" "$directory_identity" "$filename" "$@"
}

create_private_staging_directory() {
    local output
    local -a output_lines
    output="$(/usr/bin/python3 -c '
import os
import pathlib
import stat
import tempfile
import sys

repo = pathlib.Path(sys.argv[1]).resolve(strict=True)
fixed_parent = pathlib.Path(sys.argv[2])
created_path = None
created_identity = None

try:
    if fixed_parent.is_symlink():
        raise RuntimeError("fixed staging parent is a symlink")
    parent = fixed_parent.resolve(strict=True)
    if str(parent) != "/private/tmp":
        raise RuntimeError("fixed staging parent resolved unexpectedly")
    parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    parent_stat = os.fstat(parent_fd)
    parent_mode = stat.S_IMODE(parent_stat.st_mode)
    if (
        not stat.S_ISDIR(parent_stat.st_mode)
        or parent_stat.st_uid != 0
        or not (parent_mode & stat.S_ISVTX)
        or not (parent_mode & stat.S_IWOTH)
    ):
        raise RuntimeError("fixed staging parent permissions are unsafe")

    # An inherited TMPDIR is deliberately irrelevant.
    created_path = pathlib.Path(
        tempfile.mkdtemp(prefix="open-island-matrix-", dir=str(parent))
    )
    created_lstat = os.lstat(created_path)
    created_identity = (created_lstat.st_dev, created_lstat.st_ino)
    if not stat.S_ISDIR(created_lstat.st_mode) or stat.S_ISLNK(created_lstat.st_mode):
        raise RuntimeError("created staging path is not a physical directory")
    os.chmod(created_path, 0o700)
    created = created_path.resolve(strict=True)
    created_stat = os.stat(created, follow_symlinks=False)
    if (created_stat.st_dev, created_stat.st_ino) != created_identity:
        raise RuntimeError("created staging identity changed")
    if stat.S_IMODE(created_stat.st_mode) != 0o700:
        raise RuntimeError("created staging permissions are not 0700")
    if created.parent != parent:
        raise RuntimeError("created staging escaped fixed parent")
    if created == repo or repo in created.parents:
        raise RuntimeError("staging directory is inside repository")
    applications = pathlib.Path("/Applications").resolve(strict=True)
    if created == applications or applications in created.parents:
        raise RuntimeError("staging directory is inside applications")

    print(parent)
    print(f"{parent_stat.st_dev}:{parent_stat.st_ino}")
    print(created)
    print(f"{created_stat.st_dev}:{created_stat.st_ino}")
except Exception:
    if created_path is not None and created_identity is not None:
        try:
            current = os.lstat(created_path)
            if (
                (current.st_dev, current.st_ino) == created_identity
                and stat.S_ISDIR(current.st_mode)
                and not stat.S_ISLNK(current.st_mode)
            ):
                os.rmdir(created_path)
        except FileNotFoundError:
            pass
    raise
' "$repo_root" "$fixed_staging_parent")" || return 1
    output_lines=("${(@f)output}")
    (( ${#output_lines[@]} == 4 )) || return 1
    staging_parent_physical="$output_lines[1]"
    staging_parent_identity="$output_lines[2]"
    staging_dir_physical="$output_lines[3]"
    staging_dir="$staging_dir_physical"
    staging_dir_identity="$output_lines[4]"
    staging_started_epoch="$(date +%s)"
    if ! validate_directory_identity \
        "$staging_parent_physical" \
        "$staging_parent_physical" \
        "$staging_parent_identity" ||
       ! validate_directory_identity \
        "$staging_dir" "$staging_dir_physical" "$staging_dir_identity" ||
       ! assert_not_protected_path "$staging_dir_physical"; then
        remove_private_staging_directory || {
            echo "MANUAL CLEANUP REQUIRED: post-create staging validation failed at exact path '$staging_dir_physical'." >&2
        }
        return 1
    fi
}

safe_copy_staged_file() {
    local filename="$1"
    /usr/bin/python3 -c '
import os
import stat
import sys

source_dir, source_identity, destination_dir, destination_identity, name = sys.argv[1:]
if os.path.basename(name) != name or name in (".", ".."):
    raise SystemExit("unsafe staged basename")
source_dev, source_ino = map(int, source_identity.split(":"))
destination_dev, destination_ino = map(int, destination_identity.split(":"))
source_dir_fd = os.open(
    source_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
)
destination_dir_fd = os.open(
    destination_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
)
source_dir_stat = os.fstat(source_dir_fd)
destination_dir_stat = os.fstat(destination_dir_fd)
if (source_dir_stat.st_dev, source_dir_stat.st_ino) != (source_dev, source_ino):
    raise SystemExit("staging directory identity mismatch")
if (destination_dir_stat.st_dev, destination_dir_stat.st_ino) != (
    destination_dev,
    destination_ino,
):
    raise SystemExit("destination directory identity mismatch")
source_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=source_dir_fd)
source_stat = os.fstat(source_fd)
if not stat.S_ISREG(source_stat.st_mode):
    raise SystemExit("staged artifact is not regular")
destination_fd = os.open(
    name,
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
    0o600,
    dir_fd=destination_dir_fd,
)
while True:
    chunk = os.read(source_fd, 1024 * 1024)
    if not chunk:
        break
    view = memoryview(chunk)
    while view:
        view = view[os.write(destination_fd, view):]
os.fsync(destination_fd)
destination_stat = os.fstat(destination_fd)
print(f"{destination_stat.st_dev}:{destination_stat.st_ino}")
' "$staging_dir_physical" "$staging_dir_identity" \
        "$scenario_dir_physical" "$scenario_dir_identity" "$filename"
}

remove_private_staging_directory() {
    [[ -n "$staging_dir_physical" ]] || return 0
    /usr/bin/python3 -c '
import os
import stat
import sys

path, expected = sys.argv[1:]
expected_dev, expected_ino = map(int, expected.split(":"))
parent, name = os.path.split(path)
parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
dir_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
dir_stat = os.fstat(dir_fd)
if (dir_stat.st_dev, dir_stat.st_ino) != (expected_dev, expected_ino):
    raise SystemExit("staging identity mismatch during cleanup")
for entry in os.listdir(dir_fd):
    entry_stat = os.stat(entry, dir_fd=dir_fd, follow_symlinks=False)
    if not stat.S_ISREG(entry_stat.st_mode):
        raise SystemExit(f"refusing non-regular staging entry: {entry}")
    os.unlink(entry, dir_fd=dir_fd)
current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
if (current.st_dev, current.st_ino) != (expected_dev, expected_ino):
    raise SystemExit("staging path replaced before cleanup")
os.rmdir(name, dir_fd=parent_fd)
' "$staging_dir_physical" "$staging_dir_identity" || return 1
    staging_dir=""
    staging_dir_physical=""
    staging_dir_identity=""
    staging_started_epoch=""
    staging_parent_physical=""
    staging_parent_identity=""
}

path_is_at_or_below() {
    local candidate="$1" ancestor="$2"
    [[ "$candidate" == "$ancestor" || "$candidate" == "$ancestor"/* ]]
}

assert_not_protected_path() {
    local candidate="$1" protected protected_physical
    for protected in "$repo_root/shots/app" "$repo_root/shots/notch"; do
        if [[ -d "$protected" ]]; then
            protected_physical="$(physical_directory "$protected")" || return 1
            if path_is_at_or_below "$candidate" "$protected_physical"; then
                echo "ERROR: physical evidence path is inside protected evidence: $candidate" >&2
                return 1
            fi
        fi
    done
}

create_approved_evidence_parent() {
    local shots_root="$repo_root/shots"
    local shots_physical shots_identity

    if [[ -L "$shots_root" || -L "$approved_evidence_parent" ]]; then
        echo "ERROR: shots or shots/after is a symlink; refusing evidence creation." >&2
        return 1
    fi
    if [[ -e "$shots_root" && ! -d "$shots_root" ]]; then
        echo "ERROR: shots exists but is not a directory." >&2
        return 1
    fi
    repo_root_identity="$(filesystem_identity "$repo_root")" || return 1
    validate_directory_identity "$repo_root" "$repo_root" "$repo_root_identity" || return 1
    if [[ ! -e "$shots_root" ]]; then
        shots_identity="$(safe_mkdir_child "$repo_root" "$repo_root_identity" shots)" || return 1
    else
        shots_identity="$(filesystem_identity "$shots_root")" || return 1
    fi
    shots_physical="$(physical_directory "$shots_root")" || return 1
    [[ "$shots_physical" == "$repo_root/shots" ]] || {
        echo "ERROR: shots physical path is not the repository shots directory." >&2
        return 1
    }
    validate_directory_identity "$shots_root" "$shots_physical" "$shots_identity" || return 1

    if [[ -e "$approved_evidence_parent" && ! -d "$approved_evidence_parent" ]]; then
        echo "ERROR: shots/after exists but is not a directory." >&2
        return 1
    fi
    if [[ ! -e "$approved_evidence_parent" ]]; then
        approved_evidence_parent_identity="$(
            safe_mkdir_child "$shots_physical" "$shots_identity" after
        )" || return 1
    else
        approved_evidence_parent_identity="$(
            filesystem_identity "$approved_evidence_parent"
        )" || return 1
    fi
    [[ ! -L "$approved_evidence_parent" ]] || {
        echo "ERROR: shots/after became a symlink during setup." >&2
        return 1
    }
    approved_evidence_parent_physical="$(
        physical_directory "$approved_evidence_parent"
    )" || return 1
    [[ "$approved_evidence_parent_physical" == "$repo_root/shots/after" ]] || {
        echo "ERROR: shots/after physical path escaped the approved parent." >&2
        return 1
    }
    validate_directory_identity \
        "$approved_evidence_parent" \
        "$approved_evidence_parent_physical" \
        "$approved_evidence_parent_identity" || return 1
    assert_not_protected_path "$approved_evidence_parent_physical"
}

create_fresh_run_root() {
    local run_basename
    create_approved_evidence_parent

    run_nonce="$(/usr/bin/uuidgen)"
    [[ "$run_nonce" =~ '^[A-F0-9-]{36}$' ]] || {
        echo "ERROR: uuidgen returned an invalid nonce." >&2
        return 1
    }
    run_basename="matrix-$(date +%Y%m%d-%H%M%S)-$run_nonce"
    run_root="$approved_evidence_parent/$run_basename"
    [[ ! -e "$run_root" && ! -L "$run_root" ]] || {
        echo "ERROR: generated run root already exists; refusing reuse." >&2
        return 1
    }
    run_root_identity="$(
        safe_mkdir_child \
            "$approved_evidence_parent_physical" \
            "$approved_evidence_parent_identity" \
            "$run_basename"
    )" || {
        echo "ERROR: atomic creation of the unique run root failed." >&2
        return 1
    }
    [[ -d "$run_root" && ! -L "$run_root" ]] || {
        echo "ERROR: fresh run root is not a physical directory." >&2
        return 1
    }
    run_root_physical="$(physical_directory "$run_root")" || return 1
    [[ "${run_root_physical:h}" == "$approved_evidence_parent_physical" ]] || {
        echo "ERROR: fresh run root escaped the approved evidence parent." >&2
        return 1
    }
    validate_directory_identity "$run_root" "$run_root_physical" "$run_root_identity" || return 1
    assert_not_protected_path "$run_root_physical"
}

create_fresh_cell_directory() {
    local theme="$1" scenario="$2"
    local label="$theme-$scenario"
    local cell_parent

    # theme and scenario come only from the fixed literal arrays above.
    scenario_dir="$run_root_physical/$label"
    [[ ! -e "$scenario_dir" && ! -L "$scenario_dir" ]] || {
        echo "ERROR: cell directory already exists; refusing reuse: $scenario_dir" >&2
        return 1
    }
    cell_started_epoch="$(date +%s)"
    scenario_dir_identity="$(
        safe_mkdir_child "$run_root_physical" "$run_root_identity" "$label"
    )" || {
        echo "ERROR: atomic creation of the fresh cell directory failed: $scenario_dir" >&2
        return 1
    }
    [[ -d "$scenario_dir" && ! -L "$scenario_dir" ]] || {
        echo "ERROR: cell path is not a fresh physical directory: $scenario_dir" >&2
        return 1
    }
    scenario_dir_physical="$(physical_directory "$scenario_dir")" || return 1
    cell_parent="${scenario_dir_physical:h}"
    [[ "$cell_parent" == "$run_root_physical" ]] || {
        echo "ERROR: cell physical path escaped its fresh run root." >&2
        return 1
    }
    validate_directory_identity \
        "$scenario_dir" "$scenario_dir_physical" "$scenario_dir_identity" || return 1
    assert_not_protected_path "$scenario_dir_physical"

    cell_nonce="$(/usr/bin/uuidgen)"
    [[ "$cell_nonce" =~ '^[A-F0-9-]{36}$' ]] || {
        echo "ERROR: uuidgen returned an invalid cell nonce." >&2
        return 1
    }
    local manifest_content
    manifest_content="$({
        printf 'run_nonce\t%s\n' "$run_nonce"
        printf 'cell_nonce\t%s\n' "$cell_nonce"
        printf 'theme\t%s\n' "$theme"
        printf 'scenario\t%s\n' "$scenario"
        printf 'cell_started_epoch\t%s\n' "$cell_started_epoch"
        printf 'cell_directory\t%s\n' "$scenario_dir_physical"
        printf 'expected_executable\t%s\n' "$harness_executable"
    })"$'\n'
    cell_manifest_identity="$(
        safe_write_content \
            create "$scenario_dir_physical" "$scenario_dir_identity" \
            cell-manifest.tsv "" "$manifest_content"
    )" || return 1
}

record_process_inventory() {
    local destination="$1"
    # Passive evidence only: no listed PID is selected or signalled.
    [[ "${destination:h}" == "$run_root_physical" ]] || return 1
    validate_directory_identity \
        "$run_root_physical" "$run_root_physical" "$run_root_identity" || return 1
    safe_exec_new_output \
        "$run_root_physical" "$run_root_identity" "${destination:t}" \
        /bin/ps -axo pid=,ppid=,lstart=,comm=
}

write_runner_manifest() {
    local theme scenario manifest_content
    validate_directory_identity \
        "$run_root_physical" "$run_root_physical" "$run_root_identity" || return 1
    manifest_content="$({
        printf 'run_nonce\t%s\n' "$run_nonce"
        printf 'run_root\t%s\n' "$run_root_physical"
        printf 'expected_executable\t%s\n' "$harness_executable"
        printf 'matrix\t3x15\n'
        printf 'serial\ttrue\n'
        for theme in "${themes[@]}"; do
            for scenario in "${scenarios[@]}"; do
                printf 'expected_cell\t%s\t%s\n' "$theme" "$scenario"
            done
        done
    })"$'\n'
    runner_manifest_identity="$(
        safe_write_content \
            create "$run_root_physical" "$run_root_identity" \
            runner-manifest.tsv "" "$manifest_content"
    )"
}

validate_runner_manifest() {
    local manifest="$run_root_physical/runner-manifest.tsv"
    local theme scenario
    validate_directory_identity \
        "$run_root_physical" "$run_root_physical" "$run_root_identity" &&
        [[ -f "$manifest" && ! -L "$manifest" ]] &&
        [[ "$(filesystem_identity "$manifest")" == "$runner_manifest_identity" ]] &&
        /usr/bin/grep -Fqx $'run_nonce\t'"$run_nonce" "$manifest" &&
        /usr/bin/grep -Fqx $'run_root\t'"$run_root_physical" "$manifest" &&
        /usr/bin/grep -Fqx $'matrix\t3x15' "$manifest" &&
        /usr/bin/grep -Fqx $'serial\ttrue' "$manifest" || return 1
    for theme in "${themes[@]}"; do
        for scenario in "${scenarios[@]}"; do
            /usr/bin/grep -Fqx $'expected_cell\t'"$theme"$'\t'"$scenario" "$manifest" || return 1
        done
    done
}

# ---------------------------------------------------------------------------
# Exact process identities
# ---------------------------------------------------------------------------
runner_start_identity="$(/bin/ps -o lstart= -p "$$")"
launcher_pid=""
launcher_ppid=""
launcher_start_identity=""
launcher_comm=""
launcher_arguments=""
launcher_expected_arguments=""
owned_app_pid=""
owned_app_ppid=""
owned_app_start_identity=""
owned_app_comm=""
owned_app_arguments=""
bound_app_pid=""
bound_app_start_identity=""
terminal_unsafe=false
typeset -a production_app_baseline_pids
typeset -a production_app_baseline_start_identities
production_app_baseline_count=0
production_app_baseline_observed=false

pid_is_live() {
    [[ "$1" == <-> ]] && kill -0 "$1" 2>/dev/null
}

process_field() {
    local pid="$1" field="$2"
    /bin/ps -o "$field=" -p "$pid"
}

normalize_start_identity() {
    # `ps -o lstart=` left-pads its fixed-width value. Canonicalize every
    # observation before comparing or recording it so a live, unchanged
    # process cannot fail merely because direct lookup and `ps -ax` use
    # different leading-space padding.
    printf '%s\n' "$1" | /usr/bin/sed -E \
        's/^[[:space:]]+//;s/[[:space:]]+/ /g;s/[[:space:]]+$//'
}

production_app_snapshot() {
    # `comm` is the executable field used for all exact runner PID identity
    # checks. This is passive inventory only: it never selects, signals, or
    # otherwise targets a production process.
    /usr/bin/python3 - "$production_app_executable" <<'PY'
import subprocess
import sys

expected = sys.argv[1]


def normalize_start_identity(value: str) -> str:
    return " ".join(value.split())


result = subprocess.run(
    ["/bin/ps", "-axo", "pid=,lstart=,comm="],
    check=True,
    capture_output=True,
    text=True,
)
for line in result.stdout.splitlines():
    fields = line.split(None, 6)
    if len(fields) != 7:
        continue
    pid, *start_fields, executable = fields
    if pid.isdecimal() and executable == expected:
        print(f"{pid}\t{normalize_start_identity(' '.join(start_fields))}\t{executable}")
PY
}

capture_production_app_baseline() {
    local snapshot entry pid start_identity executable
    local -a entries

    snapshot="$(production_app_snapshot)" || return 1
    if [[ -n "$snapshot" ]]; then
        entries=("${(@f)snapshot}")
    else
        entries=()
    fi
    production_app_baseline_pids=()
    production_app_baseline_start_identities=()

    if (( ${#entries[@]} > 0 )); then
        for entry in "${entries[@]}"; do
            IFS=$'\t' read -r pid start_identity executable <<< "$entry"
            start_identity="$(normalize_start_identity "$start_identity")"
            [[ "$pid" == <-> && -n "$start_identity" &&
               "$executable" == "$production_app_executable" ]] || return 1
            production_app_baseline_pids+=("$pid")
            production_app_baseline_start_identities+=("$start_identity")
        done
    fi
    production_app_baseline_count=${#production_app_baseline_pids[@]}
    production_app_baseline_observed=true
}

record_production_app_baseline() {
    local manifest_content baseline_index

    if [[ "$production_app_baseline_observed" != true ]]; then
        capture_production_app_baseline || return 1
    fi
    validate_directory_identity \
        "$run_root_physical" "$run_root_physical" "$run_root_identity" || return 1

    manifest_content="$({
        printf 'production_app_executable\t%s\n' "$production_app_executable"
        printf 'observation\tbefore-run\n'
        if (( production_app_baseline_count == 0 )); then
            printf 'production_app_baseline\tNONE\n'
        else
            for (( baseline_index = 1; baseline_index <= production_app_baseline_count; baseline_index++ )); do
                printf 'production_app_baseline\t%s\t%s\t%s\n' \
                    "${production_app_baseline_pids[baseline_index]}" \
                    "${production_app_baseline_start_identities[baseline_index]}" \
                    "$production_app_executable"
            done
        fi
        printf 'production_app_baseline_count\t%s\n' \
            "$production_app_baseline_count"
    })"$'\n'
    safe_write_content \
        create "$run_root_physical" "$run_root_identity" \
        production-app-baseline.tsv "" "$manifest_content" >/dev/null || return 1
}

production_app_identity_is_live() {
    local pid="$1" expected_start_identity="$2"
    local actual_start_identity actual_executable
    pid_is_live "$pid" || return 1
    actual_start_identity="$(normalize_start_identity "$(process_field "$pid" lstart)")"
    actual_executable="$(process_field "$pid" comm | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ "$actual_start_identity" == "$expected_start_identity" &&
       "$actual_executable" == "$production_app_executable" ]]
}

run_root_available_for_evidence() {
    [[ -n "$run_root_physical" && -n "$run_root_identity" ]] || return 1
    validate_directory_identity \
        "$run_root_physical" "$run_root_physical" "$run_root_identity"
}

record_production_app_after() {
    local snapshot entry pid start_identity executable manifest_content proof_status=0
    local baseline_index after_index matching_after_index
    local baseline_rows="" after_rows="" proof_rows=""
    local evidence_available=false
    local -a entries after_pids after_start_identities after_executables

    if run_root_available_for_evidence; then
        evidence_available=true
    else
        # The comparison still runs below against the trusted in-memory
        # baseline. With no identity-bound evidence location, never fall back
        # to a caller-controlled path.
        mark_terminal_unsafe "run-root evidence directory is unavailable; production app after-proof is live-only"
        proof_status=1
    fi
    snapshot="$(production_app_snapshot)" || return 1
    if [[ -n "$snapshot" ]]; then
        entries=("${(@f)snapshot}")
    else
        entries=()
    fi

    after_pids=()
    after_start_identities=()
    after_executables=()
    if (( ${#entries[@]} == 0 )); then
        after_rows+=$'production_app_after\tNONE\n'
    else
        for entry in "${entries[@]}"; do
            IFS=$'\t' read -r pid start_identity executable <<< "$entry"
            start_identity="$(normalize_start_identity "$start_identity")"
            [[ "$pid" == <-> && -n "$start_identity" &&
               "$executable" == "$production_app_executable" ]] || return 1
            after_pids+=("$pid")
            after_start_identities+=("$start_identity")
            after_executables+=("$executable")
            after_rows+=$'production_app_after\t'"$pid"$'\t'"$start_identity"$'\t'"$executable"$'\n'
        done
    fi

    if [[ "$production_app_baseline_observed" != true ]]; then
        proof_status=1
        baseline_rows+=$'production_app_baseline\tUNAVAILABLE\n'
        proof_rows+=$'production_app_baseline_capture_proof\tUNAVAILABLE\n'
    elif (( production_app_baseline_count == 0 )); then
        baseline_rows+=$'production_app_baseline\tNONE\n'
        if (( ${#after_pids[@]} == 0 )); then
            proof_rows+=$'production_app_none_baseline_proof\tPASS\n'
        else
            proof_status=1
            proof_rows+=$'production_app_none_baseline_proof\tFAIL\n'
            for (( after_index = 1; after_index <= ${#after_pids[@]}; after_index++ )); do
                proof_rows+=$'production_app_population_proof\t'"${after_pids[after_index]}"$'\tNEW\n'
            done
        fi
    else
        for (( baseline_index = 1; baseline_index <= production_app_baseline_count; baseline_index++ )); do
            pid="${production_app_baseline_pids[baseline_index]}"
            start_identity="${production_app_baseline_start_identities[baseline_index]}"
            baseline_rows+=$'production_app_baseline\t'"$pid"$'\t'"$start_identity"$'\t'"$production_app_executable"$'\n'
            matching_after_index=0
            for (( after_index = 1; after_index <= ${#after_pids[@]}; after_index++ )); do
                if [[ "${after_pids[after_index]}" == "$pid" ]]; then
                    matching_after_index=$after_index
                    break
                fi
            done
            if (( matching_after_index == 0 )); then
                proof_status=1
                proof_rows+=$'production_app_population_proof\t'"$pid"$'\tMISSING\n'
            elif [[ "${after_start_identities[matching_after_index]}" != "$start_identity" ]]; then
                proof_status=1
                proof_rows+=$'production_app_population_proof\t'"$pid"$'\tIDENTITY_CHANGED\n'
            elif production_app_identity_is_live "$pid" "$start_identity"; then
                proof_rows+=$'production_app_baseline_proof\t'"$pid"$'\t'"$start_identity"$'\t'"$production_app_executable"$'\tPASS\n'
            else
                proof_status=1
                proof_rows+=$'production_app_baseline_proof\t'"$pid"$'\t'"$start_identity"$'\t'"$production_app_executable"$'\tFAIL\n'
            fi
        done
        for (( after_index = 1; after_index <= ${#after_pids[@]}; after_index++ )); do
            matching_after_index=0
            for (( baseline_index = 1; baseline_index <= production_app_baseline_count; baseline_index++ )); do
                if [[ "${production_app_baseline_pids[baseline_index]}" == "${after_pids[after_index]}" &&
                      "${production_app_baseline_start_identities[baseline_index]}" == "${after_start_identities[after_index]}" ]]; then
                    matching_after_index=$baseline_index
                    break
                fi
            done
            if (( matching_after_index == 0 )); then
                proof_status=1
                proof_rows+=$'production_app_population_proof\t'"${after_pids[after_index]}"$'\tNEW_OR_CHANGED\n'
            fi
        done
    fi

    if (( ${#after_pids[@]} != production_app_baseline_count )); then
        proof_status=1
        proof_rows+=$'production_app_population_count_proof\tFAIL\n'
    else
        proof_rows+=$'production_app_population_count_proof\tPASS\n'
    fi

    manifest_content="$({
        printf 'production_app_executable\t%s\n' "$production_app_executable"
        printf 'observation\tafter-run\n'
        printf 'production_app_baseline_count\t%s\n' \
            "$production_app_baseline_count"
        printf '%s' "$baseline_rows"
        printf '%s' "$after_rows"
        printf '%s' "$proof_rows"
    })"$'\n'
    if [[ "$evidence_available" == true ]]; then
        safe_write_content \
            create "$run_root_physical" "$run_root_identity" \
            production-app-after.tsv "" "$manifest_content" >/dev/null || return 1
    fi
    return "$proof_status"
}

base64_value() {
    printf '%s' "$1" | /usr/bin/base64
}

mark_terminal_unsafe() {
    local reason="$1"
    terminal_unsafe=true
    # Cleanup invokes this helper after detaching its traps. Keep diagnostics
    # best-effort so a closed stderr cannot abort the remaining restoration
    # and passive-proof steps while errexit is enabled.
    print -u2 -r -- "TERMINAL UNSAFE: $reason" || true
    if [[ -n "$launcher_pid" || -n "$owned_app_pid" ]]; then
        print -u2 -r -- "MANUAL CLEANUP MAY BE REQUIRED: inspect exact recorded launcher PID '${launcher_pid:-none}' and app PID '${owned_app_pid:-none}'. No unvalidated PID will be signalled." || true
    fi
    return 0
}

capture_launcher_identity() {
    local iteration=0
    while (( iteration < 30 )); do
        if pid_is_live "$launcher_pid"; then
            launcher_ppid="$(process_field "$launcher_pid" ppid | tr -d '[:space:]')"
            launcher_start_identity="$(process_field "$launcher_pid" lstart)"
            launcher_comm="$(process_field "$launcher_pid" comm | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            launcher_arguments="$(process_field "$launcher_pid" args)"
            if [[ "$launcher_ppid" == "$$" &&
                  "$launcher_comm" == "$script_executable" &&
                  -n "$launcher_start_identity" &&
                  "$launcher_arguments" == "$launcher_expected_arguments" ]]; then
                return 0
            fi
        fi
        sleep 0.05
        iteration=$((iteration + 1))
    done
    mark_terminal_unsafe "launcher PID $launcher_pid could not be bound to pinned executable, arguments, PPID, and start identity"
    return 1
}

validate_launcher_identity() {
    local actual_ppid actual_start actual_comm actual_arguments
    pid_is_live "$launcher_pid" || return 1
    actual_ppid="$(process_field "$launcher_pid" ppid | tr -d '[:space:]')"
    actual_start="$(process_field "$launcher_pid" lstart)"
    actual_comm="$(process_field "$launcher_pid" comm | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    actual_arguments="$(process_field "$launcher_pid" args)"
    [[ "$actual_ppid" == "$launcher_ppid" &&
       "$actual_ppid" == "$$" &&
       "$actual_start" == "$launcher_start_identity" &&
       "$actual_comm" == "$script_executable" &&
       "$actual_comm" == "$launcher_comm" &&
       "$actual_arguments" == "$launcher_arguments" ]]
}

capture_owned_app_identity() {
    local candidate="$1"
    owned_app_pid="$candidate"
    owned_app_ppid="$(process_field "$owned_app_pid" ppid | tr -d '[:space:]')"
    owned_app_start_identity="$(process_field "$owned_app_pid" lstart)"
    owned_app_comm="$(process_field "$owned_app_pid" comm | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    owned_app_arguments="$(process_field "$owned_app_pid" args)"
    [[ "$owned_app_ppid" == "$launcher_pid" &&
       "$owned_app_start_identity" != "" &&
       "$owned_app_comm" == "$harness_executable" &&
       "$owned_app_arguments" == "$harness_executable" ]] || {
        mark_terminal_unsafe "app PID $owned_app_pid did not match the exact executable path and direct-parent identity"
        return 1
    }
    bound_app_pid="$owned_app_pid"
    bound_app_start_identity="$owned_app_start_identity"
}

validate_owned_app_identity() {
    local actual_ppid actual_start actual_comm actual_arguments
    validate_launcher_identity || return 1
    pid_is_live "$owned_app_pid" || return 1
    actual_ppid="$(process_field "$owned_app_pid" ppid | tr -d '[:space:]')"
    actual_start="$(process_field "$owned_app_pid" lstart)"
    actual_comm="$(process_field "$owned_app_pid" comm | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    actual_arguments="$(process_field "$owned_app_pid" args)"
    [[ "$actual_ppid" == "$owned_app_ppid" &&
       "$actual_ppid" == "$launcher_pid" &&
       "$actual_start" == "$owned_app_start_identity" &&
       "$actual_comm" == "$owned_app_comm" &&
       "$actual_comm" == "$harness_executable" &&
       "$actual_arguments" == "$owned_app_arguments" &&
       "$actual_arguments" == "$harness_executable" ]]
}

append_owned_identities_to_manifest() {
    local content appended_identity
    validate_directory_identity \
        "$scenario_dir_physical" "$scenario_dir_physical" "$scenario_dir_identity" || return 1
    content="$({
        printf 'runner_pid\t%s\n' "$$"
        printf 'runner_start_identity\t%s\n' "$runner_start_identity"
        printf 'launcher_pid\t%s\n' "$launcher_pid"
        printf 'launcher_ppid\t%s\n' "$launcher_ppid"
        printf 'launcher_start_identity\t%s\n' "$launcher_start_identity"
        printf 'launcher_executable\t%s\n' "$launcher_comm"
        printf 'launcher_arguments_base64\t%s\n' "$(base64_value "$launcher_arguments")"
        printf 'app_pid\t%s\n' "$owned_app_pid"
        printf 'app_ppid\t%s\n' "$owned_app_ppid"
        printf 'app_start_identity\t%s\n' "$owned_app_start_identity"
        printf 'app_executable\t%s\n' "$owned_app_comm"
        printf 'app_arguments_base64\t%s\n' "$(base64_value "$owned_app_arguments")"
    })"$'\n'
    appended_identity="$(
        safe_write_content \
            append "$scenario_dir_physical" "$scenario_dir_identity" \
            cell-manifest.tsv "$cell_manifest_identity" "$content"
    )" || return 1
    [[ "$appended_identity" == "$cell_manifest_identity" ]]
}

append_staging_identity_to_manifest() {
    local content appended_identity
    content="$({
        printf 'staging_parent\t%s\n' "$staging_parent_physical"
        printf 'staging_parent_identity\t%s\n' "$staging_parent_identity"
        printf 'staging_directory\t%s\n' "$staging_dir_physical"
        printf 'staging_identity\t%s\n' "$staging_dir_identity"
        printf 'staging_started_epoch\t%s\n' "$staging_started_epoch"
    })"$'\n'
    appended_identity="$(
        safe_write_content \
            append "$scenario_dir_physical" "$scenario_dir_identity" \
            cell-manifest.tsv "$cell_manifest_identity" "$content"
    )" || return 1
    [[ "$appended_identity" == "$cell_manifest_identity" ]]
}

resolve_owned_app_pid() {
    local iteration=0 candidates candidate child_output
    while (( iteration < 50 )); do
        if ! validate_launcher_identity; then
            mark_terminal_unsafe "launcher identity changed before app PID resolution (PID $launcher_pid)"
            return 1
        fi
        child_output="$(/usr/bin/pgrep -P "$launcher_pid" 2>/dev/null || true)"
        if [[ -n "$child_output" ]]; then
            candidates=("${(@f)child_output}")
        else
            candidates=()
        fi
        if (( ${#candidates[@]} == 1 )); then
            candidate="$candidates[1]"
            [[ "$candidate" == <-> ]] || {
                mark_terminal_unsafe "launcher child PID was not numeric"
                return 1
            }
            capture_owned_app_identity "$candidate" || return 1
            validate_owned_app_identity || {
                mark_terminal_unsafe "app identity changed immediately after binding PID $owned_app_pid"
                return 1
            }
            append_owned_identities_to_manifest || {
                mark_terminal_unsafe "cell manifest changed before owned identity append"
                return 1
            }
            return 0
        elif (( ${#candidates[@]} > 1 )); then
            mark_terminal_unsafe "launcher PID $launcher_pid has ambiguous children: ${candidates[*]}"
            return 1
        fi
        sleep 0.1
        iteration=$((iteration + 1))
    done
    echo "ERROR: timed out resolving the one direct app child of launcher $launcher_pid." >&2
    return 1
}

same_start_identity_is_live() {
    local pid="$1" start_identity="$2" process_state
    pid_is_live "$pid" || return 1
    [[ "$(process_field "$pid" lstart)" == "$start_identity" ]] || return 1
    process_state="$(process_field "$pid" stat | tr -d '[:space:]')"
    [[ "$process_state" != Z* ]]
}

wait_for_identity_exit() {
    local pid="$1" start_identity="$2" iteration=0
    while same_start_identity_is_live "$pid" "$start_identity"; do
        (( iteration < 30 )) || return 1
        sleep 0.1
        iteration=$((iteration + 1))
    done
}

bounded_reap_launcher() {
    local iteration=0 actual_start process_state
    [[ -n "$launcher_pid" && -n "$launcher_start_identity" ]] || return 0
    while (( iteration < 30 )); do
        if ! pid_is_live "$launcher_pid"; then
            wait "$launcher_pid" 2>/dev/null || true
            return 0
        fi
        actual_start="$(process_field "$launcher_pid" lstart 2>/dev/null || true)"
        if [[ -z "$actual_start" ]]; then
            if ! pid_is_live "$launcher_pid"; then
                wait "$launcher_pid" 2>/dev/null || true
                return 0
            fi
        fi
        [[ "$actual_start" == "$launcher_start_identity" ]] || {
            mark_terminal_unsafe "launcher PID $launcher_pid changed identity before bounded reap"
            return 1
        }
        process_state="$(
            process_field "$launcher_pid" stat 2>/dev/null | tr -d '[:space:]' || true
        )"
        if [[ -z "$process_state" ]]; then
            if ! pid_is_live "$launcher_pid"; then
                wait "$launcher_pid" 2>/dev/null || true
                return 0
            fi
        fi
        if [[ "$process_state" == Z* ]]; then
            wait "$launcher_pid" 2>/dev/null || true
            return 0
        fi
        sleep 0.1
        iteration=$((iteration + 1))
    done
    echo "ERROR: bounded launcher reap timed out for exact PID $launcher_pid." >&2
    return 1
}

terminate_owned_app() {
    [[ -n "$owned_app_pid" ]] || return 0
    if ! same_start_identity_is_live "$owned_app_pid" "$owned_app_start_identity"; then
        bounded_reap_launcher || return 1
        owned_app_pid=""
        launcher_pid=""
        return 0
    fi
    if ! validate_owned_app_identity; then
        mark_terminal_unsafe "owned app revalidation failed immediately before TERM (PID $owned_app_pid)"
        return 1
    fi

    kill -TERM "$owned_app_pid"
    if ! wait_for_identity_exit "$owned_app_pid" "$owned_app_start_identity"; then
        if ! validate_owned_app_identity; then
            mark_terminal_unsafe "owned app revalidation failed immediately before KILL (PID $owned_app_pid)"
            return 1
        fi
        kill -KILL "$owned_app_pid"
        wait_for_identity_exit "$owned_app_pid" "$owned_app_start_identity" || {
            mark_terminal_unsafe "owned app PID $owned_app_pid did not exit after exact KILL"
            return 1
        }
    fi

    bounded_reap_launcher || return 1
    owned_app_pid=""
    launcher_pid=""
}

terminate_validated_launcher_only() {
    [[ -n "$launcher_pid" ]] || return 0
    if ! same_start_identity_is_live "$launcher_pid" "$launcher_start_identity"; then
        launcher_pid=""
        return 0
    fi
    if ! validate_launcher_identity; then
        mark_terminal_unsafe "launcher revalidation failed immediately before TERM (PID $launcher_pid)"
        return 1
    fi
    kill -TERM "$launcher_pid"
    wait_for_identity_exit "$launcher_pid" "$launcher_start_identity" || {
        mark_terminal_unsafe "validated launcher PID $launcher_pid did not exit after TERM"
        return 1
    }
    bounded_reap_launcher || return 1
    launcher_pid=""
}

# ---------------------------------------------------------------------------
# Cleanup and launch
# ---------------------------------------------------------------------------
restore_harness_defaults() {
    defaults write OpenIslandApp appearance.island.v8.theme -string halo || return 1
    defaults write OpenIslandApp overlay.display.preference -string F3BDCAC0-1700-415E-817D-AC4E69D405BC || return 1
    [[ "$(defaults read OpenIslandApp appearance.island.v8.theme)" == "halo" ]] || return 1
    [[ "$(defaults read OpenIslandApp overlay.display.preference)" == "F3BDCAC0-1700-415E-817D-AC4E69D405BC" ]] || return 1
}

cleanup_done=false
cleanup() {
    local cleanup_status=0
    [[ "$cleanup_done" == true ]] && return 0
    cleanup_done=true

    if [[ "$terminal_unsafe" == true ]]; then
        if [[ -n "$launcher_pid" || -n "$owned_app_pid" ]]; then
            echo "MANUAL CLEANUP REQUIRED: terminal state is unsafe; no PID signal attempted. Exact recorded launcher PID '${launcher_pid:-none}', app PID '${owned_app_pid:-none}'." >&2
        fi
        cleanup_status=1
    elif [[ -n "$owned_app_pid" ]]; then
        if ! terminate_owned_app; then
            mark_terminal_unsafe "owned app/launcher termination failed during cleanup"
            cleanup_status=1
        fi
    elif [[ -n "$launcher_pid" ]]; then
        if ! terminate_validated_launcher_only; then
            mark_terminal_unsafe "owned launcher termination failed during cleanup"
            cleanup_status=1
        fi
    fi
    if [[ "$terminal_unsafe" == false && -n "$staging_dir_physical" ]]; then
        if ! remove_private_staging_directory; then
            mark_terminal_unsafe "exact private staging cleanup failed during cleanup"
            cleanup_status=1
        fi
    elif [[ -n "$staging_dir_physical" ]]; then
        echo "MANUAL CLEANUP REQUIRED: private staging preserved at exact path '$staging_dir_physical' because terminal state is unsafe." >&2
    fi
    if run_root_available_for_evidence; then
        if ! record_process_inventory "$run_root_physical/processes-after.tsv"; then
            mark_terminal_unsafe "passive post-run process inventory could not be written"
            cleanup_status=1
        fi
    else
        mark_terminal_unsafe "run-root evidence directory is unavailable; passive post-run process inventory could not be written"
        cleanup_status=1
    fi
    # This comparison is mandatory even if the run root was removed or its
    # identity changed. record_production_app_after then records no evidence
    # outside an identity-bound, run-owned location.
    if ! record_production_app_after; then
        mark_terminal_unsafe "production app baseline/after proof failed; production processes were observed passively and never targeted"
        cleanup_status=1
    fi
    if ! restore_harness_defaults; then
        mark_terminal_unsafe "harness defaults restore/readback failed during cleanup"
        cleanup_status=1
    fi
    return "$cleanup_status"
}

finish() {
    local exit_status="$1"
    trap - EXIT
    trap '' INT TERM HUP
    cleanup || exit_status=1
    exit "$exit_status"
}

build_harness_executable() {
    echo "Building OpenIslandApp in this worktree"
    swift build --product OpenIslandApp
    [[ -x "$harness_executable" ]] || {
        echo "ERROR: expected worktree executable is missing: $harness_executable" >&2
        return 1
    }
    [[ -x "$script_executable" ]] || {
        echo "ERROR: pinned pseudo-terminal launcher is unavailable: $script_executable" >&2
        return 1
    }
    [[ -x "$orca_executable" ]] || {
        echo "ERROR: pinned Orca executable is unavailable: $orca_executable" >&2
        return 1
    }
}

apply_theme() {
    local theme="$1"
    defaults write OpenIslandApp appearance.island.v8.theme -string "$theme"
}

launch_scenario() {
    local scenario="$1"
    local -a launcher_command
    launcher_pid=""
    owned_app_pid=""
    bound_app_pid=""
    launcher_start_identity=""
    owned_app_start_identity=""
    bound_app_start_identity=""

    validate_directory_identity \
        "$approved_evidence_parent_physical" \
        "$approved_evidence_parent_physical" \
        "$approved_evidence_parent_identity" || {
        mark_terminal_unsafe "approved evidence parent changed before app launch"
        return 1
    }
    validate_directory_identity \
        "$run_root_physical" "$run_root_physical" "$run_root_identity" || {
        mark_terminal_unsafe "run root changed before app launch"
        return 1
    }
    validate_directory_identity \
        "$scenario_dir_physical" "$scenario_dir_physical" "$scenario_dir_identity" || {
        mark_terminal_unsafe "cell directory changed before app launch"
        return 1
    }
    validate_directory_identity \
        "$staging_dir_physical" "$staging_dir_physical" "$staging_dir_identity" || {
        mark_terminal_unsafe "private staging directory changed before app launch"
        return 1
    }

    # The backgrounded function immediately execs Python, which opens the log
    # relative to the bound cell directory and execs this exact command. The
    # PID/start/PPID therefore survive Python -> script without an extra zsh.
    launcher_command=(
        /usr/bin/script -q /dev/null /usr/bin/env
        "OPEN_ISLAND_HARNESS_SCENARIO=$scenario"
        OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1
        OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0
        OPEN_ISLAND_HARNESS_START_BRIDGE=0
        OPEN_ISLAND_HARNESS_SUPPRESS_INSTALL_HINT=1
        "OPEN_ISLAND_HARNESS_ARTIFACT_DIR=$staging_dir_physical"
        OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS=1
        "$harness_executable"
    )
    launcher_expected_arguments="${(j: :)launcher_command}"
    safe_exec_new_output_replace_process \
        "$scenario_dir_physical" "$scenario_dir_identity" smoke.log \
        "${launcher_command[@]}" &
    launcher_pid="$!"

    capture_launcher_identity || return 1
    resolve_owned_app_pid
}

# ---------------------------------------------------------------------------
# Fresh artifact validation
# ---------------------------------------------------------------------------
verify_fresh_artifact() {
    local artifact="$1" artifact_parent birth_epoch modification_epoch
    [[ -f "$artifact" && ! -L "$artifact" ]] || return 1
    artifact_parent="$(physical_directory "${artifact:h}")" || return 1
    [[ "$artifact_parent" == "$scenario_dir_physical" ]] || return 1
    validate_directory_identity \
        "$scenario_dir_physical" "$scenario_dir_physical" "$scenario_dir_identity" || return 1
    birth_epoch="$(/usr/bin/stat -f '%B' "$artifact")" || return 1
    modification_epoch="$(/usr/bin/stat -f '%m' "$artifact")" || return 1
    (( birth_epoch >= cell_started_epoch && modification_epoch >= cell_started_epoch ))
}

validate_cell_manifest() {
    local manifest="$scenario_dir_physical/cell-manifest.tsv"
    validate_directory_identity \
        "$scenario_dir_physical" "$scenario_dir_physical" "$scenario_dir_identity" || return 1
    [[ -f "$manifest" && ! -L "$manifest" ]] || return 1
    [[ "$(filesystem_identity "$manifest")" == "$cell_manifest_identity" ]] || return 1
    /usr/bin/grep -Fqx $'run_nonce\t'"$run_nonce" "$manifest" &&
        /usr/bin/grep -Fqx $'cell_nonce\t'"$cell_nonce" "$manifest" &&
        /usr/bin/grep -Fqx $'theme\t'"$1" "$manifest" &&
        /usr/bin/grep -Fqx $'scenario\t'"$2" "$manifest" &&
        /usr/bin/grep -Fqx $'app_pid\t'"$bound_app_pid" "$manifest" &&
        /usr/bin/grep -Fqx $'app_start_identity\t'"$bound_app_start_identity" "$manifest" &&
        /usr/bin/grep -Fqx $'staging_parent\t'"$staging_parent_physical" "$manifest" &&
        /usr/bin/grep -Fqx $'staging_parent_identity\t'"$staging_parent_identity" "$manifest" &&
        /usr/bin/grep -Fqx $'staging_directory\t'"$staging_dir_physical" "$manifest" &&
        /usr/bin/grep -Fqx $'staging_identity\t'"$staging_dir_identity" "$manifest"
}

verify_fresh_staged_artifact() {
    local artifact="$1" artifact_parent birth_epoch modification_epoch
    [[ -f "$artifact" && ! -L "$artifact" ]] || return 1
    validate_directory_identity \
        "$staging_dir_physical" "$staging_dir_physical" "$staging_dir_identity" || return 1
    artifact_parent="$(physical_directory "${artifact:h}")" || return 1
    [[ "$artifact_parent" == "$staging_dir_physical" ]] || return 1
    birth_epoch="$(/usr/bin/stat -f '%B' "$artifact")" || return 1
    modification_epoch="$(/usr/bin/stat -f '%m' "$artifact")" || return 1
    (( birth_epoch >= staging_started_epoch && modification_epoch >= staging_started_epoch ))
}

wait_for_staging_capture() {
    local iteration=0 report_path artifact report_complete
    local -a png_files ax_files
    report_path="$staging_dir_physical/report.json"
    while (( iteration < 100 )); do
        validate_directory_identity \
            "$staging_dir_physical" "$staging_dir_physical" "$staging_dir_identity" || {
            mark_terminal_unsafe "private staging directory changed during app capture"
            return 1
        }
        png_files=("$staging_dir_physical"/*.png(N))
        ax_files=("$staging_dir_physical"/*.ax.json(N))
        if [[ -f "$report_path" && ${#png_files[@]} -gt 0 && ${#ax_files[@]} -gt 0 ]]; then
            verify_fresh_staged_artifact "$report_path" || {
                mark_terminal_unsafe "staging report failed identity/freshness validation"
                return 1
            }
            for artifact in "${png_files[@]}" "${ax_files[@]}"; do
                verify_fresh_staged_artifact "$artifact" || {
                    mark_terminal_unsafe "staging PNG/AX artifact failed identity/freshness validation"
                    return 1
                }
            done
            report_complete=false
            /usr/bin/python3 - "$report_path" <<'PY' && report_complete=true
import json
import pathlib
import sys

report = pathlib.Path(sys.argv[1])
if report.stat().st_size <= 0:
    raise SystemExit(1)
json.loads(report.read_text())
PY
            if [[ "$report_complete" == true ]]; then
                return 0
            fi
        fi
        if ! validate_owned_app_identity; then
            mark_terminal_unsafe "owned app identity changed while waiting for staging capture (PID $owned_app_pid)"
            return 1
        fi
        sleep 0.1
        iteration=$((iteration + 1))
    done
    echo "ERROR: timed out waiting for private staging capture." >&2
    return 1
}

finalize_staged_artifacts() {
    local theme="$1" scenario="$2" orca_observation_succeeded="$3"
    local staged_report="$staging_dir_physical/report.json"
    local final_report="$scenario_dir_physical/report.json"
    local orca_report="$scenario_dir_physical/orca-app-state.json"
    local artifact filename copied_identity validation_content appended_identity
    local -a staged_files png_files ax_files final_artifacts

    validate_cell_manifest "$theme" "$scenario" || {
        mark_terminal_unsafe "cell manifest identity no longer matches run $run_nonce"
        return 1
    }
    validate_directory_identity \
        "$staging_dir_physical" "$staging_dir_physical" "$staging_dir_identity" || {
        mark_terminal_unsafe "private staging identity changed before finalization"
        return 1
    }
    staged_files=("$staging_dir_physical"/*(N))
    png_files=("$staging_dir_physical"/*.png(N))
    ax_files=("$staging_dir_physical"/*.ax.json(N))
    [[ -f "$staged_report" && ${#png_files[@]} -gt 0 && ${#ax_files[@]} -gt 0 ]] || return 1
    for artifact in "${staged_files[@]}"; do
        verify_fresh_staged_artifact "$artifact" || {
            mark_terminal_unsafe "staged artifact is stale, linked, or outside staging: $artifact"
            return 1
        }
    done

    /usr/bin/python3 - "$staged_report" "$scenario" "$staging_dir_physical" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
if report.get("scenario") != sys.argv[2]:
    raise SystemExit(
        f"Smoke failed: report scenario {report.get('scenario')!r} "
        f"does not match manifest scenario {sys.argv[2]!r}"
    )
staging = pathlib.Path(sys.argv[3]).resolve(strict=True)
for window in report.get("windows") or []:
    for key in ("imagePath", "accessibilityPath"):
        raw_path = window.get(key)
        if raw_path is None:
            continue
        if not isinstance(raw_path, str) or not raw_path:
            raise SystemExit(f"Smoke failed: report {key} is not a basename")
        relative = pathlib.PurePath(raw_path)
        if (
            relative.is_absolute()
            or len(relative.parts) != 1
            or relative.name in (".", "..")
            or "/" in raw_path
            or "\\" in raw_path
        ):
            raise SystemExit(
                f"Smoke failed: report {key} is not a single basename: {raw_path!r}"
            )
        artifact = (staging / raw_path).resolve(strict=True)
        if artifact.parent != staging:
            raise SystemExit(
                f"Smoke failed: report {key} escaped private staging: {artifact}"
            )
PY
    [[ "$?" == 0 ]] || {
        mark_terminal_unsafe "staged report scenario or basename validation failed"
        return 1
    }

    for artifact in "${staged_files[@]}"; do
        filename="${artifact:t}"
        copied_identity="$(safe_copy_staged_file "$filename")" || {
            mark_terminal_unsafe "staging-to-cell exclusive copy failed for $filename"
            return 1
        }
        [[ -n "$copied_identity" ]] || return 1
    done

    final_artifacts=("$scenario_dir_physical"/*.png(N) "$scenario_dir_physical"/*.ax.json(N))
    verify_fresh_artifact "$final_report" || {
        mark_terminal_unsafe "final report is not fresh in the identity-bound cell"
        return 1
    }
    verify_fresh_artifact "$orca_report" || {
        mark_terminal_unsafe "final Orca evidence is not fresh in the identity-bound cell"
        return 1
    }
    for artifact in "${final_artifacts[@]}"; do
        verify_fresh_artifact "$artifact" || {
            mark_terminal_unsafe "final copied artifact failed identity/freshness validation: $artifact"
            return 1
        }
    done
    if [[ "$orca_observation_succeeded" == true ]]; then
        /usr/bin/python3 - "$orca_report" <<'PY'
import json
import pathlib
import sys

json.loads(pathlib.Path(sys.argv[1]).read_text())
PY
        [[ "$?" == 0 ]] || {
            mark_terminal_unsafe "successful Orca evidence is not valid JSON"
            return 1
        }
    fi
    /usr/bin/python3 "$repo_root/scripts/validate-harness-artifacts.py" \
        --theme "$theme" "$final_report" || {
        # The owned harness process has already exited cleanly before this
        # semantic check. A validator nonconformance fails this cell, but is
        # not an ownership, no-follow transfer, cleanup, or evidence-identity
        # incident and must not suppress safe cleanup or misstate the hazard.
        echo "ERROR: copied harness evidence semantic validation failed for $theme/$scenario." >&2
        return 1
    }

    validation_content="$({
        printf 'validated_run_nonce\t%s\n' "$run_nonce"
        printf 'validated_cell_nonce\t%s\n' "$cell_nonce"
        printf 'validated_theme\t%s\n' "$theme"
        printf 'validated_scenario\t%s\n' "$scenario"
        printf 'orca_observation_succeeded\t%s\n' "$orca_observation_succeeded"
        printf 'validated_staging_identity\t%s\n' "$staging_dir_identity"
        printf 'validated_epoch\t%s\n' "$(date +%s)"
        for artifact in "$final_report" "$orca_report" "${final_artifacts[@]}"; do
            printf 'validated_artifact\t%s\t%s\n' \
                "${artifact:t}" "$(/usr/bin/stat -f '%B' "$artifact")"
        done
    })"$'\n'
    appended_identity="$(
        safe_write_content \
            append "$scenario_dir_physical" "$scenario_dir_identity" \
            cell-manifest.tsv "$cell_manifest_identity" "$validation_content"
    )" || {
        mark_terminal_unsafe "cell manifest changed before final validation append"
        return 1
    }
    [[ "$appended_identity" == "$cell_manifest_identity" ]] || {
        mark_terminal_unsafe "cell manifest inode changed during final validation append"
        return 1
    }
}

# ---------------------------------------------------------------------------
# Strictly serial matrix
# ---------------------------------------------------------------------------
typeset -A results
failures=()

run_scenario() {
    local theme="$1" scenario="$2"
    local label="$theme-$scenario"
    local scenario_status=0

    if ! validate_runner_manifest; then
        mark_terminal_unsafe "runner manifest no longer matches fixed run $run_nonce"
        return 1
    fi
    if ! create_fresh_cell_directory "$theme" "$scenario"; then
        mark_terminal_unsafe "fresh evidence cell creation failed for fixed cell $label"
        return 1
    fi
    if ! create_private_staging_directory; then
        mark_terminal_unsafe "fresh private staging creation failed for fixed cell $label"
        return 1
    fi
    if ! append_staging_identity_to_manifest; then
        mark_terminal_unsafe "cell manifest changed before staging identity binding"
        return 1
    fi
    echo "Running serial cell '$label' -> $scenario_dir_physical"

    local staging_ready=false
    local orca_observation_succeeded=false
    local orca_exit_status=0
    local orca_evidence="$scenario_dir_physical/orca-app-state.json"
    if ! launch_scenario "$scenario"; then
        scenario_status=1
    elif wait_for_staging_capture; then
        staging_ready=true
        if ! validate_owned_app_identity; then
            mark_terminal_unsafe "owned app revalidation failed immediately before Orca (PID $owned_app_pid)"
            scenario_status=1
        else
            # Exact identity validation is intentionally immediately adjacent
            # to the protected synchronous Orca observation.
            if safe_exec_new_output \
                "$scenario_dir_physical" "$scenario_dir_identity" orca-app-state.json \
                "$orca_executable" computer get-app-state \
                --app "pid:$owned_app_pid" --json; then
                orca_exit_status=0
            else
                orca_exit_status=$?
            fi
            if ! validate_owned_app_identity; then
                mark_terminal_unsafe "owned app identity changed during Orca execution"
                scenario_status=1
            elif ! verify_fresh_artifact "$orca_evidence"; then
                mark_terminal_unsafe "Orca evidence output is missing or not fresh in the identity-bound cell"
                scenario_status=1
            elif (( orca_exit_status != 0 )); then
                echo "ERROR: Orca observation failed for exact owned PID $owned_app_pid." >&2
                scenario_status=1
            else
                orca_observation_succeeded=true
            fi
        fi
    else
        scenario_status=1
    fi

    if [[ "$terminal_unsafe" == true ]]; then
        if [[ -n "$launcher_pid" || -n "$owned_app_pid" ]]; then
            echo "MANUAL CLEANUP REQUIRED: no signal after failed revalidation. Exact recorded launcher PID '${launcher_pid:-none}', app PID '${owned_app_pid:-none}'." >&2
        fi
    elif [[ -n "$owned_app_pid" ]]; then
        if ! terminate_owned_app; then
            mark_terminal_unsafe "owned app/launcher termination failed after cell execution"
            scenario_status=1
        fi
    elif [[ -n "$launcher_pid" ]]; then
        if ! terminate_validated_launcher_only; then
            mark_terminal_unsafe "owned launcher termination failed after cell execution"
            scenario_status=1
        fi
    fi

    if [[ "$terminal_unsafe" == false && "$staging_ready" == true && -z "$owned_app_pid" ]]; then
        finalize_staged_artifacts \
            "$theme" "$scenario" "$orca_observation_succeeded" || scenario_status=1
    fi
    if [[ "$terminal_unsafe" == false && -n "$staging_dir_physical" ]]; then
        remove_private_staging_directory || {
            mark_terminal_unsafe "exact private staging cleanup failed"
            scenario_status=1
        }
    fi

    return "$scenario_status"
}

run_theme() {
    local theme="$1" scenario label
    apply_theme "$theme" || {
        echo "ERROR: failed to apply fixed theme '$theme' in the isolated defaults domain." >&2
        return 1
    }
    for scenario in "${scenarios[@]}"; do
        label="$theme-$scenario"
        if run_scenario "$theme" "$scenario"; then
            results[$label]="PASS"
        else
            results[$label]="FAIL"
            failures+=("$label")
            echo "FAILED: $label" >&2
            if [[ "$terminal_unsafe" == true ]]; then
                echo "ERROR: refusing all further cells after terminal ownership/evidence failure." >&2
            else
                echo "ERROR: refusing all further cells after actual cell failure ($label)." >&2
            fi
            return 1
        fi
    done
}

print_actual_summary() {
    local theme scenario label cell total=0 passed=0
    echo
    echo "==================== Actual matrix summary ===================="
    printf '%-23s%-14s%-14s%-14s\n' "SCENARIO" "poured" "flightDeck" "halo"
    for scenario in "${scenarios[@]}"; do
        printf '%-23s' "$scenario"
        for theme in "${themes[@]}"; do
            label="$theme-$scenario"
            cell="${results[$label]:-NOT-RUN}"
            printf '%-14s' "$cell"
            total=$((total + 1))
            [[ "$cell" == "PASS" ]] && passed=$((passed + 1))
        done
        printf '\n'
    done
    echo "==============================================================="
    echo "$passed / $total actual cells passed"
}

# ---------------------------------------------------------------------------
# Real-run main
# ---------------------------------------------------------------------------
if [[ "${SMOKE_ALL_SCENARIOS_TEST_LIBRARY:-}" == "1" ]]; then
    # Direct runner tests source the helper functions with safe fakes. This
    # guard is intentionally after all helpers and before any real-run state.
    return 0
fi

trap 'finish $?' EXIT
trap 'finish 130' INT
trap 'finish 143' TERM
trap 'finish 129' HUP

# Capture the immutable production-process baseline before evidence setup so
# every post-trap failure, including run-root or manifest setup, is checked.
capture_production_app_baseline || {
    mark_terminal_unsafe "passive production app baseline could not be captured"
    exit 1
}
create_fresh_run_root
write_runner_manifest
record_process_inventory "$run_root_physical/processes-before.tsv" || {
    mark_terminal_unsafe "passive pre-run process inventory could not be written"
    exit 1
}
if ! record_production_app_baseline; then
    mark_terminal_unsafe "passive production app baseline could not be written"
    exit 1
fi

build_harness_executable
echo "Fixed matrix: 3 themes x 15 scenarios, strictly serial"
echo "Fresh evidence root: $run_root_physical"

for theme in "${themes[@]}"; do
    if ! run_theme "$theme"; then
        exit 1
    fi
done

print_actual_summary

if (( ${#failures[@]} > 0 )); then
    echo "smoke-all-scenarios: ${#failures[@]} actual cell(s) failed" >&2
    exit 1
fi

echo "All 45 actual matrix cells passed"
echo "Fresh artifacts written to $run_root_physical"
