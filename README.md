# shell-elasticsearch-cluster

#### 介绍
> 一键部署三节点ES Cluster，版本为7.4.0，下载地址：https://www.elastic.co/cn/downloads/past-releases#elasticsearch， 根据实际情况修改 `ES_IP_LIST`，`ES_JAVA_OPTS` ，ES Cluster默认安装目录与脚本一致，
> 可根据情况定义 `ES_DATA`, `ES_LOG` 目录

服务器规格：
| 服务器IP | 服务器规格 | 生成私钥 |
| :------- | :--------| :-------|
| 192.168.157.131 | 1核4g | 是 |
| 192.168.157.132 | 1核4g | 否 |
| 192.168.157.133 | 1核4g | 否 |

#### 安装教程

1. 生成私钥
> 脚本默认在第一台服务器，也就是 **ES_IP_LIST** 的第一个元素中生成私钥，并将公钥拷贝至另外两台服务器
- 在第一台服务器 `192.168.157.131` 的 `root` 目录执行以下命令生成私钥，一路按 `enter` 键即可
```shell
cd /root
ssh-keygen -t rsa
```
- 将生成的公钥拷贝至其余两台服务器
```shell
ssh-copy-id -i ~/.ssh/id_dsa.pub root@192.168.157.132
ssh-copy-id -i ~/.ssh/id_dsa.pub root@192.168.157.133
```

2.  本例中脚本与二进制文件均存放于 `/opt/elasticsearch` 目录，默认情况下 ES Cluster 就部署在此目录, 如下图:
![image-20220529222213404](https://brianhsiung.oss-cn-hangzhou.aliyuncs.com/img/image-20220529222213404.png)

3.  在每台服务器上执行以下命令进行安装
```shell
cd /opt/elasticsearch/
chmod +x auto_install_es_cluster.sh
./auto_install_es_cluster.sh
```

4. 在每台服务器上的脚本执行完成后，默认情况下第一台服务器(`ES_IP_LIST`的第一个元素)会有以下提示，输入 **y** 则自动生成密码，需要妥善保存账号与之对应的密码
![image-20220529220140209](https://brianhsiung.oss-cn-hangzhou.aliyuncs.com/img/image-20220529220140209.png)

5. 在最后一步，如果要自定义密码则输入 **N**，然后执行以下命令自定义密码
```shell
/opt/elasticsearch/elasticsearch-7.4.0/bin/elasticsearch-setup-passwords interactive
```
![image-20220529222024837](https://brianhsiung.oss-cn-hangzhou.aliyuncs.com/img/image-20220529222024837.png)

6. 验证集群健康
```shell
# 查看集群健康状态，status 为 green 时表示健康
curl http://elastic:mypasswd@192.168.157.132:9200/_cat/health?v
# 查看集群节点情况，master 带 * 则表示 master 节点
curl http://elastic:mypasswd@192.168.157.132:9200/_cat/nodes?v
```
![image-20220529224415179](https://brianhsiung.oss-cn-hangzhou.aliyuncs.com/img/image-20220529224415179.png)

7. 删除安装包
```shell
rm -f elasticsearch-*.gz elasticsearch-*.zip
```