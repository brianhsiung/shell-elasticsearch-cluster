#！/bin/bash
##############################################################
# File Name: auto_install_es_cluster.sh
# Version: V1.0
# Author: Brian Hsiung
# Created Time : 2022-05-27 9:37:53
# Description: elasticsearch 集群部署脚本
##############################################################

. /etc/init.d/functions

# 获取脚本的绝对路径，本例将elasticsearch上传至/opt
DIR=$(cd $(dirname $0) && pwd)
cd $DIR
# ES 节点名
ES_NODE_NAME=
# ES 集群状态
ES_HEALTH_STATUS=
# 对外服务端口
ES_HTTP_PORT=9200
# 集群通讯端口
ES_CLUSTER_PORT=9300
# ES版本
ES_VERSION="7.4.0"
# ES用户
ES_USER="elastic"
# ES 运行内存
ES_JAVA_OPTS="4g"
# ES 日志目录
ES_LOG="$DIR/logs"
# ES 数据目录
ES_DATA="$DIR/data"
# ES 集群名称
ES_CLUSTER_NAME="elasticsearch_cluster"
# 上传至/opt/目录, 则ES_HOME为/opt/elasticsearch/elasticsearch-7.4.0
ES_HOME="$DIR/elasticsearch-$ES_VERSION"
# ES node
ES_NODE_NAME_LIST=(elastic01 elastic02 elastic03)
# ES 集群的IP, 此处需要根据实际情况修改
ES_IP_LIST=(192.168.157.131 192.168.157.132 192.168.157.133)

# 当前主机IP
HOST_IP=$(hostname -I | awk '{print $1}')
if echo "${ES_IP_LIST[@]}" | grep -w "$HOST_IP" &> /dev/null; then
    echo "当前主机IP为: $HOST_IP"
else
    echo "获取的主机IP: $HOST_IP 不在 ${ES_IP_LIST[@]} 中, 请手动设置 HOST_IP"
    exit 1
