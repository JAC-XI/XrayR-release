#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_acme() {
    curl https://get.acme.sh | sh
}

install_XrayR() {
    if [[ -e /usr/local/XrayR/ ]]; then
        rm /usr/local/XrayR/ -rf
    fi

    mkdir /usr/local/XrayR/ -p
    cd /usr/local/XrayR/

    # 直接从主分支 zip 包下载
    echo -e "开始安装 XrayR 0.9.5 (从主分支)"
    
    # 下载主分支 zip 包
    wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-master.zip https://github.com/JAC-XI/XrayR/archive/refs/heads/master.zip
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 XrayR 主分支失败，请确保：${plain}"
        echo -e "1. 您的网络可以访问 GitHub"
        echo -e "2. 仓库地址 https://github.com/JAC-XI/XrayR 存在且可访问"
        exit 1
    fi

    # 解压 zip 包
    unzip XrayR-master.zip
    if [[ $? -ne 0 ]]; then
        echo -e "${red}解压 XrayR 失败，请检查下载的文件是否完整${plain}"
        exit 1
    fi
    
    # 进入解压后的目录
    cd XrayR-master/
    
    # 编译或准备 XrayR 二进制文件
    echo -e "准备 XrayR 二进制文件..."
    
    # 检查是否有预编译的二进制文件
    if [[ -f "XrayR" ]]; then
        echo -e "找到预编译的 XrayR 二进制文件"
        chmod +x XrayR
    else
        # 如果没有预编译文件，尝试编译
        echo -e "未找到预编译的二进制文件，尝试编译..."
        
        # 检查是否有 go 环境
        if ! command -v go &> /dev/null; then
            echo -e "${yellow}未找到 Go 环境，尝试安装...${plain}"
            if [[ x"${release}" == x"centos" ]]; then
                yum install -y golang
            else
                apt install -y golang
            fi
        fi
        
        # 尝试编译
        if command -v go &> /dev/null; then
            echo -e "开始编译 XrayR..."
            go build -o XrayR
            if [[ $? -ne 0 ]]; then
                echo -e "${red}编译 XrayR 失败，请确保仓库包含完整的源代码${plain}"
                exit 1
            fi
            chmod +x XrayR
            echo -e "${green}编译成功${plain}"
        else
            echo -e "${red}无法编译 XrayR，请确保 Go 环境已正确安装${plain}"
            exit 1
        fi
    fi
    
    # 复制文件到安装目录
    cp XrayR ../
    
    # 检查并复制配置文件
    if [[ -f "config.yml" ]]; then
        cp config.yml ../
    fi
    
    # 检查并复制数据文件
    if [[ -f "geoip.dat" ]]; then
        cp geoip.dat ../
    fi
    
    if [[ -f "geosite.dat" ]]; then
        cp geosite.dat ../
    fi
    
    # 返回安装目录
    cd ..
    
    # 创建配置目录
    mkdir /etc/XrayR/ -p
    
    # 下载服务文件（已修改为您的仓库）
    rm /etc/systemd/system/XrayR.service -f
    file="https://raw.githubusercontent.com/JAC-XI/XrayR-release/master/XrayR.service"
    wget -q -N --no-check-certificate -O /etc/systemd/system/XrayR.service ${file}
    
    # 如果下载失败，使用内置服务文件
    if [[ $? -ne 0 ]] || [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        echo -e "${yellow}下载服务文件失败，使用内置服务配置${plain}"
        cat > /etc/systemd/system/XrayR.service << EOF
[Unit]
Description=XrayR Service
Documentation=https://github.com/JAC-XI/XrayR
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
ExecStart=/usr/local/XrayR/XrayR -config /etc/XrayR/config.yml
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
MemoryMax=512M
MemorySwapMax=512M
WorkingDirectory=/usr/local/XrayR/
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/etc/XrayR /usr/local/XrayR
ReadOnlyPaths=/
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    systemctl daemon-reload
    systemctl stop XrayR
    systemctl enable XrayR
    echo -e "${green}XrayR 0.9.5${plain} 安装完成，已设置开机自启"
    
    # 复制数据文件到配置目录
    if [[ -f "geoip.dat" ]]; then
        cp geoip.dat /etc/XrayR/
    fi
    
    if [[ -f "geosite.dat" ]]; then
        cp geosite.dat /etc/XrayR/
    fi 

    # 检查配置文件
    if [[ ! -f /etc/XrayR/config.yml ]]; then
        if [[ -f "config.yml" ]]; then
            cp config.yml /etc/XrayR/
        else
            # 创建基本配置文件
            cat > /etc/XrayR/config.yml << EOF
Log:
  Level: warning
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
RouteConfigPath: 
InboundConfigPath: 
OutboundConfigPath: 
ConnectionConfig:
  Handshake: 4
  ConnIdle: 30
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 64
Nodes:
  -
    PanelType: "SSpanel"
    ApiConfig:
      ApiHost: "http://127.0.0.1:667"
      ApiKey: "123"
      NodeID: 41
      NodeType: V2ray
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      SpeedLimit: 0
      DeviceLimit: 0
      RuleListPath: 
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false
      AutoSpeedLimitConfig:
        Limit: 0
        WarnTimes: 0
        LimitSpeed: 0
        LimitDuration: 0
      GlobalDeviceLimitConfig:
        Enable: false
        RedisAddr: 127.0.0.1:6379
        RedisPassword: YOUR PASSWORD
        RedisDB: 0
        Timeout: 5
        Expiry: 60
      EnableFallback: false
      FallBackConfigs: 
        -
          SNI: 
          Alpn: 
          Path: 
          Dest: 80
          ProxyProtocolVer: 0
      CertConfig:
        CertMode: none
        CertDomain: "node1.test.com"
        CertFile: /etc/XrayR/cert/node1.test.com.cert
        KeyFile: /etc/XrayR/cert/node1.test.com.key
        Provider: alidns
        Email: test@me.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
        fi
        echo -e ""
        echo -e "全新安装，请编辑配置文件 /etc/XrayR/config.yml 后启动服务"
    else
        systemctl start XrayR
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 重启成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请稍后使用 XrayR log 查看日志信息${plain}"
        fi
    fi

    # 复制其他配置文件
    for config_file in dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
        if [[ -f "${config_file}" ]] && [[ ! -f /etc/XrayR/${config_file} ]]; then
            cp ${config_file} /etc/XrayR/
        fi
    done
    
    # 下载管理脚本（已修改为您的仓库）
    curl -o /usr/bin/XrayR -Ls https://raw.githubusercontent.com/JAC-XI/XrayR-release/master/XrayR.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${yellow}下载管理脚本失败，请手动下载${plain}"
    else
        chmod +x /usr/bin/XrayR
        ln -s /usr/bin/XrayR /usr/bin/xrayr 2>/dev/null
        chmod +x /usr/bin/xrayr 2>/dev/null
    fi
    
    cd $cur_dir
    rm -f install.sh 2>/dev/null
    echo -e ""
    echo "XrayR 管理脚本使用方法 (兼容使用xrayr执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "XrayR                    - 显示管理菜单 (功能更多)"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR config             - 显示配置文件内容"
    echo "XrayR install            - 安装 XrayR"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
    echo -e "${green}安装完成！当前版本: XrayR 0.9.5${plain}"
}

echo -e "${green}开始安装${plain}"
install_base
# install_acme

# 不再需要版本参数，直接安装
install_XrayR
