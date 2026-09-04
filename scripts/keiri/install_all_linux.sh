# ！このファイルは GScale-jp/fde-setup (@b74f5a8) から自動生成されています。
# ！ここを直接編集しないでください。編集は fde-setup 側 → vendor_onboard.sh で再生成。
# ！profile: daimaru-keiri
#!/usr/bin/env bash
# =============================================================
# install_all_linux.sh — GScale FDE 一括セットアップ（Linux）
#
# Node.js / @google/clasp / Python / gcloud SDK / uv(+workspace-mcp=gws) /
# Claude Code(CLI) / git / GitHub CLI(gh) / VS Code を一括導入。
#
# 対応: Debian/Ubuntu(apt) と Fedora/RHEL(dnf/yum) を自動判定。
#       root 以外は sudo を使う。sudo が無い環境では ~/.local への
#       ユーザー領域導入に自動フォールバック（node/gh/uv/claude/gcloud/clasp）。
# 冪等: 導入済みはスキップ。
#
# 実行: bash install_all_linux.sh
# オプション（環境変数）:
#   CHECK_ONLY=1               何も変更せず現状診断だけ行う（サポートの切り分け用）
#   MINIMAL=1                  コアのみ導入（node/git/gh/claude + Claude既定設定）
#   WITH_PYTHON=1              MINIMAL=1 でも Python を入れる（Excel/CSV 処理など）
#   WITH_PLAYWRIGHT=1          Playwright と chromium を導入し、実際に起動して確認する
#   SKIP_PYTHON=1 SKIP_VSCODE=1
#   RESTORE_CREDS=<zip|tar.gz> backup_creds の出力から認証情報を復元
#   RESTORE_ONLY=1             復元だけ実行（ツール導入はしない）
#   TRUST_DIR=<path>           Claude Code の信頼済みフォルダを事前登録（ベストエフォート）
#
# 終了コード: 0=コア全て導入済(PASS) / 2=一部未導入(PARTIAL)
# 実行ログ: ~/fde-setup-install.log に自動保存（つまずいたらこのファイルをサポートへ）
# =============================================================
set -uo pipefail

has() { command -v "$1" >/dev/null 2>&1; }
log() { printf '%s\n' "$*"; }
ok()  { log "  OK  $1"; }
ng()  { log "  --  $1"; }
warn(){ log "  !   $1"; }

START_TS=$(date +%s)
CHECK_ONLY="${CHECK_ONLY:-0}"
MINIMAL="${MINIMAL:-0}"
SKIP_PYTHON="${SKIP_PYTHON:-0}"
SKIP_VSCODE="${SKIP_VSCODE:-0}"
LOCAL_BIN="$HOME/.local/bin"
LOCAL_NODE="$HOME/.local/node"
ARCH="$(uname -m)"   # x86_64 / aarch64

# 権限: root / sudoあり / sudoなし（ユーザー領域導入）
SUDO=""; SUDOE=""; NOSUDO=0
if [ "$(id -u)" -ne 0 ]; then
  if has sudo; then SUDO="sudo"; SUDOE="sudo -E"
  else NOSUDO=1; fi
fi

# パッケージマネージャ判定
if   has apt-get; then PM=apt
elif has dnf;     then PM=dnf
elif has yum;     then PM=yum
else PM=""; fi

pm_install() { # $@ = パッケージ名（sudo 無しの一般ユーザーでは使えない）
  [ "$NOSUDO" = "1" ] && return 1
  case "$PM" in
    apt) $SUDO apt-get install -y "$@" >/dev/null 2>&1 ;;
    dnf) $SUDO dnf install -y "$@" >/dev/null 2>&1 ;;
    yum) $SUDO yum install -y "$@" >/dev/null 2>&1 ;;
    *)   return 1 ;;
  esac
}

# ---- 実行ログ（診断モード以外は自動でファイルにも残す）----------
LOG_FILE="${FDE_LOG:-$HOME/fde-setup-install.log}"
if [ "$CHECK_ONLY" != "1" ] && [ "${FDE_NO_LOG:-0}" != "1" ] && touch "$LOG_FILE" 2>/dev/null; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

