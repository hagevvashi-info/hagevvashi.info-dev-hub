#!/command/with-contenv bash
set -euo pipefail

echo "Setting up mise environment for s6 services..."

export HOME=/home/${UNAME}

# mise 設定ファイルを自動的に trust（対話的な確認を回避）
echo "  Trusting mise configuration files..."
su - ${UNAME} -c 'mise trust --all' 2>/dev/null || true

# mise env の出力を解析して、各環境変数を s6 の環境変数ディレクトリに書き込む
while IFS='=' read -r line; do
    # 空行をスキップ
    [ -z "$line" ] && continue
    
    # key=value に分割
    key="${line%%=*}"
    value="${line#*=}"
    
    # export を除去
    key=$(echo "$key" | sed 's/^export //')
    
    # 空のキーをスキップ
    [ -z "$key" ] && continue
    
    # 値のクォートを除去
    value=$(echo "$value" | sed "s/^['\"]//;s/['\"]$//")
    
    # s6 環境変数に書き込み
    printf "%s" "$value" > "/run/s6/container_environment/$key"
    echo "  Set $key"
done < <(su - ${UNAME} -c 'mise env -s bash')

echo "mise environment setup complete"
