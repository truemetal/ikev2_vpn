function bail_out {
	echo -e "\033[31;7mThis script supports only Ubuntu 16.04. Terminating.\e[0m"
	exit 1
}

if ! [ -x "$(command -v lsb_release)" ]; then
	bail_out
fi

if [ $(lsb_release -i -s) != "Ubuntu" ] || [ $(lsb_release -r -s) != "16.04" ]; then 
	bail_out
fi

export SHARED_KEY=$(uuidgen)
export IP=$(curl -s api.ipify.org)

echo "Your shared key (PSK) is $SHARED_KEY and your IP is $IP"
echo -e "Press enter to continue...\n"; read

apt-get update
apt-get -y upgrade
apt-get -y dist-upgrade

# skips interactive dialog for iptables-persistent installer
export DEBIAN_FRONTEND=noninteractive
apt-get -y install strongswan strongswan-plugin-eap-mschapv2 moreutils iptables-persistent

#=========== 
# STRONG SWAN CONFIG
#===========

## Create /etc/ipsec.conf

cat << EOF > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    ike=aes256-sha1-modp1024,3des-sha1-modp1024!,aes256-sha2_256
    esp=aes256-sha1,3des-sha1!
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=%any
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightdns=8.8.8.8,8.8.4.4
    rightsourceip=10.10.10.0/24
    authby=secret
EOF

sed -i "s/@server_name_or_ip/${IP}/g" /etc/ipsec.conf

## add secrets to /etc/ipsec.secrets
cat << EOF > /etc/ipsec.secrets

: PSK $SHARED_KEY
EOF

sed -i "s/server_name_or_ip/${IP}/g" /etc/ipsec.secrets

#=========== 
# IPTABLES + FIREWALL
#=========== 

# remove if there were UFW rules
ufw disable
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -F
iptables -Z

# ssh rules

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# loopback 
iptables -A INPUT -i lo -j ACCEPT

# ipsec

iptables -A INPUT -p udp --dport  500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT

iptables -A FORWARD --match policy --pol ipsec --dir in  --proto esp -s 10.10.10.10/24 -j ACCEPT
iptables -A FORWARD --match policy --pol ipsec --dir out --proto esp -d 10.10.10.10/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.10.10.10/24 -o eth0 -m policy --pol ipsec --dir out -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.10.10.10/24 -o eth0 -j MASQUERADE
iptables -t mangle -A FORWARD --match policy --pol ipsec --dir in -s 10.10.10.10/24 -o eth0 -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360

iptables -A INPUT -j DROP
iptables -A FORWARD -j DROP

netfilter-persistent save
netfilter-persistent reload

#=======
# CHANGES TO SYSCTL (/etc/sysctl.conf)
#=======

sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/" /etc/sysctl.conf
sed -i "s/#net.ipv4.conf.all.accept_redirects = 0/net.ipv4.conf.all.accept_redirects = 0/" /etc/sysctl.conf
sed -i "s/#net.ipv4.conf.all.send_redirects = 0/net.ipv4.conf.all.send_redirects = 0/" /etc/sysctl.conf
echo "" >> /etc/sysctl.conf
echo "" >> /etc/sysctl.conf
echo "net.ipv4.ip_no_pmtu_disc = 1" >> /etc/sysctl.conf

#=======
# REBOOT
#=======

echo ""
echo "Looks like the script has finished successfully."
echo "The system will now be re-booted and your VPN server should be up and running right after that."
echo ""

reboot