github_latest_tag() { # $1=owner/repo → vX.Y.Z（リダイレクト解決＝APIレート制限の影響を受けない。失敗時のみAPI）
  local tag
  tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null | tr -d '\r' | sed -n 's|.*/tag/||p')"
  if [ -z "$tag" ]; then
    tag="$(curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  fi
  printf '%s' "$tag"
}

node_lts_version() { # 最新 LTS の vX.Y.Z（index.tab の lts 列で判定）
  curl -fsSL https://nodejs.org/dist/index.tab 2>/dev/null | awk -F'\t' 'NR>1 && $10!="-" {print $1; exit}'
}

ensure_local_path() { # ユーザー領域導入時の PATH（現行シェル＋次回以降）
  mkdir -p "$LOCAL_BIN"
  export PATH="$LOCAL_BIN:$LOCAL_NODE/bin:$PATH"
  local marker='# >>> FDE PATH >>>' rc
  for rc in "$HOME/.bashrc" "$HOME/.profile"; do
    if ! grep -qs "$marker" "$rc" 2>/dev/null; then
      {
        echo ''
        echo "$marker"
        echo 'export PATH="$HOME/.local/bin:$HOME/.local/node/bin:$PATH"'
        echo '[ -d "$HOME/google-cloud-sdk/bin" ] && export PATH="$HOME/google-cloud-sdk/bin:$PATH"'
        echo '# <<< FDE PATH <<<'
      } >> "$rc"
    fi
  done
}

install_node_tarball() { # 公式 tarball → ~/.local/node（NodeSource が使えない環境向け）
  local ver narch tmp
  ver="$(node_lts_version)"
  narch=x64; [ "$ARCH" = "aarch64" ] && narch=arm64
  [ -z "$ver" ] && return 1
  ensure_local_path
  log "  + 公式 tarball $ver ($narch) → ~/.local/node ..."
  tmp="$(mktemp -d)"
  if curl -fsSL "https://nodejs.org/dist/$ver/node-$ver-linux-$narch.tar.gz" -o "$tmp/node.tgz"; then
    rm -rf "$LOCAL_NODE"; mkdir -p "$LOCAL_NODE"
    tar -xzf "$tmp/node.tgz" -C "$LOCAL_NODE" --strip-components 1
  fi
  rm -rf "$tmp"
  has node
}

# ---- サマリ（機械可読な FDE_RESULT 行で終わる）------------------
detect_summary() {
  log ""
  log "================================================"
  log " 導入結果サマリ"
  log "================================================"
  local core missing=() t n m elapsed
  if [ "$MINIMAL" = "1" ]; then core="node npm git gh claude"
  else core="node npm clasp python3 gcloud uv uvx claude git gh"; fi
  # 明示指定した追加ツールも「入っていて当然」の扱いにする（PARTIAL で気づけるように）
  case " $core " in *" python3 "*) : ;; *) [ "${WITH_PYTHON:-0}" = "1" ] && core="$core python3" ;; esac
  [ "${WITH_PLAYWRIGHT:-0}" = "1" ] && core="$core playwright"
  m=0
  for t in $core; do
    m=$((m + 1))
    has "$t" && ok "$t" || { ng "${t}（未導入 / 新シェルで反映の場合あり）"; missing+=("$t"); }
  done
  if [ "$MINIMAL" != "1" ]; then
    has code && ok "code（任意）" || ng "code（任意・GUI環境向け）"
  fi
  n=${#missing[@]}
  elapsed=$(( $(date +%s) - START_TS ))
  log ""
  if [ "$n" -eq 0 ]; then
    log "FDE_RESULT: PASS core=$m/$m elapsed=${elapsed}s"
    return 0
  else
    log "FDE_RESULT: PARTIAL core=$((m - n))/$m missing=$(IFS=,; echo "${missing[*]}") elapsed=${elapsed}s"
    return 2
  fi
}

