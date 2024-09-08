#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/Rainbow.sh"

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

    # 安装 Docker 和 Docker Compose
    echo "安装 Docker 和 Docker Compose..."

    # 安装 Docker
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl start docker
    sudo systemctl enable docker

    # 验证 Docker 安装
    echo "Docker 状态:"
    sudo systemctl status docker --no-pager

    # 检查 Docker Compose 是否安装
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose 未安装，正在安装 Docker Compose..."
        # 安装 Docker Compose
        DOCKER_COMPOSE_VERSION="2.20.2"
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose 已安装。"
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

    # 检查 Docker Compose 启动状态
    if [ $? -ne 0 ]; then
        echo "Docker Compose 启动失败。请检查容器日志并处理错误。"

        # 提示用户处理容器错误后重新启动 Docker Compose
        echo "处理完容器错误后，重新启动 Docker Compose:"
        docker-compose up -d

        # 提示用户按任意键返回主菜单
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
        exit 1
    fi

    # 进入克隆下来的目录
    cd btc_testnet4 || { echo "进入目录失败！"; exit 1; }

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

    # 创建一个新的 screen 会话
    screen -S Rainbow -dm

    # 切换到工作目录并运行 rbo_worker
    echo "在 screen 会话中启动 rbo_worker..."
    screen -S Rainbow -X stuff $'cd /root/rbo_indexer_testnet && ./rbo_worker worker --rpc http://127.0.0.1:5000 --password demo --username demo --start_height 42000\n'

    echo "索引器正在运行。"

    # 提示用户按任意键返回主菜单
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# Get your Principal ID的函数
function edit_principal() {
    # 确保 identity 目录存在
    mkdir -p /root/rbo_indexer_testnet/identity

    # 检查 principal.json 文件是否存在
    if [ -f /root/rbo_indexer_testnet/identity/principal.json ]; then
        echo "导出 principal.json 文件的内容..."

        # 显示 principal.json 文件的内容
        cat /root/rbo_indexer_testnet/identity/principal.json

    else
        echo "文件 /root/rbo_indexer_testnet/identity/principal.json 不存在。"
    fi

    # 提示用户按任意键返回主菜单
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
        echo "3. 获取Principal ID"
        echo "4. 退出"
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
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效的选项，请选择 [1-4]"
                ;;
        esac
    done
}

# 运行主菜单
main_menu
