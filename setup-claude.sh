#!/usr/bin/env bash
# Claude Code setup for macOS and Linux (Xsolla game jam).
#
# Paste this into Terminal, press Enter, then paste your key when asked:
#   curl -fsSL "<link to this file>" | bash
#
# It will:
#   1. Install Claude Code if it is missing
#   2. Test the key against the right endpoint
#        sk-ant-...    -> official Anthropic API (asks for a workspace ID if the key needs one)
#        anything else -> Xsolla jam LiteLLM gateway
#   3. Save the settings in your shell startup file (~/.zshrc, ~/.bashrc or ~/.bash_profile),
#      between the lines "# >>> xsolla-jam claude >>>" and "# <<< xsolla-jam claude <<<"
#   4. Jam key only: add a note to ~/.claude/CLAUDE.md so Claude Code knows how to make
#      images with jam-image
#   5. Start Claude Code
#
# The same file also undoes it:
#   curl -fsSL "<link>" | bash -s reset    Start over: remove the jam settings, back up
#                                          ~/.claude and ~/.claude.json, then set up again
#   curl -fsSL "<link>" | bash -s remove   After the jam: remove the jam settings and the
#                                          image note, and keep everything else
# Or download it and run: bash setup-claude.sh [reset|remove]
#
# Everything runs from main() on the last line, so a half-downloaded copy does nothing.

GATEWAY_URL="${JAM_GATEWAY_URL:-https://litellm-school-proxy-z73l24biba-wl.a.run.app}"
ANTHROPIC_URL="${JAM_ANTHROPIC_URL:-https://api.anthropic.com}"
EFFORT_LEVEL='medium'

# Every variable this script owns. All are removed before new ones are written,
# so switching between gateway and official never leaves stale settings behind.
MANAGED_VARS='ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS ANTHROPIC_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_EFFORT_LEVEL'
STRAY_PATTERN='^[[:space:]]*export[[:space:]]+(ANTHROPIC_[A-Z_]+|CLAUDE_CODE_EFFORT_LEVEL)='
BLOCK_START='# >>> xsolla-jam claude >>>'
BLOCK_END='# <<< xsolla-jam claude <<<'
RC_FILES="$HOME/.zshrc $HOME/.bashrc $HOME/.bash_profile $HOME/.profile"

# Same note and markers as setup-claude.ps1 on Windows.
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
NOTE_START='<!-- xsolla-jam-images:start -->'
NOTE_END='<!-- xsolla-jam-images:end -->'
JAM_NOTE='<!-- xsolla-jam-images:start -->
## Making images (Xsolla game jam)

The jam key can also make images with the model jam-image. When I ask for an image (a sprite, icon, background or cover), make it like this:

- POST to "$ANTHROPIC_BASE_URL/v1/images/generations" with the header "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" and the JSON body {"model": "jam-image", "prompt": "<what to draw>"}. Both values are already set as environment variables. Never print the key or write it into a file.
- The image comes back as base64 in data[0].b64_json. Decode it, save it as a PNG in my project (in its assets folder if there is one), and tell me where you saved it.
- If the response has no data, show me the error message instead.
- Each image costs about US$0.04 of my jam budget, so make one image at a time unless I ask for more.
- Only call this API from the terminal. Never put the key or this API call in the game'"'"'s own code.
<!-- xsolla-jam-images:end -->'

if [ -t 1 ]; then
  C_STEP=$'\033[36m'; C_OK=$'\033[32m'; C_NOTE=$'\033[33m'; C_ERR=$'\033[31m'; C_OFF=$'\033[0m'
else
  C_STEP=''; C_OK=''; C_NOTE=''; C_ERR=''; C_OFF=''
fi
step() { printf '\n%s==> %s%s\n' "$C_STEP" "$1" "$C_OFF"; }
ok()   { printf '    %s%s%s\n' "$C_OK" "$1" "$C_OFF"; }
note() { printf '    %s%s%s\n' "$C_NOTE" "$1" "$C_OFF"; }
die()  { printf '\n%sERROR: %s%s\n' "$C_ERR" "$1" "$C_OFF"; exit 1; }