# ---- アーカイブ安全性の事前検査（zip-slip / tar トラバーサル / symlink 越境の防止）----
# 悪意あるバックアップを復元させられても $HOME 外へ書き込ませない。正規の backup_creds 出力は
# トップレベルの固定名のみで、絶対パス・.. ・リンクを一切含まない。
archive_is_unsafe() { # $1=archive → 0(=危険) を返したら復元を中止する
  local f="$1" names verbose
  case "$f" in
    *.tar.gz|*.tgz)
      # リンク（symlink/hardlink）検出は -tv のタイプ文字・" -> "・"link to" で判定
      verbose="$(tar -tzvf "$f" 2>/dev/null)" || return 0   # 読めない=安全側に倒して拒否
      printf '%s\n' "$verbose" | grep -qE '^[lh]|[[:space:]]->[[:space:]]|[[:space:]]link to[[:space:]]' && return 0
      # 絶対パス / .. の検査はメンバー名だけ（メタデータ列を含む -tv ではなく -t）で行う
      names="$(tar -tzf "$f" 2>/dev/null)" || return 0
      ;;
    *.zip)
      # -Z1 はメンバー名のみを1行ずつ出力（"Archive:" ヘッダ等のノイズが混じらない）
      names="$(unzip -Z1 "$f" 2>/dev/null)"
      [ -z "$names" ] && names="$(python3 -c 'import sys,zipfile
[print(n) for n in zipfile.ZipFile(sys.argv[1]).namelist()]' "$f" 2>/dev/null)"
      [ -z "$names" ] && return 0
      ;;
    *) return 0 ;;
  esac
  # メンバー名に絶対パス（先頭 /）または .. パス成分があれば拒否
  printf '%s\n' "$names" | grep -qE '^/|(^|/)\.\.(/|$)' && return 0
  return 1
}

# ---- 認証情報の復元（backup_creds の zip / 旧 tar.gz 両対応）----
restore_creds() {
  local f="$1" stg
  log ""; log "[+] 認証情報の復元: $f"
  [ -f "$f" ] || { log "  X ファイルが見つかりません: $f"; return 1; }
  if archive_is_unsafe "$f"; then
    log "  X 危険なパス（絶対パス / .. / シンボリックリンク）を含むため復元を中止しました: $f"
    return 1
  fi
  stg="$(mktemp -d)"
  case "$f" in
    *.zip)
      if has unzip; then unzip -oq "$f" -d "$stg"
      elif has python3; then python3 -m zipfile -e "$f" "$stg"
      else log "  X unzip も python3 も無く ZIP を展開できません"; rm -rf "$stg"; return 1; fi ;;
    *.tar.gz|*.tgz) tar -xzf "$f" -C "$stg" ;;
    *) log "  X 対応形式は .zip / .tar.gz です"; rm -rf "$stg"; return 1 ;;
  esac
  # マッピング用ヘルパ（固定の展開先のみに書き込む＝アーカイブ内の名前でトラバーサルされない）
  _put() { # $1=アーカイブ内の名前 $2=展開先
    [ -e "$stg/$1" ] || return 0
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst" 2>/dev/null || true
    cp -R "$stg/$1" "$dst" && ok "復元 $dst"
  }
  # 統一レイアウト（トップレベル配置・Windows/macOS/Linux 共通）を各所へマッピング
  _put ".clasprc.json"         "$HOME/.clasprc.json"
  _put "gcloud"                "$HOME/.config/gcloud"
  _put "gh"                    "$HOME/.config/gh"
  _put "GitHub CLI"            "$HOME/.config/gh"
  _put ".credentials.json"     "$HOME/.claude/.credentials.json"
  _put ".google_workspace_mcp" "$HOME/.google_workspace_mcp"
  # 旧レイアウト（HOME 相対: .config/... .claude/...）も「既知パスだけ」を明示コピー。
  # かつての cp -R "$stg/." "$HOME/"（ブランケットコピー）は、悪意あるアーカイブで
  # ~/.ssh/authorized_keys や ~/.bashrc 等を上書きでき RCE に至るため廃止した。
  _put ".config/gcloud"            "$HOME/.config/gcloud"
  _put ".config/gh"                "$HOME/.config/gh"
  _put ".claude/.credentials.json" "$HOME/.claude/.credentials.json"
  # .claude.json（両レイアウトともトップレベル。既存があれば保持）
  if [ -f "$HOME/.claude.json" ]; then
    ng ".claude.json は既存を保持（バックアップ内は最小化版のため上書きしない）"
  else
    _put ".claude.json" "$HOME/.claude.json"
  fi
  chmod 600 "$HOME/.claude/.credentials.json" "$HOME/.clasprc.json" 2>/dev/null || true
  rm -rf "$stg"
  log "  → clasp / gcloud / gh / claude / gws が再ログイン無しで使えるはずです。"
  return 0
}

