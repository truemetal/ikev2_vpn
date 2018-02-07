# StrongSwan IKEv2 VPN setup

Hey There

This repo a couple of scripts (and those are perfect manuals at the same time) that lets you deploy a VPN server in a matter of minutes.
It requires a fresh `Ubuntu 16.04`

You're welcome to browse the `.sh` files and hack your own out of those, or just use the commands below to quickly get the job done.

These scripts are based on this cool tutorial article: https://www.digitalocean.com/community/tutorials/how-to-set-up-an-ikev2-vpn-server-with-strongswan-on-ubuntu-16-04 (thanks DigitalOcean!)

### Deploy with Pre Shared Key auth

This script would uuidgen a PSK and print it out to console, where you can copy and hit enter to continue.

After you `ssh your_vpn_machine`, just run this: 
```
curl -L https://raw.githubusercontent.com/truemetal/ikev2_vpn/master/ikev2-deploy-psk.sh -o /tmp/deploy.sh && chmod +x /tmp/deploy.sh && /tmp/deploy.sh
```

### Deploy with cert / username-password auth

The .pem files would be in `~/vpn-certs/`
<br>You can add your users to `/etc/ipsec.secrets`, make sure to reboot afterwards

After you `ssh your_vpn_machine`, just run this: 
```
curl -L https://raw.githubusercontent.com/truemetal/ikev2_vpn/master/ikev2-deploy-certs.sh -o /tmp/deploy.sh && chmod +x /tmp/deploy.sh && /tmp/deploy.sh
```

### Example macOS client setup (PSK)

![macos setup demo](https://github.com/truemetal/ikev2_vpn/raw/master/macos%20setup%20demo%20%28PSK%29.gif)

### Example deployment and macOS client setup (certs)

![deployment and macOS client setup](https://youtu.be/hZS4DHjmfP0)

---

Please feel free to open an issue or drop me a pull request.

Bogdan (Dan) Pashchenko
https://ios-engineer.com
