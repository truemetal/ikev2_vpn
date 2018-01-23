if [ $(lsb_release -i -s) != "Ubuntu" ] || [ $(lsb_release -r -s) != "16.04" ]; 
        then echo -e "\033[31;7mThis script supports only Ubuntu 16.04. Terminating.\e[0m"; exit -1; 
fi

export REGION=GB
export IP=$(curl -s api.ipify.org)

apt-get update
apt-get -y upgrade
apt-get -y dist-upgrade

# skips interactive dialog for iptables-persistent installer
export DEBIAN_FRONTEND=noninteractive
apt-get -y install strongswan strongswan-plugin-eap-mschapv2 moreutils iptables-persistent

#=========== 
# CERTS
#=========== 

mkdir vpn-certs
cd vpn-certs

ipsec pki --gen --type rsa --size 4096 --outform pem > server-root-key.pem
chmod 600 server-root-key.pem

ipsec pki --self --ca --lifetime 3650 \
--in server-root-key.pem \
--type rsa --dn "C=${REGION}, O=VPN Server, CN=VPN Server Root CA" \
--outform pem > server-root-ca.pem

ipsec pki --gen --type rsa --size 4096 --outform pem > vpn-server-key.pem

ipsec pki --pub --in vpn-server-key.pem \
--type rsa | ipsec pki --issue --lifetime 1825 \
--cacert server-root-ca.pem \
--cakey server-root-key.pem \
--dn "C=${REGION}, O=VPN Server, CN=${IP}" \
--san ${IP} \
--flag serverAuth --flag ikeIntermediate \
--outform pem > vpn-server-cert.pem

cp ./vpn-server-cert.pem /etc/ipsec.d/certs/vpn-server-cert.pem
cp ./vpn-server-key.pem /etc/ipsec.d/private/vpn-server-key.pem

chown root /etc/ipsec.d/private/vpn-server-key.pem
chgrp root /etc/ipsec.d/private/vpn-server-key.pem
chmod 600 /etc/ipsec.d/private/vpn-server-key.pem


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
    ike=aes256-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,3des-sha1!
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=@server_name_or_ip
    leftcert=/etc/ipsec.d/certs/vpn-server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightdns=8.8.8.8,8.8.4.4
    rightsourceip=10.10.10.0/24
    rightsendcert=never
    eap_identity=%identity
EOF

sed -i "s/@server_name_or_ip/${IP}/g" /etc/ipsec.conf

## add secrets to /etc/ipsec.secrets
cat << EOF > /etc/ipsec.secrets

server_name_or_ip : RSA "/etc/ipsec.d/private/vpn-server-key.pem"
your_username %any% : EAP "your_password"
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

reboot