# =============================================================
# メイン
# =============================================================
log "================================================"
log " GScale FDE 一括セットアップ (Linux)"
log "  $( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}" ) / $ARCH / PM=${PM:-none}"
MODE_NOTE=""
[ "$CHECK_ONLY" = "1" ] && MODE_NOTE="$MODE_NOTE [診断のみ]"
[ "$MINIMAL" = "1" ]    && MODE_NOTE="$MODE_NOTE [MINIMAL]"
[ "$NOSUDO" = "1" ]     && MODE_NOTE="$MODE_NOTE [sudoなし→ユーザー領域]"
[ -n "$MODE_NOTE" ] && log "  モード:$MODE_NOTE"
log "================================================"

# 復元だけ実行するモード
if [ "${RESTORE_ONLY:-0}" = "1" ]; then
  restore_creds "${RESTORE_CREDS:?RESTORE_ONLY=1 には RESTORE_CREDS=<file> の指定が必要です}"
  exit $?
fi

# ネットワーク事前診断（プロキシ/セキュリティソフトの切り分け・警告のみで続行）
if ! curl -fsSI -m 8 https://claude.ai >/dev/null 2>&1 && ! curl -fsSI -m 8 https://www.google.com >/dev/null 2>&1; then
  warn "外部サイトへ接続できません。プロキシ/ネット接続を確認してください（続行はします）。"
fi

# 診断のみモード: 何も変更せず現状を報告して終了
if [ "$CHECK_ONLY" = "1" ]; then
  detect_summary
  exit $?
fi

[ "$NOSUDO" = "1" ] && { warn "sudo が使えないため、可能なツールは ~/.local に導入します（python/git/VS Code は管理者に依頼）。"; ensure_local_path; }
[ "$PM" = "apt" ] && [ "$NOSUDO" = "0" ] && $SUDO apt-get update -y >/dev/null 2>&1 || true

