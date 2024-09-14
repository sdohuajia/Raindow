#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/Rainbow.sh"

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 安装并启动节点的函数
function install_and_start_node() {
    # 定义目录路径
    DIR="/root/project/run_btc_testnet4/data"

    # 创建目录
    mkdir -p "$DIR"

    # 检查目录是否创建成功
    if [ $? -eq 0 ]; then
        echo "目录 $DIR 创建成功！"
    else
        echo "目录 $DIR 创建失败！"
        exit 1
    fi

    # 安装Screen
    sudo apt install -y screen
    
    # 检查是否已安装 Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker 未安装，正在安装 Docker..."

        # 安装 Docker 和依赖
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl start docker
        sudo systemctl enable docker
    else
        echo "Docker 已安装，跳过安装步骤。"
    fi

    # 验证 Docker 状态
    echo "Docker 状态:"
    sudo systemctl status docker --no-pager

    # 检查是否已安装 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose 未安装，正在安装 Docker Compose..."
        DOCKER_COMPOSE_VERSION="2.20.2"
        sudo curl -L "https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose 已安装，跳过安装步骤。"
    fi

    # 输出 Docker Compose 版本
    echo "Docker Compose 版本:"
    docker-compose --version

    # 克隆 GitHub 仓库
    echo "克隆 GitHub 仓库..."
    git clone https://github.com/rainbowprotocol-xyz/btc_testnet4
    if [ $? -ne 0 ]; then
        echo "克隆仓库失败！"
        exit 1
    fi

    # 进入克隆下来的目录
    cd btc_testnet4 || { echo "进入目录失败！"; exit 1; }

    # 启动容器
    echo "启动 Docker 容器..."
    docker-compose up -d

    # 进入容器并执行 Bitcoin CLI 命令
    echo "进入 Docker 容器并创建钱包..."
    docker exec -it $(docker ps -q -f "name=bitcoind") /bin/bash -c "bitcoin-cli -testnet4 -rpcuser=demo -rpcpassword=demo -rpcport=5000 createwallet walletname"

    # 查看钱包地址
    echo "获取新钱包地址..."
    docker exec -it $(docker ps -q -f "name=bitcoind") /bin/bash -c "bitcoin-cli -testnet4 -rpcuser=demo -rpcpassword=demo -rpcport=5000 getnewaddress"

    # 等待用户退出容器
    sleep 5 # 适当调整等待时间，确保用户有时间退出容器

    # 克隆新的 GitHub 仓库
    echo "克隆新的 GitHub 仓库并配置..."
    cd
    git clone https://github.com/rainbowprotocol-xyz/rbo_indexer_testnet && cd rbo_indexer_testnet

    # 下载并设置权限
    wget https://github.com/rainbowprotocol-xyz/rbo_indexer_testnet/releases/download/v0.0.1-alpha/rbo_worker
    chmod +x rbo_worker

    # 自动创建 docker-compose.yml 文件
    echo "自动创建 docker-compose.yml 文件..."
    cat <<EOL > docker-compose.yml
version: '3'
services:
  bitcoind:
    image: mocacinno/btc_testnet4:bci_node
    privileged: true
    container_name: bitcoind
    volumes:
      - /root/project/run_btc_testnet4/data:/root/.bitcoin/
    command: ["bitcoind", "-testnet4", "-server","-txindex", "-rpcuser=demo", "-rpcpassword=demo", "-rpcallowip=0.0.0.0/0", "-rpcbind=0.0.0.0:5000"]
    ports:
      - "8333:8333"
      - "48332:48332"
      - "5000:5000"
EOL

    echo "完成配置，docker-compose.yml 文件已创建。"

    # 启动 Docker Compose
    echo "启动 Docker Compose..."
    docker-compose up -d

    # 检查 Docker Compose 启动状态
    if [ $? -ne 0 ]; then
        echo "Docker Compose 启动失败。请检查容器日志并处理错误。"
        echo "获取容器 ID 和重新启动容器..."

        # 提示用户获取容器 ID
        echo "请运行以下命令来停止和删除出现错误的容器:"
        echo "1. 查看正在运行的容器: docker ps"
        echo "2. 复制出现错误的容器 ID 并运行: docker stop <容器 ID>"
        echo "3. 运行: docker rm <容器 ID>"

        # 提示用户输入容器 ID
        read -p "请输入出现错误的容器 ID 并按 Enter 键: " CONTAINER_ID

        # 停止和删除指定容器
        echo "停止容器 $CONTAINER_ID..."
        docker stop "$CONTAINER_ID"
        
        echo "删除容器 $CONTAINER_ID..."
        docker rm "$CONTAINER_ID"

        # 提示用户重新启动 Docker Compose
        echo "处理完容器错误后，重新启动 Docker Compose:"
        docker-compose up -d

        # 提示用户按任意键返回主菜单
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
        exit 1
    fi

    echo "所有步骤已完成。"

    # 提示用户按任意键返回主菜单
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 连接 Bitcoin Core 并运行索引器的函数
function connect_and_run_indexer() {
    echo "连接 Bitcoin Core 并运行索引器..."

    screen -S Rainbow -dm
    screen -S Rainbow -X stuff $'cd /root/rbo_indexer_testnet && ./rbo_worker worker --rpc http://127.0.0.1:5000 --password demo --username demo --start_height 44938\n'

    echo "索引器正在运行。"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 获取 Principal ID 的函数
function edit_principal() {
    mkdir -p /root/rbo_indexer_testnet/identity

    if [ -f /root/rbo_indexer_testnet/identity/principal.json ]; then
        echo "导出 principal.json 文件的内容..."
        cat /root/rbo_indexer_testnet/identity/principal.json
    else
        echo "文件 /root/rbo_indexer_testnet/identity/principal.json 不存在。"
    fi

    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 更新脚本的函数
function update_script() {
    echo "正在更新 rbo_worker..."

    # 重新启动 Rainbow 监控
    echo "重新启动 Rainbow 监控..."
    screen -S Rainbow -dm

    # 下载最新版本的 rbo_worker
    echo "下载最新版本的 rbo_worker..."
    wget https://storage.googleapis.com/rbo/rbo_worker/rbo_worker-linux-amd64-0.0.2-20240914-4ec80a8.tar.gz

    # 创建目录用于解压
    UPDATE_DIR="/root/rbo_indexer_testnet"
    echo "创建目录 $UPDATE_DIR..."
    mkdir -p "$UPDATE_DIR"

    # 解压下载的文件到创建的目录
    echo "解压下载的文件..."
    tar -xzvf rbo_worker-linux-amd64-0.0.2-20240914-4ec80a8.tar.gz -C "$UPDATE_DIR" --strip-components=1

    # 清理不必要的文件
    echo "清理临时文件..."
    rm rbo_worker-linux-amd64-0.0.2-20240914-4ec80a8.tar.gz

    # 向现有的 screen 会话发送命令
    echo "向 Rainbow 会话发送命令..."
    screen -S Rainbow -X stuff $'cd /root/rbo_indexer_testnet && nohup ./rbo_worker worker --rpc http://127.0.0.1:5000 --password demo --username demo --start_height 44938 --indexer_port 5050 > worker.log 2>&1 &\n'

    echo "rbo_worker 更新和监控重启完成。"

    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 停止并删除脚本相关内容的函数
function cleanup_and_remove_script() {
    echo "停止并删除脚本相关 Docker 容器..."

    # 停止并删除 Docker 容器
    cd /root/btc_testnet4
    docker-compose down

    cd /root/rbo_indexer_testnet
    docker-compose down
    
    echo "删除克隆的 GitHub 仓库..."
    rm -rf /root/project/run_btc_testnet4
    rm -rf /root/rbo_indexer_testnet
    rm -rf /root/btc_testnet4

    echo "所有内容已删除，脚本将退出。"
    exit 0
}

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "脚本由大赌社区哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "如有问题，可联系推特，仅此只有一个号"
        echo "================================================================"
        echo "退出脚本，请按键盘 ctrl + C 退出即可"
        echo "请选择要执行的操作:"
        echo "1. 安装并启动节点"
        echo "2. 连接 Bitcoin Core 并运行索引器"
        echo "3. 获取 Principal ID"
        echo "4. 更新脚本"
        echo "5. 停止并删除节点（请保存好钱包文件）"
        read -p "请输入选项 [1-5]: " option
        case $option in
            1)
                install_and_start_node
                ;;
            2)
                connect_and_run_indexer
                ;;
            3)
                edit_principal
                ;;
            4)
                update_script
                ;;
            5)
                cleanup_and_remove_script
                ;;
            *)
                echo "无效的选项，请选择 [1-5]"
                ;;
        esac
    done
}

# 运行主菜单
main_menu
