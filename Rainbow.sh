#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/Rainbow.sh"

# 安装并启动节点的函数
function install_and_start_node() {
    DIR="/root/project/run_btc_testnet4/data"
    mkdir -p "$DIR"

    if [ $? -ne 0 ]; then
        echo "目录 $DIR 创建失败！"
        exit 1
    fi

    echo "安装 Docker 和 Docker Compose..."

    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl start docker
    sudo systemctl enable docker

    if [ $? -ne 0 ]; then
        echo "Docker 安装失败！"
        exit 1
    fi

    echo "Docker 状态:"
    sudo systemctl status docker --no-pager

    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose 未安装，正在安装..."
        DOCKER_COMPOSE_VERSION="2.20.2"
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi

    echo "Docker Compose 版本:"
    docker-compose --version

    echo "克隆 GitHub 仓库..."
    git clone https://github.com/rainbowprotocol-xyz/btc_testnet4
    if [ $? -ne 0 ]; then
        echo "克隆仓库失败！"
        exit 1
    fi

    cd btc_testnet4 || { echo "进入目录失败！"; exit 1; }

    echo "启动 Docker 容器..."
    docker-compose up -d

    if [ $? -ne 0 ]; then
        echo "Docker Compose 启动失败。请检查容器日志并处理错误。"
        exit 1
    fi

    echo "进入 Docker 容器并创建钱包..."
    docker exec -it $(docker ps -q -f "name=bitcoind") /bin/bash -c "bitcoin-cli -testnet4 -rpcuser=demo -rpcpassword=demo -rpcport=5000 createwallet walletname"

    echo "获取新钱包地址..."
    docker exec -it $(docker ps -q -f "name=bitcoind") /bin/bash -c "bitcoin-cli -testnet4 -rpcuser=demo -rpcpassword=demo -rpcport=5000 getnewaddress"

    sleep 5

    echo "克隆新的 GitHub 仓库并配置..."
    cd
    git clone https://github.com/rainbowprotocol-xyz/rbo_indexer_testnet && cd rbo_indexer_testnet

    wget https://github.com/rainbowprotocol-xyz/rbo_indexer_testnet/releases/download/v0.0.1-alpha/rbo_worker
    chmod +x rbo_worker

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

    echo "所有步骤已完成。"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    return 0
}

# 连接 Bitcoin Core 并运行索引器的函数
function connect_and_run_indexer() {
    echo "连接 Bitcoin Core 并运行索引器..."

    screen -S Rainbow -dm
    screen -S Rainbow -X stuff $'cd /root/rbo_indexer_testnet && ./rbo_worker worker --rpc http://127.0.0.1:5000 --password demo --username demo --start_height 42000\n'

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

# 停止并删除脚本相关内容的函数
function cleanup_and_remove_script() {
    echo "停止并删除脚本相关 Docker 容器..."

    # 停止并删除 Docker 容器
    docker-compose down

    echo "删除克隆的 GitHub 仓库..."
    rm -rf /root/project/run_btc_testnet4
    rm -rf /root/rbo_indexer_testnet

    echo "所有内容已删除，脚本将退出。"
    exit 0

    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
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
        echo "4. 停止并删除节点"
        read -p "请输入选项 [1-4]: " option
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
                cleanup_and_remove_script
                ;;
            *)
                echo "无效的选项，请选择 [1-4]"
                ;;
        esac
    done
}

# 运行主菜单
main_menu