# ---- 1. Node.js（NodeSource LTS → 失敗時は公式 tarball）--------
log ""; log "[1] Node.js (LTS)"
if has node; then ok "node $(node --version)"
else
  if [ "$NOSUDO" = "0" ]; then
    if [ "$PM" = "apt" ]; then
      curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDOE bash - >/dev/null 2>&1
      pm_install nodejs
    elif [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | $SUDOE bash - >/dev/null 2>&1
      pm_install nodejs
    fi
  fi
  has node || install_node_tarball || true
  has node && ok "node $(node --version)" || log "  X node 未導入"
fi

# ---- 2. @google/clasp（npm）------------------------------------
if [ "$MINIMAL" != "1" ]; then
  log ""; log "[2] @google/clasp"
  if has clasp; then ok "clasp $(clasp --version 2>/dev/null)"
  elif has npm; then
    # まず通常の -g、権限で失敗したら ~/.local prefix、それでも駄目なら sudo
    if npm install -g @google/clasp >/dev/null 2>&1; then :
    elif npm install -g --prefix "$HOME/.local" @google/clasp >/dev/null 2>&1; then ensure_local_path
    elif [ "$NOSUDO" = "0" ] && [ -n "$SUDO" ]; then $SUDO npm install -g @google/clasp >/dev/null 2>&1 || true
    fi
    has clasp && ok "clasp 導入" || log "  X clasp 失敗"
  else log "  X npm 無し（Node 導入後に再実行）"; fi
fi

# ---- 3. Python --------------------------------------------------
# WITH_PYTHON=1 は「コアのみ + Python」（Excel/CSV 処理が要る案件）用。
if [ "$MINIMAL" != "1" ] || [ "${WITH_PYTHON:-0}" = "1" ]; then
  log ""; log "[3] Python 3"
  if [ "$SKIP_PYTHON" = "1" ]; then ng "python (skip)"
  elif has python3; then ok "$(python3 --version 2>&1)"
  elif [ "$NOSUDO" = "1" ]; then warn "sudo なしでは python3 を導入できません（管理者に依頼: $PM install python3）"
  else pm_install python3 python3-pip; has python3 && ok "$(python3 --version)" || log "  X python3 未導入"; fi
fi

# ---- 4. gcloud SDK（公式 tar.gz 直接展開・ディストリ非依存・ユーザー領域）
# ※ sdk.cloud.google.com の bash インストーラは `which` に依存し、Fedora 最小構成等で失敗するため使わない
if [ "$MINIMAL" != "1" ]; then
  log ""; log "[4] gcloud SDK"
  if has gcloud; then ok "$(gcloud --version 2>/dev/null | head -1)"
  else
    GC_ARCH=x86_64; [ "$ARCH" = "aarch64" ] && GC_ARCH=arm
    log "  + 公式 tar.gz → ~/google-cloud-sdk（容量が大きく数分かかります）..."
    GCTMP="$(mktemp -d)"
    if curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-${GC_ARCH}.tar.gz" -o "$GCTMP/gc.tgz"; then
      rm -rf "$HOME/google-cloud-sdk"
      tar -xzf "$GCTMP/gc.tgz" -C "$HOME"
      "$HOME/google-cloud-sdk/install.sh" --quiet --usage-reporting false --path-update true --command-completion false >/dev/null 2>&1 || true
      export PATH="$HOME/google-cloud-sdk/bin:$PATH"
    fi
    rm -rf "$GCTMP"
    has gcloud && ok "gcloud 導入" || log "  X gcloud 未導入（新シェルで反映の場合あり）"
  fi
fi

# ---- 5. uv / uvx（astral.sh 公式・ユーザー領域）----------------
if [ "$MINIMAL" != "1" ]; then
  log ""; log "[5] uv / uvx"
  if has uv || has uvx; then ok "uv/uvx"
  else curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
       export PATH="$LOCAL_BIN:$HOME/.cargo/bin:$PATH"
       has uvx && ok "uv 導入" || log "  X uv 未導入（新シェルで反映の場合あり）"; fi
fi

# ---- 6. workspace-mcp (gws) 動作確認 ---------------------------
if [ "$MINIMAL" != "1" ]; then
  log ""; log "[6] workspace-mcp (gws)"
  if has uvx; then ( uvx workspace-mcp --help >/dev/null 2>&1 && ok "workspace-mcp 実行可" ) || warn "workspace-mcp 取得失敗（ネット/Python 要確認）"
  else ng "uvx 無し（uv 導入後）"; fi
fi

# ---- 7. Claude Code (CLI)（公式・ユーザー領域）-----------------
log ""; log "[7] Claude Code (CLI)"
if has claude; then ok "claude"
else curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1
     export PATH="$LOCAL_BIN:$PATH"
     has claude && ok "claude 導入" || log "  X claude 未導入（新シェルで反映の場合あり）"; fi

# ---- 8. git ----------------------------------------------------
log ""; log "[8] git"
if has git; then ok "$(git --version)"
elif [ "$NOSUDO" = "1" ]; then warn "sudo なしでは git を導入できません（管理者に依頼: $PM install git）"
else pm_install git; has git && ok "$(git --version)" || log "  X git 未導入"; fi

# ---- 9. GitHub CLI (gh)（公式 tarball・ディストリ非依存）-------
log ""; log "[9] GitHub CLI (gh)"
if has gh; then ok "$(gh --version 2>/dev/null | head -1)"
else
  GTAG="$(github_latest_tag cli/cli)"; GVER="${GTAG#v}"
  GARCH=amd64; [ "$ARCH" = "aarch64" ] && GARCH=arm64
  if [ -n "$GTAG" ]; then
    GTMP="$(mktemp -d)"
    if curl -fsSL "https://github.com/cli/cli/releases/download/$GTAG/gh_${GVER}_linux_${GARCH}.tar.gz" -o "$GTMP/gh.tgz"; then
      tar -xzf "$GTMP/gh.tgz" -C "$GTMP"
      GHBIN="$(find "$GTMP" -type f -name gh -path '*/bin/*' 2>/dev/null | head -1)"
      if [ -n "$GHBIN" ]; then
        if [ "$NOSUDO" = "1" ]; then mkdir -p "$LOCAL_BIN"; cp "$GHBIN" "$LOCAL_BIN/gh"; chmod +x "$LOCAL_BIN/gh"
        else $SUDO cp "$GHBIN" /usr/local/bin/gh 2>/dev/null || { mkdir -p "$LOCAL_BIN"; cp "$GHBIN" "$LOCAL_BIN/gh"; chmod +x "$LOCAL_BIN/gh"; ensure_local_path; }
        fi
      fi
    fi
    rm -rf "$GTMP"
  fi
  has gh && ok "gh 導入" || log "  X gh 未導入"
fi

# ---- 10. VS Code（GUI・任意）-----------------------------------
# WITH_VSCODE=1 は「コアのみ + VS Code」（onboard.sh の lite プロファイル）用。
if [ "$MINIMAL" != "1" ] || [ "${WITH_VSCODE:-0}" = "1" ]; then
  log ""; log "[10] Visual Studio Code"
  if [ "$SKIP_VSCODE" = "1" ]; then ng "code (skip)"
  elif has code; then ok "code"
  elif [ "$NOSUDO" = "1" ]; then ng "code（sudo なしのためスキップ・GUI環境で管理者に依頼）"
  else
    if [ "$PM" = "apt" ]; then
      $SUDO apt-get install -y wget gpg >/dev/null 2>&1
      wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor 2>/dev/null | $SUDO tee /usr/share/keyrings/microsoft.gpg >/dev/null
      echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | $SUDO tee /etc/apt/sources.list.d/vscode.list >/dev/null
      $SUDO apt-get update -y >/dev/null 2>&1; pm_install code
    elif [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
      $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
      printf '[code]\nname=VS Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' | $SUDO tee /etc/yum.repos.d/vscode.repo >/dev/null
      pm_install code
    fi
    has code && ok "code 導入" || ng "code（GUI環境向け・サーバでは不要な場合あり）"
  fi
fi

# ---- Playwright（ブラウザ操作の自動化・WITH_PLAYWRIGHT=1）------
# API が使えない業務システムを Claude Code から操作するための土台。
# ブラウザ本体はユーザー領域のキャッシュに入るため管理者権限は不要。
# 先に取得しておくと、各プロジェクトの npm install が同じキャッシュを共有する。
if [ "${WITH_PLAYWRIGHT:-0}" = "1" ]; then
  log ""; log "[+] Playwright（ブラウザ操作）"
  if ! has npm; then
    log "  X npm 無し（Node 導入後に再実行してください）"
  else
    has playwright || npm install -g playwright >/dev/null 2>&1
    if has playwright; then ok "playwright $(playwright --version 2>/dev/null | head -1)"; else log "  X playwright CLI 未導入"; fi
    log "  ブラウザ(chromium)を取得しています。数分かかります..."
    npx --yes playwright install chromium 2>&1 | sed 's/^/    /'
    # 「ダウンロードは成功したが起動できない」をここで検出する（プロキシ配下で実際に起こる）
    G_ROOT="$(npm root -g 2>/dev/null | tail -1)"
    # プローブは「グローバル node_modules の親」に置く必要がある。書けなければ確認は諦める
    if [ -n "$G_ROOT" ] && [ -d "$G_ROOT" ] && [ -w "$(dirname "$G_ROOT")" ]; then
      # グローバル node_modules の「親」に置くと ESM の解決が playwright を見つけられる
      PW_PROBE="$(dirname "$G_ROOT")/fde_pw_probe.mjs"
      cat > "$PW_PROBE" <<'PWEOF'
import { chromium } from "playwright";
const b = await chromium.launch({ headless: true });
console.log("PW_PROBE_OK " + b.version());
await b.close();
PWEOF
      PW_OUT="$(node "$PW_PROBE" 2>&1)"
      rm -f "$PW_PROBE"
      case "$PW_OUT" in
        *PW_PROBE_OK*) ok "ブラウザ起動を確認: chromium ${PW_OUT##*PW_PROBE_OK }" ;;
        *) log "  X ブラウザを起動できませんでした（ダウンロードは終わっている可能性があります）"
           log "    $PW_OUT" ;;
      esac
    else
      warn "npm root -g を解決できず、起動確認をスキップしました"
    fi
  fi