fi
# 设置ES节点名称
for ((i=0; i<${#ES_IP_LIST[@]}; i++)); do
    if [ "$HOST_IP" == "${ES_IP_LIST[i]}" ]; then
        ES_NODE_NAME="${ES_NODE_NAME_LIST[i]}"
        echo "ES当前节点名称: $ES_NODE_NAME"
        break
    fi
done

if [ -z "$ES_NODE_NAME" ]; then
    echo "ES_NODE_NAME的值为空"
    exit 1
fi

# 检查服务器上是否安装unzip
if [ ! -f /usr/bin/unzip ]; then
    echo "当前服务器无unzip, 需要先安装"
    exit 1
fi

# 初始化环境
function init_env {
    # 创建用户
    if ! grep -w "$ES_USER" /etc/passwd >/dev/null 2>&1; then
        adduser $ES_USER
    fi

    # 禁用交换分区swap
    is_swap=$(swapon --show)
    if [ -n "$is_swap" ]; then
        swapoff -a
        sed -ri 's/.*swap.*/#&/' /etc/fstab
    fi

    # 禁用transparent_hugepage
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag

    if ! grep '/sys/kernel/mm/transparent_hugepage/enabled' /etc/rc.d/rc.local &> /dev/null; then
        cat >> /etc/rc.d/rc.local << EOF
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi
EOF
    fi
    if ! grep '/sys/kernel/mm/transparent_hugepage/defrag' /etc/rc.d/rc.local &> /dev/null; then
        cat >> /etc/rc.d/rc.local << EOF
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi
EOF
    fi
    chmod +x /etc/rc.d/rc.local

    # vm.max_map_count
    if ! grep -w 'vm.max_map_count' /etc/sysctl.conf &> /dev/null; then
        sysctl -w vm.max_map_count=1048576
        echo "vm.max_map_count = 1048576" >> /etc/sysctl.conf
        sysctl -p
    fi

    # memlock, nofile
    ulimit -SHn 65536
    ulimit -l unlimited

    if ! grep '* soft nofile' /etc/security/limits.conf &> /dev/null; then
        echo '* soft nofile 65536' >> /etc/security/limits.conf
    fi
    if ! grep '* hard nofile' /etc/security/limits.conf &> /dev/null; then
        echo '* hard nofile 131070' >> /etc/security/limits.conf
    fi
    if ! grep '* soft nproc' /etc/security/limits.conf &> /dev/null; then
        echo '* soft nproc 65536' >> /etc/security/limits.conf
    fi
    if ! grep '* hard nproc' /etc/security/limits.conf &> /dev/null; then
        echo '* hard nproc 65536' >> /etc/security/limits.conf
    fi
    if ! grep '* soft memlock' /etc/security/limits.conf &> /dev/null; then
        echo '* soft memlock unlimited' >> /etc/security/limits.conf
    fi
    if ! grep '* hard memlock' /etc/security/limits.conf &> /dev/null; then
        echo '* hard memlock unlimited' >> /etc/security/limits.conf
    fi

    # 开放防火墙端口
    if systemctl status firewalld &> /dev/null; then
        firewall-cmd --zone=public --add-port={$ES_HTTP_PORT/tcp,$ES_CLUSTER_PORT/tcp} --permanent &> /dev/null
        firewall-cmd --reload &> /dev/null
    fi
}

# 安装elasticsearch
function install_elasticsearch {
    # 有些概念理解的还不够深刻: 
    # https://blog.csdn.net/laoyang360/article/details/111148362
    # https://blog.csdn.net/qa76774730/article/details/82778896
    
    [ ! -d $ES_DATA ] && mkdir -p $ES_DATA
    [ ! -d $ES_LOG ] && mkdir -p $ES_LOG

    echo "解压elasticsearch-$ES_VERSION-linux-x86_64.tar.gz && elasticsearch-analysis-ik-$ES_VERSION.zip"
    tar -zxf elasticsearch-$ES_VERSION-linux-x86_64.tar.gz
    unzip elasticsearch-analysis-ik-$ES_VERSION.zip -d $ES_HOME/plugins/analysis-ik &> /dev/null
    chown $ES_USER -R $DIR

    # 设置ES_JAVA_OPTS
    sed -i -e "s/-Xms1g/-Xms$ES_JAVA_OPTS/g" -e "s/-Xmx1g/-Xmx$ES_JAVA_OPTS/g" $ES_HOME/config/jvm.options

    # 不要加任何注释
    cat > $ES_HOME/config/elasticsearch.yml << EOF
cluster.name: $ES_CLUSTER_NAME
node.name: $ES_NODE_NAME
node.master: true
node.data: true
path.data: $ES_DATA
path.logs: $ES_LOG
bootstrap.memory_lock: true
network.host: $HOST_IP
http.port: $ES_HTTP_PORT
transport.tcp.port: $ES_CLUSTER_PORT
discovery.seed_hosts: ["${ES_IP_LIST[0]}:$ES_CLUSTER_PORT", "${ES_IP_LIST[1]}:$ES_CLUSTER_PORT", "${ES_IP_LIST[2]}:$ES_CLUSTER_PORT"]
cluster.initial_master_nodes: ["${ES_NODE_NAME_LIST[0]}", "${ES_NODE_NAME_LIST[1]}", "${ES_NODE_NAME_LIST[2]}"]
gateway.recover_after_nodes: 2
gateway.expected_nodes: 3
gateway.recover_after_time: 5m
discovery.zen.fd.ping_timeout: 300s
discovery.zen.fd.ping_retries: 8
discovery.zen.fd.ping_interval: 30s
discovery.zen.ping_timeout: 180s
#xpack.security.enabled: true
#xpack.security.transport.ssl.enabled: true
#xpack.security.transport.ssl.verification_mode: certificate
#xpack.security.transport.ssl.keystore.path: elastic-certificates.p12
#xpack.security.transport.ssl.truststore.path: elastic-certificates.p12
EOF
	
    # ES 自启动脚本
    cat > /etc/rc.d/init.d/elasticsearch << EOF
#!/bin/bash
#chkconfig:2345 30 70
#description:elasticsearch

ES_HOME=$ES_HOME

case \$1 in
    start)
        ulimit -SHn 65536
        ulimit -l unlimited
        su - $ES_USER -c "\$ES_HOME/bin/elasticsearch -d"
        echo "elasticsearch is started" 
        ;;
    stop)
        ES_PID=\$(ps -ef|grep elasticsearch|grep -v grep|awk '{print \$2}')
        kill -9 \$ES_PID
        echo "elasticsearch is stopped"
        ;;
    restart)
        \$0 stop
        \$0 start
        echo "elasticsearch is started"
        ;;
    *)
        echo "start|stop|restart" 
        ;;
