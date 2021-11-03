#! /bin/bash
#判断是否具有root权限
root_need() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error:This script must be run as root!" 1>&2
        exit 1
    fi
}

#检查系统分支及版本(主要是：分支->>版本>>决定命令格式)
check_release() {
    if uname -a | grep el7  ; then
        release="centos7"
    elif uname -a | grep el6 ; then
        release="centos6"
        yum install ipset -y
    elif cat /etc/issue |grep -i ubuntu ; then
        release="ubuntu"
        apt install ipset -y
    fi
}

#安装必要的软件(wget),并下载日本IP网段文件(最后将局域网地址也放进去)
get_japan_ip() {
	#安装必要的软件(wget)
	rpm --help >/dev/null 2>&1 && rpm -qa |grep wget >/dev/null 2>&1 ||yum install -y wget ipset >/dev/null 2>&1 
	dpkg --help >/dev/null 2>&1 && dpkg -l |grep wget >/dev/null 2>&1 ||apt-get install wget ipset -y >/dev/null 2>&1

	#该文件由IPIP维护更新，大约一月一次更新(也可以用我放在国内的存储的版本，2018-9-8日版)
	[ -f japan.txt ] && mv japan.txt japan.txt.old
	wget https://raw.githubusercontent.com/opbnma/Japan-ip/main/japan.txt
	cat japan.txt |grep 'js-file-line">' |awk -F'js-file-line">' '{print $2}' |awk -F'<' '{print $1}' >> japan_ip.txt
	rm -rf japan.txt
	#wget https://qiniu.wsfnk.com/japan_ip.txt

	#放行局域网地址
	echo "192.168.0.0/18" >> japan_ip.txt
	echo "10.0.0.0/8" >> japan_ip.txt
	echo "172.16.0.0/12" >> japan_ip.txt
}

#只允许国内IP访问
ipset_only_china() {
	echo "ipset create whitelist-japan hash:net hashsize 10000 maxelem 1000000" > /etc/ip-black.sh
	for i in $( cat japan_ip.txt )
	do
        	echo "ipset add whitelist-japan $i" >> /etc/ip-black.sh
	done
	echo "iptables -I INPUT -m set --match-set whitelist-japan src -j ACCEPT" >> /etc/ip-black.sh
	#拒绝非国内和内网地址发起的tcp连接请求（tcp syn 包）（注意，只是屏蔽了入向的tcp syn包，该主机主动访问国外资源不用影响）
	echo "iptables  -A INPUT -p tcp --syn -m connlimit --connlimit-above 0 -j DROP" >> /etc/ip-black.sh
	#拒绝非国内和内网发起的ping探测（不影响本机ping外部主机）
	echo "iptables  -A INPUT -p icmp -m icmp --icmp-type 8 -j DROP" >> /etc/ip-black.sh
	#echo "iptables -A INPUT -j DROP" >> /etc/ip-black.sh
	rm -rf japan_ip.txt
}

run_setup() {
	chmod +x /etc/rc.local
	sh /etc/ip-black.sh
	rm -rf /etc/ip-black.sh
	#下面这句主要是兼容centos6不能使用"-f"参数
	ipset save whitelist-china -f /etc/ipset.conf || ipset save whitelist-china > /etc/ipset.conf
	[ $release = centos7 ] && echo "ipset restore -f /etc/ipset.conf" >> /etc/rc.local
	[ $release = centos6 ] && echo "ipset restore < /etc/ipset.conf" >> /etc/rc.local
	echo "iptables -I INPUT -m set --match-set whitelist-china src -j ACCEPT" >> /etc/rc.local
	echo "iptables  -A INPUT -p tcp --syn -m connlimit --connlimit-above 0 -j DROP" >> /etc/rc.local
	echo "iptables  -A INPUT -p icmp -m icmp --icmp-type 8 -j DROP" >> /etc/rc.local
	#echo "iptables -A INPUT -j DROP" >> /etc/rc.local
}

main() {
	check_release
	get_japan_ip
	ipset_only_china

case "$release" in
centos6)
	run_setup
	;;
centos7)
	chmod +x /etc/rc.d/rc.local
	run_setup
	;;
ubuntu)
	sed -i '/exit 0/d' /etc/rc.local
	run_setup
	echo "exit 0" >> /etc/rc.local
	;;
esac
}
main