fi

# ---- Claude Code 既定設定（auto モード・摩擦ゼロ化）------------
# 許可プロンプトを激減させる auto モードを ~/.claude/settings.json に既定化（安全チェックは維持）。
# FDE_CLAUDE_BLOCK_BEGIN
log ""; log "[+] Claude Code 既定設定（auto モード）"
CLAUDE_DIR="$HOME/.claude"; mkdir -p "$CLAUDE_DIR"; CSET="$CLAUDE_DIR/settings.json"
if has node; then
  # 無効JSON/コメント混入の既存ファイルは「上書きせずスキップ」（破壊回避）。env/permissions の型も防御。
  CSET="$CSET" node -e '
    const fs=require("fs"), p=process.env.CSET;
    let o={}, existed=false;
    try { if(fs.existsSync(p)){ const c=fs.readFileSync(p,"utf8").trim(); if(c){ existed=true; o=JSON.parse(c); } } }
    catch(e){ console.error("settings.json 解析失敗（無効JSON/コメント）→ 破壊回避でスキップ"); process.exit(3); }
    if(!o || typeof o!=="object" || Array.isArray(o)) o={};
    o.env=(o.env && typeof o.env==="object" && !Array.isArray(o.env)) ? o.env : {};
    o.env.CLAUDE_CODE_ENABLE_AUTO_MODE="1";
    o.permissions=(o.permissions && typeof o.permissions==="object" && !Array.isArray(o.permissions)) ? o.permissions : {};
    if(!o.permissions.defaultMode) o.permissions.defaultMode="auto";
    if(!Array.isArray(o.permissions.allow)) o.permissions.allow=["Read","Write","Edit","Bash(git:*)","Bash(gh:*)","Bash(python:*)","Bash(python3:*)","Bash(pip:*)","Bash(pip3:*)","Bash(node:*)","Bash(npm:*)","Bash(npx:*)","Bash(clasp:*)","Bash(uv:*)","Bash(uvx:*)","Bash(gcloud:*)","Bash(rg:*)","Bash(grep:*)","Bash(sed:*)","Bash(awk:*)","Bash(ls:*)","Bash(cat:*)","Bash(find:*)","Bash(mkdir:*)","Bash(mv:*)","Bash(cp:*)","Bash(chmod:*)","Bash(which:*)","Bash(echo:*)","Bash(head:*)","Bash(tail:*)","Bash(open:*)","Bash(xdg-open:*)","Bash(code:*)","Bash(bash:*)"];
    if(!Array.isArray(o.permissions.deny)) o.permissions.deny=["Bash(rm -rf:*)","Bash(sudo rm:*)"];
    fs.writeFileSync(p, JSON.stringify(o,null,2)+"\n");
  '
  rc=$?
  if [ "$rc" = "0" ]; then ok "settings.json に auto モード＋安全な許可/拒否リストを設定（既存値は保持）"
  elif [ "$rc" = "3" ]; then ng "既存 settings.json が無効JSON → 破壊回避でスキップ（auto未適用・手動設定可）"
  else log "  X Claude 既定設定 失敗"; fi
