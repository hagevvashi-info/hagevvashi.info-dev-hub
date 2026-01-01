echo "Setting paths..."

# ユーザーのローカルbinディレクトリ（pipxなどで利用）
echo "Setting local bin path..."
export PATH="${HOME}/.local/bin:${PATH}"

# asdfのパス設定
echo "Setting asdf path..."
export PATH="${HOME}/.asdf/bin:${HOME}/.asdf/shims:${PATH}"

# tfenvのパス設定
echo "Setting tfenv path..."
export PATH="${HOME}/.tfenv/bin:${PATH}"