# Answers come from the keyboard (fd 3), not from stdin: with "curl | bash", stdin is this script.
ask()        { printf '    %s' "$1"; IFS= read -r -u 3 REPLY || REPLY=''; }
ask_secret() { printf '    %s' "$1"; IFS= read -r -s -u 3 REPLY || REPLY=''; printf '\n'; }
is_yes()     { case "$1" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }
is_no()      { case "$1" in n|N|no|No|NO) return 0 ;; *) return 1 ;; esac; }

# Removes the lines from START to END (both included) from FILE, if both are there.
# Returns 0 if something was removed.
strip_block() {
  [ -f "$1" ] && grep -qxF "$2" "$1" && grep -qxF "$3" "$1" || return 1
  awk -v s="$2" -v e="$3" '
    $0 == s { skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { line[++n] = $0 }
    END { while (n > 0 && line[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print line[i] }
  ' "$1" > "$TMP/strip" && cat "$TMP/strip" > "$1"
}

# Old "export ANTHROPIC_..." lines outside our block, for example from the guide's manual steps.
# Prints "file:line: NAME" for each, never the value.
find_stray() {
  for f in $RC_FILES; do
    [ -f "$f" ] || continue
    awk -v s="$BLOCK_START" -v e="$BLOCK_END" -v f="$f" -v p="$STRAY_PATTERN" '
      $0 == s { inside = 1 } $0 == e { inside = 0; next }
      !inside && $0 ~ p { name = $0; sub(/^[[:space:]]*export[[:space:]]+/, "", name); sub(/=.*/, "", name); print f ":" NR ": " name }
    ' "$f"
  done
}

# Comments out the lines find_stray reports.
disable_stray() {
  for f in $RC_FILES; do
    [ -f "$f" ] || continue
    awk -v s="$BLOCK_START" -v e="$BLOCK_END" -v p="$STRAY_PATTERN" '
      $0 == s { inside = 1 } $0 == e { inside = 0; print; next }
      !inside && $0 ~ p { print "# (turned off by the jam setup) " $0; next }
      { print }
    ' "$f" > "$TMP/stray" && cat "$TMP/stray" > "$f"
  done
}

handle_stray() {
  stray=$(find_stray)
  [ -n "$stray" ] || return 0
  note 'These older lines set Claude Code settings too, and would override the jam setup:'
  printf '%s\n' "$stray" | sed 's/^/      /'
  ask 'Turn them off (they are kept as comments)? [Y/n] '
  if is_no "$REPLY"; then
    note 'Left as they are. If Claude Code uses the wrong key, run this again and answer Y.'
  else
    disable_stray
    ok 'Turned off'
  fi
}

remove_note() {
  strip_block "$CLAUDE_MD" "$NOTE_START" "$NOTE_END" || return 1
  if ! grep -q '[^[:space:]]' "$CLAUDE_MD" 2>/dev/null; then rm -f "$CLAUDE_MD"; fi
  return 0
}

add_note() {
  remove_note
  mkdir -p "$(dirname "$CLAUDE_MD")" || return 1
  if [ -s "$CLAUDE_MD" ]; then printf '\n' >> "$CLAUDE_MD"; fi
  printf '%s\n' "$JAM_NOTE" >> "$CLAUDE_MD"
}

# The startup file that new terminal windows read for the user's shell.
pick_rc() {
  case "$(basename "${SHELL:-}")" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) if [ "$(uname -s)" = Darwin ]; then echo "$HOME/.bash_profile"; else echo "$HOME/.bashrc"; fi ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

unset_managed() { for v in $MANAGED_VARS; do unset "$v"; done; }

claude_running() { pgrep -x claude >/dev/null 2>&1; }

# Sends a tiny /v1/messages request with the headers in $TMP/headers.
# Sets HTTP_STATUS (000 for network errors); the response is in $TMP/body.
key_test() {
  : > "$TMP/body"
  HTTP_STATUS=$(curl -sS -o "$TMP/body" -w '%{http_code}' --max-time 60 -X POST "$1/v1/messages" \
    -H @"$TMP/headers" -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' \
    -d "{\"model\":\"$2\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
    2> "$TMP/curl-error" < /dev/null)
  [ -n "$HTTP_STATUS" ] || HTTP_STATUS=000
}
# 401/403 mean the key itself was rejected; anything else (budget, overload, network) is not the key's fault.
key_rejected() { [ "$HTTP_STATUS" = 401 ] || [ "$HTTP_STATUS" = 403 ]; }
error_text() {
  if [ -s "$TMP/body" ]; then head -c 300 "$TMP/body"; else head -c 300 "$TMP/curl-error"; fi
}
# Header file, so the key never shows up in the process list.
write_headers() { # $1 = header name, $2 = value
  printf '%s: %s\n' "$1" "$2" > "$TMP/headers"
  if [ -n "$WORKSPACE" ]; then printf 'anthropic-workspace-id: %s\n' "$WORKSPACE" >> "$TMP/headers"; fi
}

# ---------------------------------------------------------------------------
do_setup() {
  step 'Checking Claude Code'
  export PATH="$HOME/.local/bin:$PATH"   # where the installer puts it
  if ! command -v claude >/dev/null 2>&1; then
    echo '    Installing Claude Code. This can take a few minutes; please wait...'
    curl -fsSL https://claude.ai/install.sh < /dev/null | bash \
      || die 'Claude Code did not install. Check your internet connection and run this again.'
    hash -r
    command -v claude >/dev/null 2>&1 || die 'Claude Code did not install. Check your internet connection and run this again.'
  fi
  CLAUDE_BIN=$(command -v claude)
  ok "Claude Code: $CLAUDE_BIN"
  NEED_PATH=no
  case ":$ORIG_PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) [ "$(dirname "$CLAUDE_BIN")" = "$HOME/.local/bin" ] && NEED_PATH=yes ;;
  esac

  step 'Your key'
  echo '    Paste your key (Cmd+V on a Mac, Ctrl+Shift+V on Linux) and press Enter.'
  echo '    Nothing shows on screen while you paste. That is normal.'
  MODE=''; AUTH_VAR=''; WORKSPACE=''; key=''
  attempt=1
  while [ "$attempt" -le 3 ]; do
    ask_secret 'Key: '
    key=$(printf '%s' "$REPLY" | tr -d "[:space:]\"'")
    if [ -z "$key" ]; then note 'No key entered.'; attempt=$((attempt + 1)); continue; fi

    echo '    Testing the key...'
    fallback=''
    case "$key" in
      sk-ant-*)
        MODE=official
        # Console keys normally use x-api-key; some account-level keys only work as a Bearer token.
        for style in api bearer; do
          if [ "$style" = api ]; then var=ANTHROPIC_API_KEY; write_headers x-api-key "$key"
          else var=ANTHROPIC_AUTH_TOKEN; write_headers Authorization "Bearer $key"; fi
          key_test "$ANTHROPIC_URL" claude-haiku-5-5
          if [ "$HTTP_STATUS" != 200 ] && [ -z "$WORKSPACE" ] && grep -q 'anthropic-workspace-id' "$TMP/body"; then
            note 'This key is not tied to a workspace, so a workspace ID is needed.'
            note 'Find it in console.anthropic.com > Settings > Workspaces (starts with wrkspc_).'
            ask 'Workspace ID: '
            WORKSPACE=$(printf '%s' "$REPLY" | tr -d '[:space:]')
            if [ "$style" = api ]; then write_headers x-api-key "$key"; else write_headers Authorization "Bearer $key"; fi
            key_test "$ANTHROPIC_URL" claude-haiku-5-5
          fi
          if [ "$HTTP_STATUS" = 200 ]; then AUTH_VAR=$var; break; fi
          if ! key_rejected; then fallback=$var; break; fi
        done
        ;;
      *)
        MODE=gateway
        write_headers Authorization "Bearer $key"
        for model in jam-claude-haiku jam-claude-sonnet; do
          key_test "$GATEWAY_URL" "$model"
          [ "$HTTP_STATUS" = 200 ] && break
        done
        if [ "$HTTP_STATUS" = 200 ]; then AUTH_VAR=ANTHROPIC_AUTH_TOKEN
        elif ! key_rejected; then fallback=ANTHROPIC_AUTH_TOKEN; fi
        ;;
    esac
    rm -f "$TMP/headers"

    [ -n "$AUTH_VAR" ] && break
    if [ -n "$fallback" ]; then
      # The key was accepted but the test request failed (budget, overload, network, model access).
      note "The test request failed, but not because of the key (HTTP $HTTP_STATUS):"
      note "$(error_text)"
      ask 'Save these settings anyway? [y/N] '
      if is_yes "$REPLY"; then AUTH_VAR=$fallback; break; fi
      die 'Setup stopped. Fix the problem above and run this again.'
    fi
    note "That key didn't work (HTTP $HTTP_STATUS). Copy it again in full from your email; it is often cut short."
    WORKSPACE=''
    attempt=$((attempt + 1))
    [ "$attempt" -le 3 ] && echo '    Try again.'
  done
  [ -n "$AUTH_VAR" ] || die 'No working key after 3 tries. Check the key with whoever gave it to you.'
  if [ "$MODE" = official ]; then ok 'Using the official Anthropic API'; else ok 'Using the jam gateway'; fi

  step 'Saving settings'
  if [ "$MODE" = official ]; then
    settings="$AUTH_VAR=$key"
    [ -n "$WORKSPACE" ] && settings="$settings
ANTHROPIC_CUSTOM_HEADERS=anthropic-workspace-id: $WORKSPACE"
    settings="$settings
ANTHROPIC_MODEL=sonnet"
  else
    settings="ANTHROPIC_BASE_URL=$GATEWAY_URL
ANTHROPIC_AUTH_TOKEN=$key
ANTHROPIC_MODEL=jam-claude-sonnet
ANTHROPIC_DEFAULT_SONNET_MODEL=jam-claude-sonnet
ANTHROPIC_DEFAULT_OPUS_MODEL=jam-claude-sonnet
ANTHROPIC_DEFAULT_HAIKU_MODEL=jam-claude-haiku"
  fi
  settings="$settings
CLAUDE_CODE_EFFORT_LEVEL=$EFFORT_LEVEL"

  for f in $RC_FILES; do strip_block "$f" "$BLOCK_START" "$BLOCK_END"; done
  handle_stray
  rc=$(pick_rc)
  touch "$rc" || die "Could not write $rc."
  {
    [ -s "$rc" ] && printf '\n'
    printf '%s\n' "$BLOCK_START"
    [ "$NEED_PATH" = yes ] && printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"'
    printf '%s\n' "$settings" | while IFS= read -r line; do
      printf "export %s='%s'\n" "${line%%=*}" "${line#*=}"
    done
    printf '%s\n' "$BLOCK_END"
  } >> "$rc"
  # This process gets the same settings, so Claude Code can start right away.
  unset_managed
  while IFS= read -r line; do export "${line%%=*}=${line#*=}"; done <<EOF
$settings
EOF
  ok "Saved in $rc. New terminal windows pick it up."

  # Images only work through the jam gateway, so the note is only added for jam keys.
  if [ "$MODE" = gateway ]; then
    if add_note; then ok 'Claude Code can now make images: just ask it, for example "make a pixel-art sword icon"'
    else note "Could not update $CLAUDE_MD. Everything else is set up."; fi
  else
    remove_note
  fi

  step 'Ready'
  [ "$AUTH_VAR" = ANTHROPIC_API_KEY ] && note 'If Claude asks "Do you want to use this API key?", choose Yes.'
  echo '    Next time: open a new terminal window in your project folder and type: claude'
  echo '    Terminal windows that were already open keep the old settings, so close them.'
  ask 'Start Claude Code now? [Y/n] '
  if ! is_no "$REPLY"; then
    # Start in a dedicated folder, not wherever the terminal happened to be.
    work_dir="$HOME/claude-projects"
    mkdir -p "$work_dir" && cd "$work_dir" || die "Could not open $work_dir."
    echo "    Starting Claude Code in $work_dir"
    rm -rf "$TMP"
    exec "$CLAUDE_BIN" <&3
  fi
}

# ---------------------------------------------------------------------------
do_undo() { # $1 = reset or remove
  step 'Checking that Claude Code is closed'
  if claude_running; then
    note 'Claude Code is still open. Type /exit in it, or close its window.'
    ask 'Or close it for you now? Anything it is doing stops. [y/N] '
    if is_yes "$REPLY"; then pkill -x claude; sleep 2; else die 'Close Claude Code, then run this again.'; fi
  fi
  ok 'Claude Code is closed'

  step 'Removing the jam settings'
  removed=no
  for f in $RC_FILES; do
    if strip_block "$f" "$BLOCK_START" "$BLOCK_END"; then ok "Removed them from $f"; removed=yes; fi
  done
  [ "$removed" = yes ] || ok 'No jam settings found'
  handle_stray

  if [ "$1" = reset ]; then
    step 'Backing up Claude Code settings'
    stamp=$(date +%Y%m%d-%H%M%S)
    moved=0
    for p in "$HOME/.claude" "$HOME/.claude.json"; do
      [ -e "$p" ] || continue
      mv "$p" "$p.bak-$stamp" || die "Could not move $p. Close every terminal and VS Code window, then run this again."
      ok "Moved $(basename "$p") to $(basename "$p").bak-$stamp"
      moved=$((moved + 1))
    done
    [ "$moved" -gt 0 ] || ok 'Nothing to back up'
  else
    step 'Removing the image note'
    if remove_note; then ok "Removed it from $CLAUDE_MD"; else ok 'Nothing to remove'; fi
  fi

  step 'Done'
  if [ "$1" = reset ]; then
    note 'Your Xsolla MCP connection was in those settings, so connect it again after the setup (guide step 4, Option A).'
    ask 'Run the setup again now? [Y/n] '
    if ! is_no "$REPLY"; then unset_managed; do_setup; return; fi
    echo '    Next: run the setup command again and paste your key.'
  else
    echo '    Open a new terminal window before you use Claude Code again.'
    echo '    If it asks you to sign in, sign in with your own account.'
  fi
}

# ---------------------------------------------------------------------------
main() {
  case "$(uname -s)" in
    Darwin|Linux) ;;
    *) die 'This setup is for macOS and Linux. On Windows, use setup-claude.zip.' ;;
  esac
  command -v curl >/dev/null 2>&1 || die 'curl is missing. Install it, then run this again.'
  # JAM_TTY is only for testing; normally the answers come from the terminal.
  { : < "${JAM_TTY:-/dev/tty}"; } 2>/dev/null || die 'Run this in a terminal window, so it can ask for your key.'
  exec 3< "${JAM_TTY:-/dev/tty}"
  TMP=$(mktemp -d) || die 'Could not create a temporary folder.'
  trap 'rm -rf "$TMP"' EXIT
  ORIG_PATH=$PATH

  case "${1:-setup}" in
    setup)  do_setup ;;
    reset)  do_undo reset ;;
    remove) do_undo remove ;;
    *)      die "Unknown option: $1. Use reset or remove, or nothing to set up." ;;
  esac
}

main "$@"