else
  if [ ! -f "$CSET" ]; then
    cat > "$CSET" <<'JSON'
{
  "env": { "CLAUDE_CODE_ENABLE_AUTO_MODE": "1" },
  "permissions": {
    "defaultMode": "auto",
    "allow": ["Read","Write","Edit","Bash(git:*)","Bash(gh:*)","Bash(python:*)","Bash(python3:*)","Bash(pip:*)","Bash(pip3:*)","Bash(node:*)","Bash(npm:*)","Bash(npx:*)","Bash(clasp:*)","Bash(uv:*)","Bash(uvx:*)","Bash(gcloud:*)","Bash(rg:*)","Bash(grep:*)","Bash(sed:*)","Bash(awk:*)","Bash(ls:*)","Bash(cat:*)","Bash(find:*)","Bash(mkdir:*)","Bash(mv:*)","Bash(cp:*)","Bash(chmod:*)","Bash(which:*)","Bash(echo:*)","Bash(head:*)","Bash(tail:*)","Bash(open:*)","Bash(xdg-open:*)","Bash(code:*)","Bash(bash:*)"],
    "deny": ["Bash(rm -rf:*)", "Bash(sudo rm:*)"]
  }
}
JSON
    ok "settings.json を作成（auto モード＋安全な許可/拒否リスト）"
  else ng "node 無しのため既存 settings.json は保持（auto は手動設定可）"; fi
