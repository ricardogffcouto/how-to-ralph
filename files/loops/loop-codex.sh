#!/bin/bash
# Usage: ./loop.sh [plan] [max_iterations]

set -euo pipefail

# ---- Codex configuration ----
CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_MODEL_PLAN="${CODEX_MODEL_PLAN:-gpt-5.3-codex}"
CODEX_MODEL_BUILD="${CODEX_MODEL_BUILD:-gpt-5.3-codex}"
CODEX_DANGEROUS="${CODEX_DANGEROUS:-1}"

FORCE_THINKING_MODEL="gpt-5.3-codex"
FORCE_CODING_MODEL="gpt-5.3-codex"

LOG_DIR="${LOG_DIR:-logs}"
mkdir -p "$LOG_DIR"

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  echo "Error: '$CODEX_BIN' not found in PATH. Install with: npm install -g @openai/codex"
  exit 1
fi

HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log() { local level="$1"; shift; printf "[%s] %-5s %s\n" "$(timestamp)" "$level" "$*"; }

ensure_git_remote_origin() {
  if git remote get-url origin >/dev/null 2>&1; then return 0; fi
  log WARN "git remote 'origin' is missing; skipping push."
  return 1
}

# Parse arguments
if [ "${1:-}" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=$1
else
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=0
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)

if [ "$MODE" = "plan" ]; then CODEX_MODEL="$CODEX_MODEL_PLAN"; else CODEX_MODEL="$CODEX_MODEL_BUILD"; fi

TMP_PROMPT="$(mktemp)"
cleanup() { rm -f "$TMP_PROMPT"; }
trap cleanup EXIT

log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log INFO "Mode:   $MODE"
log INFO "Prompt: $PROMPT_FILE"
log INFO "Branch: $CURRENT_BRANCH"
log INFO "Model:  $CODEX_MODEL"
log INFO "Patch:  thinking_model=$FORCE_THINKING_MODEL, coding_model=$FORCE_CODING_MODEL"
[ "$CODEX_DANGEROUS" -eq 1 ] && log WARN "Codex:  YOLO (no approvals, no sandbox)"
[ "${MAX_ITERATIONS}" -gt 0 ] && log INFO "Max:    $MAX_ITERATIONS iterations"
log INFO "Logs:   $LOG_DIR/"
log INFO "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f "$PROMPT_FILE" ]; then
    log ERROR "$PROMPT_FILE not found"
    exit 1
fi

# ---- Robust pretty-printer: if jq/formatting fails, fall back to raw JSONL passthrough ----
pretty_codex_stream() {
  if [ "$HAS_JQ" -ne 1 ]; then
    cat
    return 0
  fi

  # The subshell ensures: if jq exits non-zero, we transparently fall back to cat.
  (
    set +e
    jq -r '
      def ts: (now | todateiso8601);
      . as $e
      | if ($e.type == "thread.started") then
          "["+ts+"] CODEX thread.started  thread_id=" + ($e.thread_id // "")
        elif ($e.type == "turn.started") then
          "["+ts+"] CODEX turn.started"
        elif ($e.type == "turn.completed") then
          "["+ts+"] CODEX turn.completed"
        elif ($e.type == "item.started" and ($e.item.type // "") == "command_execution") then
          "["+ts+"] CMD  ▶ " + ($e.item.command // "")
        elif ($e.type == "item.completed" and ($e.item.type // "") == "command_execution") then
          "["+ts+"] CMD  ✓ exit=" + (($e.item.exit_code // -1)|tostring) +
          (if (($e.item.aggregated_output // "")|length) > 0 then
            "\n" + ($e.item.aggregated_output|tostring)
          else "" end)
        elif ($e.type == "item.completed" and ($e.item.type // "") == "agent_message") then
          "["+ts+"] AGENT " + ($e.item.text // "")
        elif ($e.type == "item.completed" and ($e.item.type // "") == "reasoning") then
          "["+ts+"] THINK " + ($e.item.text // "")
        else
          empty
        end
    '
    rc=$?
    if [ $rc -ne 0 ]; then
      # jq failed: fall back to raw passthrough (no log spam, stays streaming)
      cat
    fi
    exit 0
  )
}

while true; do
    if [ "${MAX_ITERATIONS}" -gt 0 ] && [ "${ITERATION}" -ge "${MAX_ITERATIONS}" ]; then
        log INFO "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    RUN_ID="$(date "+%Y%m%d-%H%M%S")-iter${ITERATION}"
    RAW_LOG="$LOG_DIR/codex-$RUN_ID.jsonl"
    PRETTY_LOG="$LOG_DIR/codex-$RUN_ID.log"

    log INFO "Run: $RUN_ID"

    sed -E \
      -e "s/^([[:space:]]*thinking_model:[[:space:]]*).*/\1$FORCE_THINKING_MODEL/" \
      -e "s/^([[:space:]]*coding_model:[[:space:]]*).*/\1$FORCE_CODING_MODEL/" \
      "$PROMPT_FILE" > "$TMP_PROMPT"

    CODEX_FLAGS=(exec --model "$CODEX_MODEL" --json)
    if [ "$CODEX_DANGEROUS" -eq 1 ]; then
      CODEX_FLAGS+=(--yolo)
    else
      CODEX_FLAGS+=(--full-auto --ask-for-approval never)
    fi

    log INFO "Codex exec starting (raw: $RAW_LOG, pretty: $PRETTY_LOG)"

    set +e
    stdbuf -oL -eL cat "$TMP_PROMPT" | \
      stdbuf -oL -eL "$CODEX_BIN" "${CODEX_FLAGS[@]}" - \
      | tee "$RAW_LOG" \
      | pretty_codex_stream \
      | tee "$PRETTY_LOG"
    CODEX_EXIT="${PIPESTATUS[1]}"
    set -e

    if [ "$CODEX_EXIT" -ne 0 ]; then
      log ERROR "Codex exited non-zero: $CODEX_EXIT (see $RAW_LOG / $PRETTY_LOG)"
      exit "$CODEX_EXIT"
    fi

    if ensure_git_remote_origin; then
      if git push origin "$CURRENT_BRANCH"; then
        log INFO "Pushed to origin/$CURRENT_BRANCH"
      else
        log WARN "Push failed; trying to set upstream..."
        git push -u origin "$CURRENT_BRANCH"
        log INFO "Pushed with upstream set: origin/$CURRENT_BRANCH"
      fi
    fi

    ITERATION=$((ITERATION + 1))
    log INFO "======================== LOOP $ITERATION ========================"
done

