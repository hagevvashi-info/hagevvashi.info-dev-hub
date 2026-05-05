#!/bin/sh

# s6-rc サービスをコンパイル
echo "Compiling s6-rc services..."
if [ -d "/etc/s6-rc/compiled" ]; then
    sudo rm -rf /etc/s6-rc/compiled
fi

# s6-rc-compile を実行する前に、ターゲットディレクトリを作成
sudo mkdir -p /etc/s6-rc/compiled

sudo /command/s6-rc-compile /etc/s6-rc/service /etc/s6-rc/compiled
sudo /command/s6-rc-update -c /etc/s6-rc/compiled add default
echo "s6-rc services compiled."

# s6-overlay の init を実行
exec /init