fi
log "  * auto モードは Opus 4.7/4.8 で有効（許可待ちを激減・危険操作は自動ブロック）。"
# FDE_CLAUDE_BLOCK_END

# ---- Claude Code 信頼済みフォルダの事前登録（任意・TRUST_DIR）--
# 新PCの非対話運用で「workspace has not been trusted」により権限設定が無効化されるのを防ぐ。
# 内部仕様（~/.claude.json の projects.*.hasTrustDialogAccepted）依存のベストエフォート。
if [ -n "${TRUST_DIR:-}" ]; then
  log ""; log "[+] Claude Code 信頼済みフォルダの事前登録: $TRUST_DIR"
  if [ -d "$TRUST_DIR" ] && has node; then
    ABS="$(cd "$TRUST_DIR" && pwd)" CJ="$HOME/.claude.json" node -e '
      const fs=require("fs"), p=process.env.CJ, d=process.env.ABS;
      let o={};
      try { if(fs.existsSync(p)){ const c=fs.readFileSync(p,"utf8").trim(); if(c) o=JSON.parse(c); } }
      catch(e){ console.error("  ! .claude.json 解析失敗 → 破壊回避でスキップ"); process.exit(3); }
      if(!o || typeof o!=="object" || Array.isArray(o)) o={};
      if(!o.projects || typeof o.projects!=="object" || Array.isArray(o.projects)) o.projects={};
      const pr=(o.projects[d] && typeof o.projects[d]==="object" && !Array.isArray(o.projects[d])) ? o.projects[d] : {};
      pr.hasTrustDialogAccepted=true;
      o.projects[d]=pr;
      fs.writeFileSync(p, JSON.stringify(o,null,2)+"\n");
    ' && ok "登録済（初回の信頼ダイアログを省略できる場合あり・仕様変更時は無害に失敗）" || warn "登録できませんでした（初回に対話で claude を起動して承諾してください）"
  else
    warn "ディレクトリが存在しない / node 無しのためスキップ（初回に対話で claude を起動して承諾してください）"
  fi
fi

# ---- 認証情報の復元（任意・RESTORE_CREDS=<zip|tar.gz>）---------
if [ -n "${RESTORE_CREDS:-}" ]; then
  restore_creds "$RESTORE_CREDS" || true
fi

# ---- サマリ ----------------------------------------------------
detect_summary
RC=$?
log ""
log "※ 反映を確実にするにはシェルを開き直してください。"
log "※ Claude Code は auto モード既定（許可待ち最小化／Opus 4.7+）。変更は ~/.claude/settings.json。"
log "※ 次のログイン/登録は別途(対話): claude（初回起動＋フォルダ信頼）/ clasp login / gcloud auth login / gws(MCP)登録。"
log "※ 実行ログ: ${LOG_FILE}（つまずいたらこのファイルをサポートへ送ってください）"
exit $RC