esac
EOF
    chmod +x /etc/rc.d/init.d/elasticsearch
    chkconfig --add elasticsearch
    chkconfig elasticsearch on

    # 使用普通用户启动ES
    su - $ES_USER -c "$ES_HOME/bin/elasticsearch -d"
}

# 等待集群启动
function wait_es_start {
    echo "等待ES集群启动!"
    while :
    do
        sleep 10
        ES_HEALTH_INFO=$(curl http://$HOST_IP:$ES_HTTP_PORT/_cat/health)
        if echo "$ES_HEALTH_INFO" | grep -w 'green' &> /dev/null; then
            ES_HEALTH_STATUS="green"
            echo "集群已启动!"
            break
        elif echo "$ES_HEALTH_INFO" | grep 'missing authentication credentials' &> /dev/null; then
            ES_HEALTH_STATUS="green"
            echo "集群已启动!"
            break
        fi
    done
}

# 初始化集群
function init_cluster {
    # 仅在第一个服务器上生成证书，并将证书拷贝至另外两个服务器
    if [ "${ES_IP_LIST[0]}" == "$HOST_IP" ]; then
        $ES_HOME/bin/elasticsearch-certutil cert -out $ES_HOME/config/elastic-certificates.p12 -pass "" > /dev/null 2>&1
        # 这里需要ssh免密，或者人为输入其它服务器密码（未验证输入密码的情况）
        for ((i=1; i<${#ES_IP_LIST[@]}; i++)); do
            echo "拷贝 elastic-certificates.p12 至 ${ES_IP_LIST[i]}:$ES_HOME/config 目录"
            scp $ES_HOME/config/elastic-certificates.p12 root@${ES_IP_LIST[i]}:$ES_HOME/config
        done
    fi

    # 等待elastic-certificates.p12拷贝至另外两台服务器
    while :
    do
        sleep 10
        if [ -f $ES_HOME/config/elastic-certificates.p12 ]; then
            chown $ES_USER -R $ES_HOME/config/elastic-certificates.p12
            # sed 's/^xpack/#&/g' elasticsearch.yml
            sed -i 's/#//g' $ES_HOME/config/elasticsearch.yml
            echo "重启ES, 启用xpack"
            ps -ef | grep elasticsearch | grep -v grep | awk '{print $2}' | xargs kill -9
            su - $ES_USER -c "$ES_HOME/bin/elasticsearch -d" &> /dev/null
            break
        fi
    done

    # 自动生成密码
    if [ "${ES_IP_LIST[0]}" == "$HOST_IP" ]; then
        ES_HEALTH_STATUS=
        wait_es_start
        if [ "$ES_HEALTH_STATUS" == "green" ]; then	
            $ES_HOME/bin/elasticsearch-setup-passwords auto
        fi
    fi
}

init_env
install_elasticsearch

wait_es_start

# echo "启用ES密码"
if [ "$ES_HEALTH_STATUS" == "green" ]; then
   init_cluster
fi
